package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import javax.net.ssl.SSLHandshakeException

class CellularAssistPolicyTest {
    @Test fun defaultOffAndWifiOnly() {
        assertFalse(CellularAssistPolicy.canRetry("GET", false, true, ConnectException()))
        assertFalse(CellularAssistPolicy.canRetry("GET", true, false, ConnectException()))
        assertTrue(CellularAssistPolicy.canRetry("GET", true, true, ConnectException()))
    }
    @Test fun neverReplaysCredentialsOrMutations() {
        for (method in listOf("POST", "PUT", "DELETE", "PATCH")) {
            assertFalse(CellularAssistPolicy.canRetry(method, true, true, SocketTimeoutException()))
        }
    }
    @Test fun noRetryForHttpJsonTlsOrCancellation() {
        for (error in listOf(Exception("HTTP 401"), Exception("bad JSON"), SSLHandshakeException("untrusted"),
            InterruptedIOException("cancelled"), Exception(SSLHandshakeException("untrusted")))) {
            assertFalse(CellularAssistPolicy.canRetry("GET", true, true, error))
        }
        assertTrue(CellularAssistPolicy.canRetry("GET", true, true, Exception(SocketTimeoutException())))
    }
}
