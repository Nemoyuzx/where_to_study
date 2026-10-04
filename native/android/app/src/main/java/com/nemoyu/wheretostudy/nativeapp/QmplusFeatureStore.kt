package com.nemoyu.wheretostudy.nativeapp

import android.util.AtomicFile
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.RandomAccessFile

/** Non-secret policy mirror. Fresh reads and revision binding work across the
 * main app and :qmplus processes; SharedPreferences cannot provide that fence. */
internal data class QmplusFeatureRecord(val revision: Long = 0, val enabled: Boolean = false)

internal object QmplusFeatureMigrationPolicy {
    fun resolve(mirror: QmplusFeatureRecord, hadSnapshot: Boolean, savedLoginEnabled: Boolean,
        resolvePublicPreference: (Boolean) -> Boolean): Boolean =
        resolvePublicPreference(if (mirror.revision > 0) mirror.enabled else hadSnapshot || savedLoginEnabled)
}

internal object QmplusFeatureOwnerPolicy {
    fun acceptsStop(connectionToken: String?, revision: Long, requestedToken: String?, requestedRevision: Long): Boolean =
        if (requestedToken != null) connectionToken == requestedToken
        else requestedRevision < 0 || requestedRevision == revision
}

internal class QmplusFeatureStore(private val directory: File,
    private val readOverride: (() -> ByteArray?)? = null,
    private val writeOverride: ((ByteArray) -> Unit)? = null,
) {
    private val recordFile by lazy { AtomicFile(File(directory, "qmplus_enabled.bin")) }
    private val lockFile = File(directory, "qmplus_enabled.lock")

    fun status(): QmplusFeatureRecord = locked { readRecord() }

    fun isCurrent(expected: QmplusFeatureRecord): Boolean =
        expected.enabled && runCatching { status() == expected }.getOrDefault(false)

    fun <T> whileCurrent(expected: QmplusFeatureRecord, work: () -> T): T = locked {
        check(expected.enabled && readRecord() == expected) { "QMplus feature owner was retired." }
        work()
    }

    fun setEnabled(enabled: Boolean, renewOwner: Boolean = false): QmplusFeatureRecord = locked {
        val previous = readRecord()
        val next = QmplusFeatureRecord(if (!renewOwner && previous.enabled == enabled) previous.revision
            else Math.addExact(previous.revision, 1), enabled)
        val buffer = ByteArrayOutputStream()
        DataOutputStream(buffer).use { output ->
            output.writeInt(1); output.writeLong(next.revision); output.writeBoolean(enabled)
        }
        val bytes = buffer.toByteArray()
        if (writeOverride != null) writeOverride.invoke(bytes) else {
            val output = recordFile.startWrite()
            try { output.write(bytes); output.fd.sync(); recordFile.finishWrite(output) }
            catch (error: Exception) { recordFile.failWrite(output); throw error }
        }
        check(readRecord() == next) { "QMplus feature state was not persisted." }
        next
    }

    private fun readRecord(): QmplusFeatureRecord {
        val bytes = if (readOverride != null) readOverride.invoke() else {
            val input = try { recordFile.openRead() } catch (_: FileNotFoundException) { return QmplusFeatureRecord() }
            input.use { require(it.channel.size() <= 64); it.readBytes() }
        } ?: return QmplusFeatureRecord()
        require(bytes.size <= 64)
        return DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            require(input.readInt() == 1)
            val revision = input.readLong(); require(revision >= 0)
            val enabled = input.readUnsignedByte(); require(enabled in 0..1 && input.read() == -1)
            QmplusFeatureRecord(revision, enabled == 1)
        }
    }

    private fun <T> locked(operation: () -> T): T = synchronized(processLock) {
        check(directory.isDirectory || directory.mkdirs())
        RandomAccessFile(lockFile, "rw").use { file ->
            file.channel.lock().use { operation() }
        }
    }

    private companion object { val processLock = Any() }
}
