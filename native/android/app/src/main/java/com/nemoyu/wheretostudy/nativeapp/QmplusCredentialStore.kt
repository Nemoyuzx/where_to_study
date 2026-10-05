package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.RandomAccessFile
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/** The QM domain is never the academic credential domain, a DTO, an Intent, or a log value. */
internal class QmplusSavedLogin(val account: String, val password: CharArray, val revision: Long) {
    fun erase() { password.fill('\u0000') }
    override fun toString(): String = "QmplusSavedLogin([redacted])"
}

internal data class QmplusCredentialStatus(val revision: Long = 0, val enabled: Boolean = false)

internal object QmplusCredentialLimits {
    const val MAXIMUM_RECORD_BYTES = 32 * 1024
    const val MAXIMUM_ACCOUNT_CHARACTERS = 320
    const val MAXIMUM_PASSWORD_CHARACTERS = 2048
    fun valid(account: String, password: CharArray): Boolean = account.trim().isNotEmpty() &&
        Regex("^[^\\s@]+@[^\\s@]+$").matches(account.trim()) &&
        account.length <= MAXIMUM_ACCOUNT_CHARACTERS && password.isNotEmpty() &&
        password.size <= MAXIMUM_PASSWORD_CHARACTERS && '\u0000' !in account && '\u0000' !in password
}

/** App-context worker; no Activity/View, and no secret survives a dropped delivery or close. */
internal class QmplusAuthCredentialWorker(private val store: QmplusCredentialStore) : QmplusAuthCredentials {
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    private val pendingSecrets = ConcurrentHashMap<Any, QmplusSavedLogin>()

    override fun authorized(revision: Long, completion: (Boolean) -> Unit) {
        submit {
            val allowed = runCatching { store.status() == QmplusCredentialStatus(revision, true) }.getOrDefault(false)
            handler.post { if (!closed.get()) completion(allowed) }
        }
    }

    override fun account(revision: Long, completion: (String?) -> Unit) {
        submit {
            val saved = runCatching { store.load(revision) }.getOrNull()
            val account = try { saved?.account } finally { saved?.erase() }
            handler.post { if (!closed.get()) completion(account) }
        }
    }

    override fun password(revision: Long, completion: (QmplusSavedLogin?) -> Unit) {
        submit {
            val saved = runCatching { store.load(revision) }.getOrNull()
            if (saved == null) { handler.post { if (!closed.get()) completion(null) }; return@submit }
            val token = Any()
            pendingSecrets[token] = saved
            if (closed.get()) { pendingSecrets.remove(token)?.erase(); return@submit }
            val posted = handler.post {
                val login = pendingSecrets.remove(token) ?: return@post
                try { if (!closed.get()) completion(login) } finally { login.erase() }
            }
            if (!posted) pendingSecrets.remove(token)?.erase()
        }
    }

    override fun close() {
        closed.set(true)
        pendingSecrets.values.forEach(QmplusSavedLogin::erase); pendingSecrets.clear()
        handler.removeCallbacksAndMessages(null); worker.shutdownNow()
    }

    private fun submit(operation: () -> Unit) {
        if (closed.get()) return
        try { worker.execute { if (!closed.get()) operation() } } catch (_: RejectedExecutionException) { /* Owner closed. */ }
    }
}

/** Fresh disk reads plus an OS file lock: SharedPreferences is not multi-process safe. */
internal class QmplusCredentialStore(context: Context, private val testDomain: String? = null) {
    private val directory = context.applicationContext.noBackupFilesDir
    private val domain = testDomain?.takeIf { BuildConfig.DEBUG && it.matches(Regex("test_[a-z0-9_]{1,48}")) }
        ?: "qmplus_saved_login_v1"
    private val file = AtomicFile(File(directory, "$domain.bin"))
    private val lockFile = File(directory, "$domain.lock")
    private val keyAlias = "where_to_study.qmplus.$domain"

    fun status(): QmplusCredentialStatus = locked { readRecord().status }

    fun save(account: String, password: CharArray, explicitOptIn: Boolean, expectedRevision: Long) = locked {
        require(explicitOptIn && QmplusCredentialLimits.valid(account, password)) { "Invalid QM saved-login request." }
        val previous = readRecord()
        check(previous.status.revision == expectedRevision) { "QM saved-login request was invalidated." }
        val next = QmplusCredentialStatus(Math.addExact(expectedRevision, 1), true)
        val buffer = object : ByteArrayOutputStream() { fun erase() { buf.fill(0) } }
        val plaintext = try {
            DataOutputStream(buffer).use { output ->
                output.writeUTF(account.trim())
                output.writeInt(password.size)
                password.forEach { output.writeChar(it.code) }
            }
            buffer.toByteArray()
        } finally { buffer.erase() }
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, secretKey(create = true))
            cipher.updateAAD(aad(next))
            writeRecord(Record(next, cipher.iv, cipher.doFinal(plaintext)))
        } finally { plaintext.fill(0) }
        next
    }

    /** Only call for a verified official password/username document and explicit saved opt-in. */
    fun load(expectedRevision: Long): QmplusSavedLogin? = locked {
        val record = readRecord()
        if (!record.status.enabled || record.status.revision != expectedRevision) return@locked null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(create = false), GCMParameterSpec(128, record.iv))
        cipher.updateAAD(aad(record.status))
        val plaintext = cipher.doFinal(record.ciphertext)
        try {
            DataInputStream(ByteArrayInputStream(plaintext)).use { input ->
                val account = input.readUTF()
                val count = input.readInt()
                require(count in 1..QmplusCredentialLimits.MAXIMUM_PASSWORD_CHARACTERS)
                val password = CharArray(count)
                var transferred = false
                try {
                    password.indices.forEach { password[it] = input.readChar() }
                    require(input.available() == 0 && QmplusCredentialLimits.valid(account, password)) { "Invalid QM saved-login record." }
                    QmplusSavedLogin(account, password, record.status.revision).also { transferred = true }
                } finally { if (!transferred) password.fill('\u0000') }
            }
        } finally { plaintext.fill(0) }
    }

    /** A durable disabled tombstone stops delayed reads/saves in either app process. */
    fun clear(): QmplusCredentialStatus = locked {
        val next = QmplusCredentialStatus(Math.addExact(readRecord().status.revision, 1), false)
        writeRecord(Record(next))
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(keyAlias)) keyStore.deleteEntry(keyAlias)
        next
    }

    private data class Record(val status: QmplusCredentialStatus = QmplusCredentialStatus(),
        val iv: ByteArray = byteArrayOf(), val ciphertext: ByteArray = byteArrayOf())

    private fun readRecord(): Record {
        val input = try { file.openRead() } catch (_: FileNotFoundException) { return Record() }
        return input.use { stream ->
            require(stream.channel.size() <= QmplusCredentialLimits.MAXIMUM_RECORD_BYTES)
            DataInputStream(stream).use record@{ data ->
                require(data.readInt() == 1)
                val revision = data.readLong(); require(revision >= 0)
                val enabled = data.readBoolean()
                if (!enabled) { require(data.read() == -1); return@record Record(QmplusCredentialStatus(revision, false)) }
                val ivLength = data.readInt(); require(ivLength == 12)
                val iv = ByteArray(ivLength); data.readFully(iv)
                val length = data.readInt(); require(length in 16..(QmplusCredentialLimits.MAXIMUM_RECORD_BYTES - 64))
                val ciphertext = ByteArray(length); data.readFully(ciphertext); require(data.read() == -1)
                Record(QmplusCredentialStatus(revision, true), iv, ciphertext)
            }
        }
    }

    private fun writeRecord(record: Record) {
        val output = file.startWrite()
        try {
            val data = DataOutputStream(output)
            data.writeInt(1); data.writeLong(record.status.revision); data.writeBoolean(record.status.enabled)
            if (record.status.enabled) {
                data.writeInt(record.iv.size); data.write(record.iv)
                data.writeInt(record.ciphertext.size); data.write(record.ciphertext)
            }
            data.flush(); output.fd.sync(); file.finishWrite(output)
            val committed = readRecord()
            check(committed.status == record.status && committed.iv.contentEquals(record.iv) &&
                committed.ciphertext.contentEquals(record.ciphertext)) { "QM saved-login write failed." }
        } catch (error: Exception) { file.failWrite(output); throw error }
    }

    private fun secretKey(create: Boolean): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        check(create) { "QM saved-login key is unavailable." }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true).build())
        return generator.generateKey()
    }

    private fun aad(status: QmplusCredentialStatus): ByteArray =
        "qmplus-saved-login-v1:${status.revision}:${status.enabled}".toByteArray(StandardCharsets.US_ASCII)

    private fun <T> locked(operation: () -> T): T = synchronized(processLock) {
        check(directory.isDirectory || directory.mkdirs())
        RandomAccessFile(lockFile, "rw").use { handle -> handle.channel.lock().use { operation() } }
    }

    private companion object { val processLock = Any() }
}
