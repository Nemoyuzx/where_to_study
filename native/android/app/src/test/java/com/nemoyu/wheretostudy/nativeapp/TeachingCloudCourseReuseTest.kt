package com.nemoyu.wheretostudy.nativeapp

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class TeachingCloudCourseReuseTest {
    @Test fun realTeacherArrayAndPerCourseRequestIDArePreservedWithoutNameJoiningOrMoreLogins() {
        var auth = 0; var directory = 0
        val client = UCloudAssignmentClient({ Credentials("synthetic", "synthetic") }, elapsedRealtime = { 0 }, sleep = {},
            authenticateOverride = { auth++; UCloudAssignmentClient.AuthenticatedSession("synthetic", "student", 100_000) },
            apiRequestOverride = { path, _ -> when {
                path.endsWith("/current") -> { directory++; JSONObject("""{"data":{"records":[{"id":"one","siteName":"设置","teachers":[{"name":"Raw teacher 设置"},{"name":"Second teacher"},{"name":"Raw teacher 设置"}]}]}}""") }
                path.endsWith("/list") -> JSONObject("""{"data":{"records":[{"id":"work","assignmentTitle":"Raw work","assignmentEndTime":"2026-10-03 23:59:00","assignmentStatus":99}]}}""")
                else -> JSONObject("""{"data":{"undoneList":[{"activityId":"work","activityName":"Raw work","type":3,"endTime":"2026-10-03 23:59:00","siteName":"设置"}]}}""")
            } })
        assertEquals(listOf("Raw teacher 设置", "Second teacher"), client.fetchCurrentCourses().single().teacherNames)
        assertEquals("one", client.fetchAll().single().courseID)
        assertEquals(1, auth); assertEquals(1, directory)
    }

    @Test fun clearingWhileCurrentCourseRequestIsBlockedCannotRefillTheCourseCache() {
        val entered = CountDownLatch(1); val release = CountDownLatch(1)
        val client = UCloudAssignmentClient({ Credentials("synthetic", "synthetic") }, elapsedRealtime = { 0 }, sleep = {},
            authenticateOverride = { UCloudAssignmentClient.AuthenticatedSession("synthetic", "student", 100_000) },
            apiRequestOverride = { _, _ ->
                entered.countDown(); check(release.await(5, TimeUnit.SECONDS))
                JSONObject("""{"data":{"records":[{"id":"one","siteName":"Old course"}]}}""")
            })
        val worker = Executors.newSingleThreadExecutor()
        try {
            val result = worker.submit<Boolean> { runCatching { client.fetchCurrentCourses() }.isSuccess }
            assertTrue(entered.await(5, TimeUnit.SECONDS)); client.reset(); release.countDown()
            assertFalse(result.get(5, TimeUnit.SECONDS))
            assertNull(client.cachedCourses()); assertNull(client.cached())
        } finally { release.countDown(); worker.shutdownNow() }
    }

    @Test fun openingCurrentCoursesDoesNotFetchEveryAssignmentAndTheLaterAssignmentRefreshReusesItsSession() {
        var auth = 0; var courses = 0; var work = 0
        val client = UCloudAssignmentClient({ Credentials("synthetic", "synthetic") }, elapsedRealtime = { 0 }, sleep = {},
            authenticateOverride = { auth++; UCloudAssignmentClient.AuthenticatedSession("synthetic", "student", 100_000) },
            apiRequestOverride = { path, _ -> when {
                path.endsWith("/current") -> { courses++; JSONObject("""{"data":{"records":[{"id":"one","siteName":"Raw name"}]}}""") }
                path.endsWith("/list") -> { work++; JSONObject("""{"data":{"records":[]}}""") }
                else -> JSONObject("""{"data":{"undoneList":[]}}""")
            } })
        assertEquals("Raw name", client.fetchCurrentCourses().single().name)
        assertEquals(1, auth); assertEquals(1, courses); assertEquals(0, work)
        client.fetchCurrentCourses(); client.fetchAll()
        assertEquals(1, auth); assertEquals(1, courses); assertEquals(1, work)
    }

    @Test fun currentCoursesComeFromTheExistingAssignmentFlightWithoutAnotherLoginOrRequest() {
        var auth = 0; var courseRequests = 0; var workRequests = 0
        val credentials = Credentials("synthetic", "synthetic", "synthetic-cloud")
        val client = UCloudAssignmentClient({ credentials }, elapsedRealtime = { 0 }, sleep = {},
            authenticateOverride = { auth++; UCloudAssignmentClient.AuthenticatedSession("synthetic", "student", 100_000) },
            apiRequestOverride = { path, _ -> when {
                path.endsWith("/current") -> { courseRequests++; JSONObject("""{"data":{"records":[{"id":"one","siteName":"设置","teacherName":"Raw teacher"}]}}""") }
                path.endsWith("/list") -> { workRequests++; JSONObject("""{"data":{"records":[]}}""") }
                else -> JSONObject("""{"data":{"undoneList":[]}}""")
            } })
        assertNull(client.cachedCourses())
        client.fetchAll()
        repeat(5) { assertEquals(TeachingCloudCourse("one", "设置", "Raw teacher"), client.cachedCourses()!!.single()) }
        client.fetchAll()
        assertEquals(1, auth); assertEquals(1, courseRequests); assertEquals(1, workRequests)
        client.fetchAll(force = true)
        assertEquals(1, auth); assertEquals(2, courseRequests); assertEquals(2, workRequests)
        client.reset()
        assertNull(client.cached()); assertNull(client.cachedCourses())
        assertEquals(2, courseRequests)
    }
}
