package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** A private preferences fixture only: no network, credentials or radio state. */
@RunWith(AndroidJUnit4::class)
class CellularPreferenceUiTest {
    @Test fun cellularOptInDefaultsOffPersistsAndFullPreferenceClearReturnsOff() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val fixture = context.getSharedPreferences("cellular_preference_regression_only", Context.MODE_PRIVATE)
        assertTrue(fixture.edit().clear().commit())
        val scopedContext = object : ContextWrapper(context) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                if (name == AppPreferences.PREFERENCES_NAME) fixture else super.getSharedPreferences(name, mode)
        }
        try {
            val preferences = AppPreferences(scopedContext)
            assertFalse(preferences.cellularAssistEnabled)
            preferences.cellularAssistEnabled = true
            assertTrue(AppPreferences(scopedContext).cellularAssistEnabled)
            preferences.cellularAssistEnabled = false
            assertFalse(AppPreferences(scopedContext).cellularAssistEnabled)
            preferences.cellularAssistEnabled = true
            preferences.clear()
            assertFalse(AppPreferences(scopedContext).cellularAssistEnabled)
            assertFalse(fixture.contains(CellularAssistPolicy.preferenceKey))
            assertTrue(fixture.all.isEmpty())
        } finally { assertTrue(fixture.edit().clear().commit()) }
    }
}
