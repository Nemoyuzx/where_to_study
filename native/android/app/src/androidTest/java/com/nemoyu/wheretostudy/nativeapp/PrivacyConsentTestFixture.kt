package com.nemoyu.wheretostudy.nativeapp

import androidx.test.platform.app.InstrumentationRegistry

internal fun ensurePrivacyConsentForUiTest() {
    PrivacyConsentStore(
        InstrumentationRegistry.getInstrumentation().targetContext,
    ).acceptCurrentPolicy()
}
