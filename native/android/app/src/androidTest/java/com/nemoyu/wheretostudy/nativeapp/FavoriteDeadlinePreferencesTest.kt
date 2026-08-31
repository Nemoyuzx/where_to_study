package com.nemoyu.wheretostudy.nativeapp

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FavoriteDeadlinePreferencesTest {
    @Test
    fun conferenceCalendarVisibilitySettingPersistsIndependently() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = AppPreferences(context)
        val previous = preferences.conferenceDeadlinesEnabled
        try {
            preferences.conferenceDeadlinesEnabled = false
            assertFalse(AppPreferences(context).conferenceDeadlinesEnabled)
            preferences.conferenceDeadlinesEnabled = true
            assertTrue(AppPreferences(context).conferenceDeadlinesEnabled)
        } finally {
            AppPreferences(context).conferenceDeadlinesEnabled = previous
        }
    }

    @Test
    fun customSettingsAndCompleteFavoriteSnapshotPersistAndRemoveLocally() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = AppPreferences(context)
        val previousCustomEnabled = preferences.customDeadlinesEnabled
        val previousCustomURL = preferences.customDeadlinesURL
        val previousFavorites = preferences.favoriteDeadlines
        clearFavorites(preferences)
        val item = PublicDeadlineItem(
            id = "android-favorite-test",
            name = "完整收藏快照",
            kind = PublicDeadlineKind.CUSTOM,
            source = PublicDeadlineSource.CUSTOM,
            deadline = "2026-09-18T23:59:00+08:00",
            organizer = "测试组织方",
            officialURL = "https://example.com/item#deadline",
            sourceName = "测试来源",
            sourceHomepage = "https://example.com",
            categories = listOf("人工智能"),
            tags = listOf("CCF A"),
            level = "国家级",
            location = "北京",
            description = "完整说明",
            eligibility = "本科生",
            notes = "以官网为准",
            metadataSource = PublicDeadlineMetadataSource(
                "上游来源", "https://example.com/source#metadata", "official", 5,
            ),
            status = "upcoming",
            region = "china",
            mode = "hybrid",
            archived = true,
        )
        try {
            preferences.customDeadlinesURL = "https://example.com/feed.json"
            preferences.customDeadlinesEnabled = true
            preferences.setFavorite(item, favorite = true)

            val reloaded = AppPreferences(context)
            assertTrue(reloaded.customDeadlinesEnabled)
            assertEquals("https://example.com/feed.json", reloaded.customDeadlinesURL)
            assertEquals(listOf(item), reloaded.favoriteDeadlines)
            reloaded.customDeadlinesEnabled = false
            assertEquals(
                listOf(item),
                reloaded.favoriteDeadlineItems("2026-09-18"),
            )

            reloaded.setFavorite(item, favorite = false)
            assertFalse(AppPreferences(context).isFavorite(item))
        } finally {
            val restored = AppPreferences(context)
            restored.customDeadlinesURL = previousCustomURL
            restored.customDeadlinesEnabled = previousCustomEnabled
            clearFavorites(restored)
            previousFavorites.reversed().forEach { restored.setFavorite(it, favorite = true) }
        }
    }

    @Test
    fun settingsPrewarmMaterializesTheNaturalYearFromOneFullFeedRequest() {
        val primaryCalls = AtomicInteger(0)
        val schoolCalls = AtomicInteger(0)
        val client = CalendarDailyInfoClient(
            fetchPublicJson = { uri, _, _, _ ->
                when (uri.toString()) {
                    CalendarDailyInfoSources.deadlinePrimary -> primaryCalls.incrementAndGet()
                    CalendarDailyInfoSources.schoolContestNotices -> schoolCalls.incrementAndGet()
                    else -> error("Unexpected URL: $uri")
                }
                """{"items":[]}"""
            },
        )
        val repository = CalendarDailyInfoRepository(
            client = client,
            usesSampleData = false,
        )
        val completed = CountDownLatch(1)
        try {
            repository.prewarmDeadlines("2026-08-24") { completed.countDown() }
            assertTrue(completed.await(5, TimeUnit.SECONDS))
            assertNotNull(repository.deadlines("2026-01-01"))
            assertNotNull(repository.deadlines("2026-12-31"))
            assertEquals(1, primaryCalls.get())
            assertEquals(1, schoolCalls.get())
        } finally {
            repository.close()
        }
    }

    private fun clearFavorites(preferences: AppPreferences) {
        preferences.favoriteDeadlines.forEach { preferences.setFavorite(it, favorite = false) }
    }
}
