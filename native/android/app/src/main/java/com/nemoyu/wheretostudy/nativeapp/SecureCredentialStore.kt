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
        val ciphertext = cipher.doFinal(payload)

        preferences.edit()
            .putString(IV_KEY, Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString(PAYLOAD_KEY, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .apply()
    }

    fun load(): Credentials? {
        val encodedIv = preferences.getString(IV_KEY, null) ?: return null
        val encodedPayload = preferences.getString(PAYLOAD_KEY, null) ?: return null
        return runCatching {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            val iv = Base64.decode(encodedIv, Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
            val plaintext = cipher.doFinal(Base64.decode(encodedPayload, Base64.NO_WRAP))
            val objectValue = JSONObject(String(plaintext, StandardCharsets.UTF_8))
            Credentials(
                account = objectValue.optString("account"),
                password = objectValue.optString("password"),
            )
        }.getOrNull()
    }

    fun clear() {
        preferences.edit().clear().apply()
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
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
            preferences.edit().putString(CAMPUS_KEY, value).apply()
        }

    private companion object {
        const val PREFERENCES_NAME = "app_preferences_v1"
        const val CAMPUS_KEY = "campus_id"
    }
}
