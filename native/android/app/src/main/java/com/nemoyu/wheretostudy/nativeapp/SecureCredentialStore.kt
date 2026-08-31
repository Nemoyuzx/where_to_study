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
    @Volatile
    private var favoriteDeadlineCache: List<PublicDeadlineItem>? = null

    var campusID: String
        get() = preferences.getString(CAMPUS_KEY, AppMetadata.campuses.first().id)
            ?: AppMetadata.campuses.first().id
        set(value) {
            save(CAMPUS_KEY, value)
        }

    var languageCode: String
        get() = preferences.getString(LANGUAGE_KEY, AppLanguage.SYSTEM.code)
            ?.takeIf { value -> AppLanguage.entries.any { it.code == value } }
            ?: AppLanguage.SYSTEM.code
        set(value) {
            save(
                LANGUAGE_KEY,
                AppLanguage.entries.firstOrNull { it.code == value }?.code
                    ?: AppLanguage.SYSTEM.code,
            )
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

    var automaticTermDetectionEnabled: Boolean
        get() = preferences.getBoolean(AUTOMATIC_TERM_DETECTION_KEY, true)
        set(value) {
            save(AUTOMATIC_TERM_DETECTION_KEY, value)
        }

    var widgetShowsLocation: Boolean
        get() = preferences.getBoolean(WIDGET_SHOWS_LOCATION_KEY, true)
        set(value) {
            save(WIDGET_SHOWS_LOCATION_KEY, value)
        }

    var widgetShowsTeacher: Boolean
        get() = preferences.getBoolean(WIDGET_SHOWS_TEACHER_KEY, true)
        set(value) {
            save(WIDGET_SHOWS_TEACHER_KEY, value)
        }

    var widgetCourseLimit: Int
        get() = preferences.getInt(WIDGET_COURSE_LIMIT_KEY, 4).coerceIn(1, 6)
        set(value) {
            save(WIDGET_COURSE_LIMIT_KEY, value.coerceIn(1, 6))
        }

    var dailyCourseNotificationsEnabled: Boolean
        get() = preferences.getBoolean(DAILY_COURSE_NOTIFICATIONS_KEY, false)
        set(value) {
            if (!preferences.edit().putBoolean(DAILY_COURSE_NOTIFICATIONS_KEY, value).commit()) {
                throw IllegalStateException("无法保存课程摘要通知设置。")
            }
        }

    var weatherEnabled: Boolean
        get() = preferences.getBoolean(WEATHER_ENABLED_KEY, true)
        set(value) {
            save(WEATHER_ENABLED_KEY, value)
        }

    var almanacEnabled: Boolean
        get() = preferences.getBoolean(ALMANAC_ENABLED_KEY, true)
        set(value) {
            save(ALMANAC_ENABLED_KEY, value)
        }

    var competitionDeadlinesEnabled: Boolean
        get() = preferences.getBoolean(COMPETITION_DEADLINES_ENABLED_KEY, true)
        set(value) {
            save(COMPETITION_DEADLINES_ENABLED_KEY, value)
        }

    var conferenceDeadlinesEnabled: Boolean
        get() = preferences.getBoolean(CONFERENCE_DEADLINES_ENABLED_KEY, true)
        set(value) {
            save(CONFERENCE_DEADLINES_ENABLED_KEY, value)
        }

    var schoolContestNoticesEnabled: Boolean
        get() = preferences.getBoolean(SCHOOL_CONTEST_NOTICES_ENABLED_KEY, true)
        set(value) {
            save(SCHOOL_CONTEST_NOTICES_ENABLED_KEY, value)
        }

    var summerCampDeadlinesEnabled: Boolean
        get() = preferences.getBoolean(SUMMER_CAMP_DEADLINES_ENABLED_KEY, true)
        set(value) {
            save(SUMMER_CAMP_DEADLINES_ENABLED_KEY, value)
        }

    var hackathonDeadlinesEnabled: Boolean
        get() = preferences.getBoolean(HACKATHON_DEADLINES_ENABLED_KEY, true)
        set(value) {
            save(HACKATHON_DEADLINES_ENABLED_KEY, value)
        }

    var customDeadlinesEnabled: Boolean
        get() = preferences.getBoolean(CUSTOM_DEADLINES_ENABLED_KEY, false)
        set(value) {
            save(CUSTOM_DEADLINES_ENABLED_KEY, value)
        }

    var customDeadlinesURL: String
        get() = preferences.getString(CUSTOM_DEADLINES_URL_KEY, "").orEmpty()
        set(value) {
            save(CUSTOM_DEADLINES_URL_KEY, value.trim())
        }

    val enabledCustomDeadlineURL: String?
        get() = customDeadlinesURL.takeIf { customDeadlinesEnabled && it.isNotBlank() }
            ?.let { raw ->
                runCatching { CustomDeadlineFeedURLValidator.validatedURI(raw).toString() }
                    .getOrNull()
            }

    val favoriteDeadlines: List<PublicDeadlineItem>
        get() = favoriteDeadlineCache ?: synchronized(this) {
            favoriteDeadlineCache ?: PublicDeadlineItemJsonCodec.decode(
                preferences.getString(FAVORITE_DEADLINES_KEY, null),
            ).also { favoriteDeadlineCache = it }
        }

    fun isFavorite(item: PublicDeadlineItem): Boolean =
        favoriteDeadlines.any { it.favoriteID == item.favoriteID }

    @Synchronized
    fun setFavorite(item: PublicDeadlineItem, favorite: Boolean) {
        val updated = favoriteDeadlines
            .filterNot { it.favoriteID == item.favoriteID }
            .toMutableList()
        if (favorite) updated.add(0, item)
        val payload = PublicDeadlineItemJsonCodec.encode(updated.take(maximumFavoriteDeadlines))
        if (!preferences.edit().putString(FAVORITE_DEADLINES_KEY, payload).commit()) {
            throw IllegalStateException("无法保存收藏日程。")
        }
        favoriteDeadlineCache = updated.take(maximumFavoriteDeadlines)
    }

    fun favoriteDeadlineItems(date: String): List<PublicDeadlineItem> = favoriteDeadlines
        .filter { it.deadline.startsWith(date) }
        .sortedWith(compareBy(PublicDeadlineItem::deadline, PublicDeadlineItem::name))

    val hasEnabledBuiltInPublicDeadlines: Boolean
        get() = competitionDeadlinesEnabled || conferenceDeadlinesEnabled ||
            schoolContestNoticesEnabled ||
            summerCampDeadlinesEnabled || hackathonDeadlinesEnabled

    val hasEnabledPublicDeadlines: Boolean
        get() = hasEnabledBuiltInPublicDeadlines || enabledCustomDeadlineURL != null

    val hasCalendarDeadlinesToDisplay: Boolean
        get() = hasEnabledPublicDeadlines || favoriteDeadlines.isNotEmpty()

    fun clear() {
        if (!preferences.edit().clear().commit()) {
            throw IllegalStateException("无法清除本地偏好。")
        }
        favoriteDeadlineCache = emptyList()
    }

    private fun save(key: String, value: String) {
        if (!preferences.edit().putString(key, value).commit()) {
            throw IllegalStateException("无法保存本地偏好。")
        }
    }

    private fun save(key: String, value: Boolean) {
        if (!preferences.edit().putBoolean(key, value).commit()) {
            throw IllegalStateException("无法保存本地偏好。")
        }
    }

    private fun save(key: String, value: Int) {
        if (!preferences.edit().putInt(key, value).commit()) {
            throw IllegalStateException("无法保存本地偏好。")
        }
    }

    companion object {
        const val PREFERENCES_NAME = "app_preferences_v1"
        const val CAMPUS_KEY = "campus_id"
        const val LANGUAGE_KEY = "language_code"
        const val TERM_ID_KEY = "term_id"
        const val TERM_START_DATE_KEY = "term_start_date"
        const val DAILY_COURSE_NOTIFICATIONS_KEY = "daily_course_notifications_enabled"
        const val AUTOMATIC_TERM_DETECTION_KEY = "automatic_term_detection_enabled"
        const val WIDGET_SHOWS_LOCATION_KEY = "widget_shows_location"
        const val WIDGET_SHOWS_TEACHER_KEY = "widget_shows_teacher"
        const val WIDGET_COURSE_LIMIT_KEY = "widget_course_limit"
        const val WEATHER_ENABLED_KEY = "weather_enabled"
        const val ALMANAC_ENABLED_KEY = "almanac_enabled"
        const val COMPETITION_DEADLINES_ENABLED_KEY = "competition_deadlines_enabled"
        const val CONFERENCE_DEADLINES_ENABLED_KEY = "conference_deadlines_enabled"
        const val SCHOOL_CONTEST_NOTICES_ENABLED_KEY = "school_contest_notices_enabled"
        const val SUMMER_CAMP_DEADLINES_ENABLED_KEY = "summer_camp_deadlines_enabled"
        const val HACKATHON_DEADLINES_ENABLED_KEY = "hackathon_deadlines_enabled"
        const val CUSTOM_DEADLINES_ENABLED_KEY = "custom_deadlines_enabled"
        const val CUSTOM_DEADLINES_URL_KEY = "custom_deadlines_url"
        const val FAVORITE_DEADLINES_KEY = "favorite_deadlines_v1"
        const val maximumFavoriteDeadlines = 500
    }
}
