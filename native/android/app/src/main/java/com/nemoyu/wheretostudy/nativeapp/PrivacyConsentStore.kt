package com.nemoyu.wheretostudy.nativeapp

import android.content.Context

/**
 * Stores only the version of the privacy notice accepted on this device.
 * The value never leaves the app's private SharedPreferences storage.
 */
class PrivacyConsentStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    val hasAcceptedCurrentPolicy: Boolean
        get() = preferences.getInt(ACCEPTED_VERSION_KEY, 0) >= CURRENT_POLICY_VERSION

    fun acceptCurrentPolicy() {
        if (!preferences.edit()
                .putInt(ACCEPTED_VERSION_KEY, CURRENT_POLICY_VERSION)
                .commit()
        ) {
            throw IllegalStateException("无法保存隐私政策同意状态。")
        }
    }

    internal fun clear() {
        if (!preferences.edit().clear().commit()) {
            throw IllegalStateException("无法清除隐私政策同意状态。")
        }
    }

    companion object {
        const val PRIVACY_POLICY_URL =
            "https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md"
        internal const val PREFERENCES_NAME = "privacy_consent_v1"
        internal const val ACCEPTED_VERSION_KEY = "accepted_policy_version"
        internal const val CURRENT_POLICY_VERSION = 1
    }
}
