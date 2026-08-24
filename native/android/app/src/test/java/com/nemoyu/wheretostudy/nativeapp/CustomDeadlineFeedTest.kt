package com.nemoyu.wheretostudy.nativeapp

import java.net.URI
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CustomDeadlineFeedTest {
    @Test
    fun v1FixturePreservesCompleteCustomDeadlineFields() {
        val payload = checkNotNull(javaClass.classLoader?.getResourceAsStream(
            "custom-deadline-feed.json",
        )).bufferedReader().use { it.readText() }
        val feed = CustomDeadlineFeedParser.parse(payload, "https://example.com/feed.json")

        assertEquals("示例自定义日程", feed.sourceName)
        assertEquals("https://example.com/calendar", feed.homepage)
        assertEquals(2, feed.metadata.itemCount)
        val item = feed.itemsByDate.getValue("2026-09-18").single()
        assertEquals(PublicDeadlineKind.CUSTOM, item.kind)
        assertEquals(PublicDeadlineSource.CUSTOM, item.source)
        assertEquals("示例自定义日程", item.sourceName)
        assertEquals("https://example.com/calendar", item.sourceHomepage)
        assertEquals("https://example.com/calendar/example-registration", item.officialURL)
    }

    @Test
    fun customURLValidationRejectsCredentialsLocalhostAndReservedLiterals() {
        assertEquals(
            URI.create("https://calendar.example.com:8443/feed.json"),
            CustomDeadlineFeedURLValidator.validatedURI(
                " https://calendar.example.com:8443/feed.json ",
            ),
        )
        listOf(
            "http://example.com/feed.json",
            "https://user:password@example.com/feed.json",
            "https://localhost/feed.json",
            "https://calendar.localhost/feed.json",
            "https://127.0.0.1/feed.json",
            "https://127.1/feed.json",
            "https://2130706433/feed.json",
            "https://0x7f000001/feed.json",
            "https://10.0.0.1/feed.json",
            "https://169.254.1.2/feed.json",
            "https://172.16.0.1/feed.json",
            "https://192.168.1.1/feed.json",
            "https://192.0.2.1/feed.json",
            "https://198.51.100.1/feed.json",
            "https://203.0.113.1/feed.json",
            "https://[::1]/feed.json",
            "https://[fc00::1]/feed.json",
            "https://[2001:db8::1]/feed.json",
            "https://example.com/feed.json#fragment",
        ).forEach { value ->
            assertThrows(value, DailyInfoClientException::class.java) {
                CustomDeadlineFeedURLValidator.validatedURI(value)
            }
        }
    }

    @Test
    fun invalidEnvelopeFailsWhileInvalidItemsAreSkipped() {
        assertThrows(DailyInfoClientException::class.java) {
            CustomDeadlineFeedParser.parse(
                """{"version":1,"source":"test","items":[],"extra":true}""",
                "https://example.com/feed.json",
            )
        }
        val feed = CustomDeadlineFeedParser.parse(
            """{
              "version":1,
              "source":"Test Feed",
              "updated_at":"2026-08-24T08:00:00+08:00",
              "items":[
                {"id":"valid","name":"Valid","event_type":"competition","primary_deadline":"2026-09-01T18:00:00+08:00"},
                {"id":"","name":"Blank","event_type":"custom","primary_deadline":"2026-09-01T18:00:00+08:00"},
                {"id":"bad-type","name":"Bad","event_type":"other","primary_deadline":"2026-09-01T18:00:00+08:00"},
                {"id":"bad-date","name":"Bad","event_type":"custom","primary_deadline":"2026-02-30T18:00:00+08:00"},
                {"id":"bad-link","name":"Bad","event_type":"custom","primary_deadline":"2026-09-01T18:00:00+08:00","official_url":"http://example.com"}
              ]
            }""",
            "https://example.com/feed.json",
        )
        assertEquals(listOf("valid"), feed.itemsByDate.getValue("2026-09-01").map { it.id })
    }

    @Test
    fun customFeedUsesFiveMinuteSuccessCacheAndCredentialFreeSizeContract() {
        var elapsedMillis = 1_000L
        val fetches = AtomicInteger(0)
        val requestedLimits = mutableListOf<Int>()
        val client = CalendarDailyInfoClient(
            fetchPublicJson = { _, _, _, _ -> error("Built-in source must stay disabled") },
            elapsedRealtimeMillis = { elapsedMillis },
            fetchCustomJson = { uri, limit ->
                assertEquals(URI.create("https://example.com/feed.json"), uri)
                requestedLimits += limit
                fetches.incrementAndGet()
                """{
                  "version":1,
                  "source":"Test",
                  "items":[
                    {"id":"one","name":"One","event_type":"custom","primary_deadline":"2026-09-01T18:00:00+08:00"},
                    {"id":"two","name":"Two","event_type":"hackathon","primary_deadline":"2026-09-02T19:00:00+08:00"}
                  ]
                }"""
            },
        )

        val first = client.fetchDeadlines(
            "2026-09-01",
            includeBuiltIn = false,
            customSourceURL = "https://example.com/feed.json",
        )
        assertEquals("one", first.items.single().id)
        assertEquals("two", client.fetchDeadlines(
            "2026-09-02",
            includeBuiltIn = false,
            customSourceURL = "https://example.com/feed.json",
        ).items.single().id)
        assertEquals(1, fetches.get())
        assertEquals(
            listOf(CalendarDailyInfoSources.deadlinePayloadLimit),
            requestedLimits,
        )
        assertEquals("Test", client.validateCustomFeed(
            "https://example.com/feed.json",
        ).sourceName)
        assertEquals(1, fetches.get())

        elapsedMillis += 5 * 60 * 1_000L + 1
        client.fetchDeadlines(
            "2026-09-01",
            includeBuiltIn = false,
            customSourceURL = "https://example.com/feed.json",
        )
        assertEquals(
            "Date navigation must keep filtering the stale full-feed cache without networking",
            1,
            fetches.get(),
        )
        client.prewarmDeadlines(
            "2026-09-01",
            includeBuiltIn = false,
            customSourceURL = "https://example.com/feed.json",
        )
        assertEquals(2, fetches.get())
        val oversizedRange = (2020..2022).flatMap { year ->
            (1..12).flatMap { month ->
                (1..28).map { day -> String.format("%04d-%02d-%02d", year, month, day) }
            }
        }.take(371)
        assertThrows(DailyInfoClientException::class.java) {
            client.fetchCustomDeadlines(
                dates = oversizedRange,
                sourceURL = "https://example.com/feed.json",
            )
        }
    }

    @Test
    fun favoriteJsonRoundTripKeepsSourceAndRejectsUnsafeSnapshots() {
        val original = PublicDeadlineItem(
            id = "favorite",
            name = "Favorite",
            kind = PublicDeadlineKind.CUSTOM,
            source = PublicDeadlineSource.CUSTOM,
            deadline = "2026-09-18T23:59:00+08:00",
            organizer = "Organizer",
            officialURL = "https://example.com/item",
            sourceName = "My Feed",
            sourceHomepage = "https://example.com",
        )
        assertEquals(listOf(original), PublicDeadlineItemJsonCodec.decode(
            PublicDeadlineItemJsonCodec.encode(listOf(original)),
        ))

        val unsafeRecord = JSONArray(PublicDeadlineItemJsonCodec.encode(listOf(original)))
            .getJSONObject(0)
            .put("official_url", "http://example.com")
        val unsafe = JSONArray().put(unsafeRecord)
        assertTrue(PublicDeadlineItemJsonCodec.decode(unsafe.toString()).isEmpty())
        assertFalse(original.favoriteID.isBlank())
    }

    @Test
    fun favoriteJsonLoadingIsCappedAtFiveHundredCompleteSnapshots() {
        val items = (0..AppPreferences.maximumFavoriteDeadlines).map { index ->
            PublicDeadlineItem(
                id = "favorite-$index",
                name = "Favorite $index",
                kind = PublicDeadlineKind.COMPETITION,
                source = PublicDeadlineSource.CONTEST_DDL,
                deadline = "2026-09-18T23:59:00+08:00",
                organizer = null,
                officialURL = null,
            )
        }
        assertEquals(
            AppPreferences.maximumFavoriteDeadlines,
            PublicDeadlineItemJsonCodec.decode(PublicDeadlineItemJsonCodec.encode(items)).size,
        )
    }
}
