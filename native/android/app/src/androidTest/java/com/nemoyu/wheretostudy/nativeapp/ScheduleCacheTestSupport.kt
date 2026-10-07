package com.nemoyu.wheretostudy.nativeapp

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

internal fun ScheduleRepository.awaitCacheRestoreForTest() {
    val restored = CountDownLatch(1)
    InstrumentationRegistry.getInstrumentation().runOnMainSync { whenCacheRestored { restored.countDown() } }
    assertTrue("Cached schedule restoration must complete", restored.await(5, TimeUnit.SECONDS))
}
