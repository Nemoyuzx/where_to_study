import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class DailyInfoClientTests: XCTestCase {
    func testWeatherParserKeepsTodayAndTomorrow() throws {
        let data = Data(#"""
        {
          "district":"海淀区",
          "weather":"多云",
          "temperature":27.4,
          "report_time":"8 分钟前发布",
          "forecast":[
            {"date":"2026-08-22","week":"星期六","temp_max":32.6,"temp_min":22.6,"weather_day":"雷阵雨","weather_night":"雷阵雨","pop":59.6},
            {"date":"2026-08-23","week":"星期日","temp_max":33,"temp_min":23,"weather_day":"多云","weather_night":"多云","pop":20},
            {"date":"2026-08-24","week":"星期一","temp_max":30,"temp_min":22,"weather_day":"晴","weather_night":"晴","pop":0}
          ]
        }
        """#.utf8)

        let parsed = try UAPIDailyInfoClient.parseWeather(
            data: data,
            campusID: "01",
            campusName: "西土城"
        )

        XCTAssertEqual(parsed.district, "海淀区")
        XCTAssertEqual(parsed.currentTemperature, 27)
        XCTAssertEqual(parsed.days.count, 2)
        XCTAssertEqual(parsed.days.last?.date, "2026-08-23")
        XCTAssertEqual(parsed.days.first?.temperatureMaximum, 33)
        XCTAssertEqual(parsed.days.first?.temperatureMinimum, 23)
        XCTAssertEqual(parsed.days.first?.precipitationProbability, 60)
    }

    func testAlmanacParserValidatesRequestedDate() throws {
        let data = Data(#"""
        {
          "datetime":"2026-08-22 12:00:00",
          "weekday_cn":"星期六",
          "lunar_month_cn":"七月",
          "lunar_day_cn":"初十",
          "ganzhi_year":"丙午",
          "ganzhi_month":"丙申",
          "ganzhi_day":"戊辰",
          "zodiac":"马"
        }
        """#.utf8)

        let parsed = try UAPIDailyInfoClient.parseAlmanac(
            data: data,
            requestedDate: "2026-08-22"
        )
        XCTAssertEqual(parsed.lunarDate, "七月初十")
        XCTAssertThrowsError(
            try UAPIDailyInfoClient.parseAlmanac(data: data, requestedDate: "2026-08-23")
        )
    }
}
