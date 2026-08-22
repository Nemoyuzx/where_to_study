package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.json.JSONObject

class CalendarDailyInfoClientTest {
    @Test
    fun almanacParsersKeepYiJiAndValidateDate() {
        val base = AlmanacResponseParser.parseBase(
            """{
              "datetime":"2026-08-22 12:00:00",
              "weekday_cn":"星期六",
              "lunar_month_cn":"七月",
              "lunar_day_cn":"初十",
              "ganzhi_year":"丙午",
              "ganzhi_month":"丙申",
              "ganzhi_day":"戊辰",
              "zodiac":"马"
            }""",
            "2026-08-22",
        )
        val advice = AlmanacResponseParser.parseAdvice(
            """{
              "errno":0,
              "data":{"year":2026,"month":8,"day":22,"almanac":{"yi":"学习、交流","ji":"拖延、熬夜"}}
            }""",
            "2026-08-22",
        )
        assertEquals("七月初十", base.lunarDate)
        assertEquals("学习、交流", advice.first)
        assertEquals("拖延、熬夜", advice.second)
        assertThrows(DailyInfoClientException::class.java) {
            AlmanacResponseParser.parseAdvice(
                """{"errno":0,"data":{"year":2026,"month":8,"day":22,"almanac":{"yi":"宜","ji":"忌"}}}""",
                "2026-08-23",
            )
        }
    }

    @Test
    fun publicDeadlineParserFiltersDateKindsAndUnsafeLinks() {
        val parsed = PublicDeadlineResponseParser.parse(
            """{
              "items":[
                {"id":"c1","name":"数据库竞赛","event_type":"competition","primary_deadline":"2026-08-22T18:00:00+08:00","official_url":"https://example.com/c1"},
                {"id":"h1","name":"校园黑客松","event_type":"hackathon","primary_deadline":"2026-08-22T23:59:59+08:00","official_url":"http://example.com"},
                {"id":"s1","name":"夏令营","event_type":"summer_camp","primary_deadline":"2026-08-23T23:59:59+08:00"},
                {"id":"x1","name":"未知","event_type":"other","primary_deadline":"2026-08-22T12:00:00+08:00"}
              ]
            }""",
            "2026-08-22",
        )
        assertEquals(listOf("c1", "h1"), parsed.map(PublicDeadlineItem::id))
        assertEquals("https", java.net.URI.create(parsed.first().officialURL).scheme)
        assertEquals(PublicDeadlineSource.CONTEST_DDL, parsed.first().source)
        assertNull(parsed.last().officialURL)
    }

    @Test
    fun schoolNoticeParserExpandsDeadlinesOnSelectedDay() {
        val parsed = PublicDeadlineResponseParser.parseSchoolNotices(
            """{
              "items":[{
                "id":"bupt-ucloud-1",
                "name":"校内创新竞赛",
                "deadlines":[
                  {"date":"2026-08-22T10:00:00+08:00","label":"材料提交"},
                  {"date":"2026-08-23T23:59:59+08:00","label":"报名截止"}
                ],
                "source":"北京邮电大学教学云平台",
                "source_url":"https://ucloud.bupt.edu.cn/#/consulting?type=1&id=1"
              }]
            }""",
            "2026-08-22",
        )
        assertEquals(PublicDeadlineSource.SCHOOL_NOTICE, parsed.single().source)
        assertEquals(1, parsed.size)
        assertEquals(PublicDeadlineKind.COMPETITION, parsed.first().kind)
        assertEquals("北京邮电大学教学云平台 · 材料提交", parsed.first().organizer)
        assertEquals("ucloud.bupt.edu.cn", java.net.URI.create(parsed.first().officialURL).host)
    }

    @Test
    fun assignmentParserSupportsCourseAndHomepageContracts() {
        val courseItems = AssignmentDeadlineResponseParser.parse(
            """{
              "data":{"records":[
                {"id":7,"assignmentTitle":"第四次作业","siteName":"神经网络与深度学习","assignmentEndTime":"2026-06-30 23:59:00","assignmentStatus":99},
                {"id":8,"assignmentTitle":"第三次作业","assignmentEndTime":"2026-06-21 23:59:00","assignmentStatus":0}
              ]}
            }""",
            "2026-06-30",
        )
        assertEquals(1, courseItems.size)
        assertEquals("未提交", courseItems.first().status)

        val undone = AssignmentDeadlineResponseParser.parse(
            """{
              "data":{"undoneList":[
                {"activityId":"a1","activityName":"课程作业","type":3,"endTime":"2026-08-22 18:00:00"},
                {"activityId":"q1","activityName":"课程测验","type":4,"endTime":"2026-08-22 20:00:00"}
              ]}
            }""",
            "2026-08-22",
        )
        assertEquals(listOf("a1"), undone.map(AssignmentDeadlineItem::id))
    }

    @Test
    fun assignmentParserInjectsCourseName() {
        val items = AssignmentDeadlineResponseParser.parseAll(
            JSONObject(
                """{"data":{"records":[{"id":"a1","assignmentTitle":"作业一","assignmentEndTime":"2026-08-22 23:59:00","assignmentStatus":99}]}}""",
            ),
            "示例课程",
        )
        assertEquals("示例课程", items.first().courseName)
    }

    @Test
    fun ucloudCASParserPinsTicketHostAndSupportsExecutionAttributeOrder() {
        assertEquals(
            "e1&s1",
            UCloudAssignmentClient.parseExecution(
                "<input value='e1&amp;s1' type='hidden' name='execution'>",
            ),
        )
        assertEquals(
            "token-2",
            UCloudAssignmentClient.parseExecution("<input name=execution value=token-2>"),
        )
        assertEquals(
            "ST-test",
            UCloudAssignmentClient.ticketFrom(
                "https://ucloud.bupt.edu.cn/?ticket=ST-test",
            ),
        )
        assertNull(UCloudAssignmentClient.ticketFrom(
            "http://ucloud.bupt.edu.cn/?ticket=ST-test",
        ))
        assertNull(UCloudAssignmentClient.ticketFrom(
            "https://evil.example/?ticket=ST-test",
        ))
    }
}
