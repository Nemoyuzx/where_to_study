package com.nemoyu.wheretostudy.nativeapp

import java.time.OffsetDateTime
import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class InformationQueryLogicTest {
    @Test
    fun shuttleClientPinsCanonicalHttpsEndpointAndPayloadLimit() {
        var calls = 0
        val snapshot = ShuttleBusClient { uri, scheme, host, maximumBytes ->
            calls += 1
            assertEquals(CalendarDailyInfoSources.shuttleBus, uri.toString())
            assertEquals("https", scheme)
            assertEquals("where-to-study.cn", host)
            assertEquals(CalendarDailyInfoSources.shuttlePayloadLimit, maximumBytes)
            shuttlePayload()
        }.fetch()

        assertEquals(1, calls)
        assertEquals("healthy", snapshot.status)
    }

    @Test
    fun shuttleClientPreservesRedirectRejectionAsSourceSpecificError() {
        val error = assertThrows(DailyInfoClientException::class.java) {
            ShuttleBusClient { _, _, _, _ ->
                throw DailyInfoClientException("公开数据源返回了不受信任的重定向。")
            }.fetch()
        }
        assertTrue(error.message.orEmpty().contains("班车信息获取失败"))
        assertTrue(error.message.orEmpty().contains("重定向"))
    }

    @Test
    fun shuttleParserAndTodayLogicUseOnlyCurrentPeriodAndWeekday() {
        val snapshot = ShuttleBusResponseParser.parse(shuttlePayload())
        val now = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
            set(2026, Calendar.AUGUST, 31, 8, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val presentation = ShuttleBusLogic.today(snapshot, now)

        assertEquals(2, presentation.routes.size)
        assertEquals(listOf("08:30"), presentation.routes[0].departures.map { it.time })
        assertEquals("下一班 08:30 · 西土城路校区 → 沙河校区", presentation.nextDeparture)
        assertEquals("今日安排 2 个发车时刻 · 3 辆车", presentation.status)
        assertFalse(presentation.isStale)
    }

    @Test
    fun shuttleLogicDoesNotResurrectOldTimetableDuringExplicitGap() {
        val snapshot = ShuttleBusResponseParser.parse(shuttlePayload())
        val gap = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
            set(2026, Calendar.SEPTEMBER, 5, 8, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val presentation = ShuttleBusLogic.today(snapshot, gap)

        assertEquals("未找到当前生效的班车时刻表", presentation.status)
        assertTrue(presentation.routes.isEmpty())
        assertNull(presentation.noticeTitle)
    }

    @Test
    fun shuttleUnknownPeriodIsNotActiveAndExactDepartureMinuteIsAlreadyDeparted() {
        val parsed = ShuttleBusResponseParser.parse(shuttlePayload())
        val unknownOnly = parsed.copy(notices = listOf(parsed.notices.last()))
        val now = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai")).apply {
            set(2026, Calendar.AUGUST, 31, 8, 30, 0)
            set(Calendar.MILLISECOND, 0)
        }

        assertEquals(
            "未找到当前生效的班车时刻表",
            ShuttleBusLogic.today(unknownOnly, now).status,
        )
        assertEquals(
            "下一班 09:00 · 沙河校区 → 西土城路校区",
            ShuttleBusLogic.today(parsed, now).nextDeparture,
        )
    }

    @Test
    fun importantEventQuerySearchesFieldsFiltersKindsAndRetainsMissingFavorite() {
        val futureConference = item(
            "conference", PublicDeadlineKind.CONFERENCE,
            PublicDeadlineSource.CONTEST_DDL, "2026-09-02T12:00:00+08:00",
            categories = listOf("人工智能"),
            tags = listOf("CCF A"),
            metadataSource = PublicDeadlineMetadataSource(
                "CCFDDL", "https://ccfddl.com/", "trusted_community", 4,
            ),
        )
        val futureCompetition = item(
            "competition", PublicDeadlineKind.COMPETITION,
            PublicDeadlineSource.CONTEST_DDL, "2026-09-01T12:00:00+08:00",
        )
        val expiredNotice = item(
            "notice", PublicDeadlineKind.COMPETITION,
            PublicDeadlineSource.SCHOOL_NOTICE, "2026-08-01T12:00:00+08:00",
        )
        val expiredToday = item(
            "expired-today", PublicDeadlineKind.COMPETITION,
            PublicDeadlineSource.CONTEST_DDL, "2026-08-31T08:00:00+08:00",
        )
        val archivedFuture = item(
            "archived", PublicDeadlineKind.CONFERENCE,
            PublicDeadlineSource.CONTEST_DDL, "2026-09-10T12:00:00+08:00",
            archived = true,
        )
        val missingFavorite = item(
            "favorite", PublicDeadlineKind.HACKATHON,
            PublicDeadlineSource.CONTEST_DDL, "2026-09-03T12:00:00+08:00",
        )
        val custom = item(
            "custom", PublicDeadlineKind.CUSTOM,
            PublicDeadlineSource.CUSTOM, "2026-09-04T12:00:00+08:00",
        )

        val nowMillis = OffsetDateTime.parse("2026-08-31T12:00:00+08:00")
            .toInstant().toEpochMilli()
        val default = ImportantEventQueryLogic.filter(
            liveItems = listOf(
                futureConference, expiredNotice, expiredToday,
                archivedFuture, futureCompetition, custom,
            ),
            favorites = listOf(missingFavorite),
            query = "",
            category = ImportantEventCategory.ALL,
            showsEnded = false,
            nowMillis = nowMillis,
        )
        assertEquals(
            listOf("competition", "conference", "favorite"),
            default.map(PublicDeadlineItem::id),
        )
        assertEquals(
            listOf("conference"),
            ImportantEventQueryLogic.filter(
                liveItems = listOf(futureConference, futureCompetition),
                favorites = emptyList(),
                query = "trusted community",
                category = ImportantEventCategory.CONFERENCE,
                metadataCategory = "人工智能",
                showsEnded = false,
                nowMillis = nowMillis,
            ).map(PublicDeadlineItem::id),
        )
        assertEquals(
            listOf("notice"),
            ImportantEventQueryLogic.filter(
                liveItems = listOf(expiredNotice, expiredToday, archivedFuture),
                favorites = emptyList(),
                query = "",
                category = ImportantEventCategory.SCHOOL_NOTICE,
                showsEnded = true,
                nowMillis = nowMillis,
            ).map(PublicDeadlineItem::id),
        )
        assertEquals(
            listOf("人工智能"),
            ImportantEventQueryLogic.metadataCategories(
                listOf(futureConference),
                emptyList(),
                ImportantEventCategory.CONFERENCE,
                showsEnded = false,
                nowMillis = nowMillis,
            ),
        )
    }

    @Test
    fun availableEventTypesComeFromRemoteAndFavoriteCatalogButExcludeCustomSources() {
        val competition = item(
            "competition", PublicDeadlineKind.COMPETITION,
            PublicDeadlineSource.CONTEST_DDL, "2026-09-01T12:00:00+08:00",
        )
        val conference = item(
            "conference", PublicDeadlineKind.CONFERENCE,
            PublicDeadlineSource.CONTEST_DDL, "2026-09-02T12:00:00+08:00",
        )
        val schoolNotice = item(
            "school", PublicDeadlineKind.COMPETITION,
            PublicDeadlineSource.SCHOOL_NOTICE, "2026-09-03T12:00:00+08:00",
        )
        val favoriteJournal = item(
            "journal", PublicDeadlineKind.JOURNAL_SPECIAL_ISSUE,
            PublicDeadlineSource.CONTEST_DDL, "2026-09-04T12:00:00+08:00",
        )
        val customPreAdmission = item(
            "custom", PublicDeadlineKind.PRE_ADMISSION,
            PublicDeadlineSource.CUSTOM, "2026-09-05T12:00:00+08:00",
        )

        assertEquals(
            listOf(
                ImportantEventCategory.ALL,
                ImportantEventCategory.COMPETITION,
                ImportantEventCategory.CONFERENCE,
                ImportantEventCategory.JOURNAL_SPECIAL_ISSUE,
                ImportantEventCategory.SCHOOL_NOTICE,
            ),
            ImportantEventQueryLogic.availableTypeFilters(
                listOf(competition, conference, schoolNotice, customPreAdmission),
                listOf(favoriteJournal),
            ),
        )
    }

    @Test
    fun metadataCategoriesFollowSelectedTypeAndEndedState() {
        val nowMillis = OffsetDateTime.parse("2026-08-31T12:00:00+08:00")
            .toInstant().toEpochMilli()
        val futureConference = item(
            "future-conference", PublicDeadlineKind.CONFERENCE,
            PublicDeadlineSource.CONTEST_DDL, "2026-09-02T12:00:00+08:00",
            categories = listOf("人工智能"),
        )
        val expiredConference = item(
            "expired-conference", PublicDeadlineKind.CONFERENCE,
            PublicDeadlineSource.CONTEST_DDL, "2026-08-01T12:00:00+08:00",
            categories = listOf("系统"),
        )
        val futureCompetition = item(
            "future-competition", PublicDeadlineKind.COMPETITION,
            PublicDeadlineSource.CONTEST_DDL, "2026-09-03T12:00:00+08:00",
            categories = listOf("数学建模"),
        )
        val custom = item(
            "custom", PublicDeadlineKind.CUSTOM,
            PublicDeadlineSource.CUSTOM, "2026-09-04T12:00:00+08:00",
            categories = listOf("自定义"),
        )
        val catalog = listOf(futureConference, expiredConference, futureCompetition, custom)

        assertEquals(
            listOf("人工智能"),
            ImportantEventQueryLogic.metadataCategories(
                catalog,
                emptyList(),
                ImportantEventCategory.CONFERENCE,
                showsEnded = false,
                nowMillis = nowMillis,
            ),
        )
        assertEquals(
            listOf("人工智能", "系统"),
            ImportantEventQueryLogic.metadataCategories(
                catalog,
                emptyList(),
                ImportantEventCategory.CONFERENCE,
                showsEnded = true,
                nowMillis = nowMillis,
            ),
        )
        assertEquals(
            listOf("数学建模"),
            ImportantEventQueryLogic.metadataCategories(
                catalog,
                emptyList(),
                ImportantEventCategory.COMPETITION,
                showsEnded = false,
                nowMillis = nowMillis,
            ),
        )
    }

    @Test
    fun unavailableTypeAndMetadataSelectionsFallBackSafely() {
        val nowMillis = OffsetDateTime.parse("2026-08-31T12:00:00+08:00")
            .toInstant().toEpochMilli()
        val conference = item(
            "conference", PublicDeadlineKind.CONFERENCE,
            PublicDeadlineSource.CONTEST_DDL, "2026-09-02T12:00:00+08:00",
            categories = listOf("人工智能"),
        )

        assertEquals(
            ImportantEventFilterSelection(ImportantEventCategory.ALL, null),
            ImportantEventQueryLogic.normalizedSelection(
                listOf(conference),
                emptyList(),
                ImportantEventCategory.PRE_ADMISSION,
                "预推免",
                showsEnded = false,
                nowMillis = nowMillis,
            ),
        )
        assertEquals(
            ImportantEventFilterSelection(ImportantEventCategory.CONFERENCE, null),
            ImportantEventQueryLogic.normalizedSelection(
                listOf(conference),
                emptyList(),
                ImportantEventCategory.CONFERENCE,
                "系统",
                showsEnded = false,
                nowMillis = nowMillis,
            ),
        )
        assertEquals(
            ImportantEventFilterSelection(ImportantEventCategory.CONFERENCE, "人工智能"),
            ImportantEventQueryLogic.normalizedSelection(
                listOf(conference),
                emptyList(),
                ImportantEventCategory.CONFERENCE,
                "人工智能",
                showsEnded = false,
                nowMillis = nowMillis,
            ),
        )
    }

    @Test
    fun publicDeadlineParserAcceptsEverySupportedPublicTypeIncludingConference() {
        val types = listOf(
            "competition", "conference", "journal_special_issue",
            "hackathon", "summer_camp", "pre_admission",
        )
        val records = types.mapIndexed { index, type ->
            """{"id":"$index","name":"$type","event_type":"$type","primary_deadline":"2026-09-0${index + 1}T12:00:00+08:00"}"""
        }.joinToString(",")
        val parsed = PublicDeadlineResponseParser.parseIndex("""{"items":[$records]}""")
            .values.flatten()

        assertEquals(types.toSet(), parsed.map { it.kind.wireValue }.toSet())
    }

    private fun item(
        id: String,
        kind: PublicDeadlineKind,
        source: PublicDeadlineSource,
        deadline: String,
        categories: List<String> = emptyList(),
        tags: List<String> = emptyList(),
        metadataSource: PublicDeadlineMetadataSource? = null,
        archived: Boolean = false,
    ) = PublicDeadlineItem(
        id = id,
        name = id,
        kind = kind,
        source = source,
        deadline = deadline,
        organizer = "主办方",
        officialURL = null,
        categories = categories,
        tags = tags,
        metadataSource = metadataSource,
        archived = archived,
    )

    private fun shuttlePayload(): String = """{
      "schema_version":"1.0",
      "generated_at":"2026-08-31T00:00:00.000Z",
      "status":"healthy",
      "source":{"name":"北京邮电大学后勤部","page_url":"https://hq.bupt.edu.cn/tzgg.htm"},
      "items":[
        {
          "id":"new","title":"最新班车通知","published_at":"2026-08-19",
          "source_url":"https://hq.bupt.edu.cn/info/1010/1541.htm",
          "kind":"regular_schedule","parse_status":"parsed",
          "stops":[{"campus":"西土城路校区","location":"教三楼西侧"}],
          "notes":["请提前五分钟候车。"],
          "schedules":[
            {
              "period":{"label":"第一时段","start_date":"2026-08-27","end_date":"2026-09-04"},
              "from":"西土城路校区","to":"沙河校区","parse_status":"parsed",
              "rows":[
                {"departure_time":"08:30","services":{"monday":{"vehicle":"大巴","count":1}}},
                {"departure_time":"09:30","services":{"monday":null}}
              ]
            },
            {
              "period":{"label":"第一时段","start_date":"2026-08-27","end_date":"2026-09-04"},
              "from":"沙河校区","to":"西土城路校区","parse_status":"parsed",
              "rows":[{"departure_time":"09:00","services":{"monday":{"vehicle":"大巴","count":2}}}]
            },
            {
              "period":{"label":"第二时段","start_date":"2026-09-07","end_date":null},
              "from":"西土城路校区","to":"沙河校区","parse_status":"parsed",
              "rows":[{"departure_time":"06:50","services":{"monday":{"vehicle":"大巴","count":2}}}]
            }
          ]
        },
        {
          "id":"old","title":"旧班车通知","published_at":"2026-04-02",
          "kind":"temporary_adjustment","parse_status":"parsed",
          "stops":[],"notes":[],
          "schedules":[{
            "period":{"label":"通知所示时段","start_date":null,"end_date":null},
            "from":"西土城路校区","to":"沙河校区","parse_status":"parsed",
            "rows":[{"departure_time":"07:00","services":{"monday":{"vehicle":"大巴","count":1}}}]
          }]
        }
      ]
    }"""
}
