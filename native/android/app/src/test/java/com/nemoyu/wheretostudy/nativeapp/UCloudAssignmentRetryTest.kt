package com.nemoyu.wheretostudy.nativeapp

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class UCloudAssignmentRetryTest {
    private val noSleep: (Long) -> Unit = { }

    @Test
    fun transientHttp423IsRetriedUntilSuccess() {
        var attempts = 0
        val result = UCloudAssignmentClient.withFetchRetry(noSleep) {
            attempts += 1
            if (attempts < 3) {
                throw DailyInfoClientException("教学云接口返回 HTTP 423。", httpStatus = 423)
            }
            "ok"
        }
        assertEquals("ok", result)
        assertEquals(3, attempts)
    }

    @Test
    fun transientHttp401AndNetworkErrorsAreRetried() {
        for (failure in listOf(
            DailyInfoClientException("教学云接口返回 HTTP 401。", httpStatus = 401),
            DailyInfoClientException("教学云接口返回 HTTP 500。", httpStatus = 500),
            DailyInfoClientException("教学云接口返回 HTTP 429。", httpStatus = 429),
            IOException("connection reset"),
        )) {
            var attempts = 0
            val result = UCloudAssignmentClient.withFetchRetry(noSleep) {
                attempts += 1
                if (attempts == 1) throw failure
                "ok"
            }
            assertEquals("ok", result)
            assertEquals(2, attempts)
        }
    }

    @Test
    fun nonTransientFailuresAreNotRetried() {
        var attempts = 0
        assertThrows(DailyInfoClientException::class.java) {
            UCloudAssignmentClient.withFetchRetry(noSleep) {
                attempts += 1
                throw DailyInfoClientException("统一认证未返回有效票据；请检查账号密码。")
            }
        }
        assertEquals(1, attempts)
    }

    @Test
    fun exhausted423RetriesProduceGuidanceMessage() {
        var attempts = 0
        val error = assertThrows(DailyInfoClientException::class.java) {
            UCloudAssignmentClient.withFetchRetry(noSleep) {
                attempts += 1
                throw DailyInfoClientException("教学云接口返回 HTTP 423。", httpStatus = 423)
            }
        }
        assertEquals(3, attempts)
        assertTrue(error.message.orEmpty().contains("423"))
        assertTrue(error.message.orEmpty().contains("防火墙"))
        assertEquals(423, error.httpStatus)
    }

    @Test
    fun exhausted401RetriesProduceCredentialGuidance() {
        val error = assertThrows(DailyInfoClientException::class.java) {
            UCloudAssignmentClient.withFetchRetry(noSleep) {
                throw DailyInfoClientException("教学云接口返回 HTTP 401。", httpStatus = 401)
            }
        }
        assertTrue(error.message.orEmpty().contains("401"))
        assertTrue(error.message.orEmpty().contains("密码"))
    }
}
