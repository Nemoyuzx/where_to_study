package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class DailyInfoClientTest {
    @Test
    fun weatherTargetsMapCampusesToTheirDistrictAdcodes() {
        assertEquals("110108", CampusWeatherTargets.resolve("01").adcode)
        assertEquals("110114", CampusWeatherTargets.resolve("4").adcode)
        assertThrows(DailyInfoClientException::class.java) {
            CampusWeatherTargets.resolve("99")
        }
    }

    @Test
    fun weatherParserKeepsTodayAndTomorrowAndRoundsValues() {
        val payload = """
            {
              "district":"海淀区",
              "weather":"多云",
              "temperature":27.4,
              "report_time":"8 分钟前发布",
              "forecast":[
                {"date":"2026-08-22","week":"星期六","temp_max":32.6,"temp_min":22.6,"weather_day":"雷阵雨","weather_night":"雷阵雨","pop":59.6},
                {"date":"2026-08-23","week":"星期日","temp_max":33,"temp_min":23,"weather_day":"多云","weather_night":"多云"},
                {"date":"2026-08-24","week":"星期一","temp_max":30,"temp_min":22,"weather_day":"晴","weather_night":"晴","pop":0}
              ]
            }
        """.trimIndent()

        val parsed = WeatherResponseParser.parse(payload, "01", "西土城")

        assertEquals("海淀区", parsed.district)
        assertEquals(27, parsed.currentTemperature)
        assertEquals(2, parsed.days.size)
        assertEquals(33, parsed.days[0].temperatureMaximum)
        assertEquals(23, parsed.days[0].temperatureMinimum)
        assertEquals(60, parsed.days[0].precipitationProbability)
        assertNull(parsed.days[1].precipitationProbability)
    }

    @Test
    fun weatherParserRejectsInvalidDatesAndUnsafeMeasurements() {
        val invalidDate = validPayload().replace("2026-08-22", "2026-02-30")
        assertThrows(DailyInfoClientException::class.java) {
            WeatherResponseParser.parse(invalidDate, "01", "西土城")
        }

        val invalidProbability = validPayload().replace("\"pop\":40", "\"pop\":101")
        assertThrows(DailyInfoClientException::class.java) {
            WeatherResponseParser.parse(invalidProbability, "01", "西土城")
        }
    }

    private fun validPayload(): String = """
        {
          "district":"海淀区","weather":"晴","temperature":20,"report_time":"刚刚",
          "forecast":[
            {"date":"2026-08-22","week":"星期六","temp_max":30,"temp_min":20,"weather_day":"晴","weather_night":"晴","pop":40},
            {"date":"2026-08-23","week":"星期日","temp_max":31,"temp_min":21,"weather_day":"晴","weather_night":"多云","pop":20}
          ]
        }
    """.trimIndent()
}
