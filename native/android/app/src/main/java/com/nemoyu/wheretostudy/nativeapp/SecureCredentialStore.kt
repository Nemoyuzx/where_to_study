package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class Credentials(
    val account: String,
    val password: String,
)

internal class CredentialUpdateException(message: String) : IllegalArgumentException(message)

internal object CredentialUpdateLogic {
    fun resolve(
        saved: Credentials?,
        requestedAccount: String,
        enteredPassword: String,
    ): Credentials {
        val account = requestedAccount.trim()
        if (account.isEmpty()) {
            if (enteredPassword.isNotEmpty()) {
                throw CredentialUpdateException("请输入教务账号。")
            }
            return Credentials("", "")
        }
        if (enteredPassword.isNotEmpty()) return Credentials(account, enteredPassword)
        if (saved != null && saved.account == account) return saved
        throw CredentialUpdateException("更换教务账号时必须输入新密码。")
    }

    fun changesAccount(saved: Credentials?, resolved: Credentials): Boolean =
        saved?.account?.trim().orEmpty() != resolved.account
}

class SecureCredentialStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun save(credentials: Credentials) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val payload = JSONObject()
            .put("account", credentials.account)
            .put("password", credentials.password)
            .toString()
            .toByteArray(StandardCharsets.UTF_8)
        val ciphertext = try {
            cipher.doFinal(payload)
        } finally {
            payload.fill(0)
        }

        val saved = preferences.edit()
            .putString(IV_KEY, Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString(PAYLOAD_KEY, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .commit()
        if (!saved) throw IllegalStateException("无法安全保存本地凭据。")
    }

    fun load(): Credentials? {
        val encodedIv = preferences.getString(IV_KEY, null) ?: return null
        val encodedPayload = preferences.getString(PAYLOAD_KEY, null) ?: return null
        return runCatching {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            val iv = Base64.decode(encodedIv, Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
            val plaintext = cipher.doFinal(Base64.decode(encodedPayload, Base64.NO_WRAP))
            try {
                val objectValue = JSONObject(String(plaintext, StandardCharsets.UTF_8))
                Credentials(
                    account = objectValue.optString("account"),
                    password = objectValue.optString("password"),
                )
            } finally {
                plaintext.fill(0)
            }
        }.getOrNull()
    }

    fun clear() {
        if (!preferences.edit().clear().commit()) {
            throw IllegalStateException("无法清除本地凭据记录。")
        }
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        if (keyStore.containsAlias(KEY_ALIAS)) keyStore.deleteEntry(KEY_ALIAS)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        // Deliberately not bound to device unlock: the 07:00 classroom refresh
        // and 07:30 course summary jobs run while the device is still locked,
        // and the key is already Keystore-only with backups excluded. Binding
        // to unlock would silently break those background features.
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        const val KEY_ALIAS = "where_to_study.credentials.v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val PREFERENCES_NAME = "secure_credentials_v1"
        const val IV_KEY = "iv"
        const val PAYLOAD_KEY = "payload"
    }
}

class AppPreferences(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    var campusID: String
        get() = preferences.getString(CAMPUS_KEY, AppMetadata.campuses.first().id)
            ?: AppMetadata.campuses.first().id
        set(value) {
            save(CAMPUS_KEY, value)
        }

    var termID: String
        get() = preferences.getString(TERM_ID_KEY, AppMetadata.defaultTermID)
            ?: AppMetadata.defaultTermID
        set(value) {
            save(TERM_ID_KEY, value)
        }

    var termStartDate: String
        get() = preferences.getString(TERM_START_DATE_KEY, AppMetadata.defaultTermStartDate)
            ?: AppMetadata.defaultTermStartDate
        set(value) {
            save(TERM_START_DATE_KEY, value)
        }

    var dailyCourseNotificationsEnabled: Boolean
        get() = preferences.getBoolean(DAILY_COURSE_NOTIFICATIONS_KEY, false)
        set(value) {
            if (!preferences.edit().putBoolean(DAILY_COURSE_NOTIFICATIONS_KEY, value).commit()) {
                throw IllegalStateException("无法保存课程摘要通知设置。")
            }
        }

    fun clear() {
        if (!preferences.edit().clear().commit()) {
            throw IllegalStateException("无法清除本地偏好。")
        }
    }

    private fun save(key: String, value: String) {
        if (!preferences.edit().putString(key, value).commit()) {
            throw IllegalStateException("无法保存本地偏好。")
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "app_preferences_v1"
        const val CAMPUS_KEY = "campus_id"
        const val TERM_ID_KEY = "term_id"
        const val TERM_START_DATE_KEY = "term_start_date"
        const val DAILY_COURSE_NOTIFICATIONS_KEY = "daily_course_notifications_enabled"
    }
}
