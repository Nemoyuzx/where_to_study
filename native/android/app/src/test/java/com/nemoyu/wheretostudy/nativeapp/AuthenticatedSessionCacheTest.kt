package com.nemoyu.wheretostudy.nativeapp

import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AuthenticatedSessionCacheTest {
    private class Expired : Exception()
    private val credentials = Credentials("student", "academic", "cloud")

    @Test fun sjdHttp500UnauthorizedFixtureRefreshesOnlyOnceForStringAndNumericCode() {
        for (code in listOf("\"401\"", "401", "401.0")) {
            var logins = 0
            var requests = 0
            val fixture = "{\"code\":$code,\"message\":\"非法访问：/currentTerm\"}"
            val api = SjdApiClient(AuthenticatedSessionCache(), { "token-${++logins}" }) { _, _, token ->
                requests++
                SjdApiClient.responsePayload(if (token == "token-1") 500 else 200,
                    if (token == "token-1") fixture else "{\"code\":1}", authenticated = true)
            }
            api.authenticated(credentials) { api.post("/bjyddx/currentTerm", "referer", token = it) }
            assertEquals(2, logins); assertEquals(2, requests)
            var rejectedLogins = 0
            val rejected = SjdApiClient(AuthenticatedSessionCache(), { "token-${++rejectedLogins}" }) { _, _, _ ->
                SjdApiClient.responsePayload(500, fixture, authenticated = true)
            }
            val error = assertThrows(ScheduleClientException::class.java) {
                rejected.authenticated(credentials) { rejected.post("/bjyddx/currentTerm", "referer", token = it) }
            }
            assertEquals(2, rejectedLogins)
            assertTrue(error.sessionExpired)
            assertFalse("Auth rejection must not be replayed by a transport retry policy", error.retryable)
        }
    }

    @Test fun sjdNonAuthServerFailuresAndLoginResponsesDoNotTriggerSessionRefresh() {
        for ((status, body, authenticated) in listOf(
            Triple(500, "{\"code\":500,\"message\":\"token expired\"}", true),
            Triple(500, "invalid response", true),
            Triple(503, "{\"code\":401}", true),
            Triple(403, "{\"code\":401}", true),
            Triple(423, "{\"code\":401}", true),
            Triple(500, "{\"code\":401}", false),
        )) {
            val error = assertThrows(ScheduleClientException::class.java) {
                SjdApiClient.responsePayload(status, body, authenticated)
            }
            assertFalse("status=$status authenticated=$authenticated", error.sessionExpired)
        }
    }

    @Test fun onlyExplicitSessionExpiryMessagesTriggerRefresh() {
        listOf("token expired", "Invalid access token", "登录已过期", "会话失效，请重新登录").forEach {
            assertTrue(it, SessionExpiryMessage.matches(it))
        }
        listOf("forbidden", "invalid response", "token parser failed", "服务器错误", "密码错误", "权限不足").forEach {
            assertFalse(it, SessionExpiryMessage.matches(it))
        }
        var logins = 0
        val api = SjdApiClient(AuthenticatedSessionCache(), { "token-${++logins}" }) { _, _, token ->
            if (token == "token-1") JSONObject("{\"code\":-1,\"Msg\":\"登录已过期\"}") else JSONObject("{\"code\":1}")
        }
        api.authenticated(credentials) { api.post("/query", "referer", token = it) }
        assertEquals(2, logins)
    }

    @Test fun repeatedAcademicQueriesShareLoginAndRefreshOnceOnExplicitExpiry() {
        var logins = 0
        var expired = false
        val api = SjdApiClient(AuthenticatedSessionCache(), { "token-${++logins}" }) { _, _, token ->
            if (expired && token == "token-1") JSONObject("{\"code\":401}") else JSONObject("{\"code\":1}")
        }
        fun fetch() = api.authenticated(credentials) { api.post("/query", "referer", token = it) }
        fetch(); fetch()
        assertEquals(1, logins)
        expired = true
        fetch(); fetch()
        assertEquals(2, logins)
    }

    @Test fun serverParserAndBusinessFailuresNeverRefreshAcademicLogin() {
        for (failure in listOf(IOException("offline"), ScheduleClientException("server", retryable = true),
            ScheduleClientException("parser"), ScheduleClientException("business"))) {
            var logins = 0
            val api = SjdApiClient(AuthenticatedSessionCache(), { "token-${++logins}" }) { _, _, _ -> throw failure }
            repeat(2) { assertThrows(Exception::class.java) {
                api.authenticated(credentials) { api.post("/query", "referer", token = it) }
            } }
            assertEquals(1, logins)
        }
    }

    @Test fun concurrentFirstLoginAndRefreshAreSingleFlight() {
        val cache = AuthenticatedSessionCache<String>()
        val logins = AtomicInteger()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val workers = Executors.newFixedThreadPool(8)
        try {
            val results = (1..8).map { workers.submit<String> {
                cache.perform("owner", {
                    val n = logins.incrementAndGet(); entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS)); "token-$n"
                }, { it is Expired }) { token -> if (token == "token-1") throw Expired() else token }
            } }
            assertTrue(entered.await(5, TimeUnit.SECONDS)); release.countDown()
            results.forEach { assertEquals("token-2", it.get(5, TimeUnit.SECONDS)) }
            assertEquals(2, logins.get())
        } finally { workers.shutdownNow() }
    }

    @Test fun repeatedExpiryRefreshesOnlyOnceAndCredentialChangesInvalidate() {
        val cache = AuthenticatedSessionCache<String>()
        var logins = 0
        assertThrows(Expired::class.java) {
            cache.perform("first", { "token-${++logins}" }, { it is Expired }) { throw Expired() }
        }
        assertEquals(2, logins)
        fun fetch(key: String) = cache.perform(key, { "token-${++logins}" }, { false }) { it }
        assertEquals("token-3", fetch("first"))
        assertEquals("token-4", fetch("changed-password"))
        cache.clear()
        assertEquals("token-5", fetch("changed-password"))
    }

    @Test fun clearDuringLoginRejectsLateResult() {
        val cache = AuthenticatedSessionCache<String>()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val worker = Executors.newSingleThreadExecutor()
        try {
            val result = worker.submit<Boolean> {
                try {
                    cache.perform("same", { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)); "old" }, { false }) { it }
                    false
                } catch (_: LocalDataInvalidatedException) { true }
            }
            assertTrue(entered.await(5, TimeUnit.SECONDS)); cache.clear(); release.countDown()
            assertTrue(result.get(5, TimeUnit.SECONDS))
            assertEquals("new", cache.perform("same", { "new" }, { false }) { it })
        } finally { worker.shutdownNow() }
    }

    @Test fun teachingCloudSessionSurvivesRefreshAndFirewallRetries() {
        var logins = 0
        var requests = 0
        var now = 0L
        val client = UCloudAssignmentClient({ credentials }, elapsedRealtime = { now }, sleep = {},
            authenticateOverride = { credential ->
                assertEquals("cloud", credential.password)
                UCloudAssignmentClient.AuthenticatedSession("token-${++logins}", "student", now + 100_000)
            }, apiRequestOverride = { path, _ ->
                when {
                    path.endsWith("/current") -> JSONObject("{\"data\":{\"records\":[{\"id\":\"course\"}]}}")
                    path.endsWith("/list") -> {
                        requests++
                        if (requests == 1) throw DailyInfoClientException("firewall", httpStatus = 423)
                        JSONObject("{\"data\":{\"records\":[]}}")
                    }
                    else -> JSONObject("{\"data\":{\"undoneList\":[]}}")
                }
            })
        client.fetchAll(); client.fetchAll(force = true)
        assertEquals(1, logins); assertEquals(3, requests)
        now = 100_001
        client.fetchAll(force = true)
        assertEquals(2, logins)
    }

    @Test fun unknownLifetimeExpiresAfterTwentyMinutesAndExplicitZeroIsExpired() {
        var now = 0L
        var logins = 0
        val cache = AuthenticatedSessionCache<String>(clockMillis = { now })
        fun fetch() = cache.perform("owner", { "token-${++logins}" }, { false }) { it }
        fetch(); now = AuthenticatedSessionCache.FALLBACK_LIFETIME_MS - 1; fetch()
        assertEquals(1, logins)
        now++; fetch(); assertEquals(2, logins)
        assertEquals(0L, SessionExpiryMessage.expirationMillis(0))
        assertNull(SessionExpiryMessage.expirationMillis(JSONObject.NULL))
        val expired = AuthenticatedSessionCache<String>(expiresAtMillis = { 0 }, clockMillis = { 1 })
        repeat(2) { expired.perform("owner", { "token-${++logins}" }, { false }) { it } }
        assertEquals(4, logins)
    }

    @Test fun authenticationChainIsNeverRetriedForFirewallNetworkOrUnauthorizedFailures() {
        for (failure in listOf(IOException("offline"), DailyInfoClientException("firewall", httpStatus = 423),
            DailyInfoClientException("unauthorized", httpStatus = 401))) {
            var logins = 0
            val client = UCloudAssignmentClient({ credentials }, elapsedRealtime = { 0 }, sleep = {},
                authenticateOverride = { logins++; throw failure })
            assertThrows(Exception::class.java) { client.fetchAll() }
            assertEquals(1, logins)
        }
    }

    @Test fun dataRetryDoesNotReplayTheCourseCatalogue() {
        var logins = 0
        var catalogueCalls = 0
        var workCalls = 0
        val client = UCloudAssignmentClient({ credentials }, elapsedRealtime = { 0 }, sleep = {},
            authenticateOverride = { UCloudAssignmentClient.AuthenticatedSession("token-${++logins}", "student") },
            apiRequestOverride = { path, _ ->
                when {
                    path.endsWith("/current") -> { catalogueCalls++; JSONObject("{\"data\":{\"records\":[{\"id\":\"course\"}]}}") }
                    path.endsWith("/list") -> { workCalls++; throw DailyInfoClientException("server", httpStatus = 500) }
                    else -> JSONObject("{\"data\":{\"undoneList\":[]}}")
                }
            })
        assertThrows(DailyInfoClientException::class.java) { client.fetchAll() }
        assertEquals(1, logins); assertEquals(1, catalogueCalls); assertEquals(3, workCalls)
    }

    @Test fun teachingCloud401RefreshIsBoundedAndOtherFailuresRetainSession() {
        var logins = 0
        var requests = 0
        val client = UCloudAssignmentClient({ credentials }, elapsedRealtime = { 0 }, sleep = {},
            authenticateOverride = { UCloudAssignmentClient.AuthenticatedSession("token-${++logins}", "student") },
            fetchAuthenticatedOverride = { requests++; throw DailyInfoClientException("expired", httpStatus = 401) })
        assertThrows(DailyInfoClientException::class.java) { client.fetchAll() }
        assertEquals(2, logins); assertEquals(2, requests)
        for (failure in listOf(IOException("offline"), DailyInfoClientException("server", httpStatus = 500),
            DailyInfoClientException("parser"))) {
            logins = 0
            val failing = UCloudAssignmentClient({ credentials }, elapsedRealtime = { 0 }, sleep = {},
                authenticateOverride = { UCloudAssignmentClient.AuthenticatedSession("token-${++logins}", "student") },
                fetchAuthenticatedOverride = { throw failure })
            repeat(2) { assertThrows(Exception::class.java) { failing.fetchAll() } }
            assertEquals(1, logins)
        }
    }
}
