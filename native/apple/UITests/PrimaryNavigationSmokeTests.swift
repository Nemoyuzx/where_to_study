import XCTest
import UIKit

@MainActor
final class PrimaryNavigationSmokeTests: XCTestCase {
    func testPrimaryPagesAreNavigable() {
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }

        assertScreen("screen.planner", in: app)
        navigate(to: "教学日历", in: app)
        assertScreen("screen.calendar", in: app)
        assertMobileCalendarControls(in: app)
        navigate(to: "查询", in: app)
        assertScreen("screen.information-queries", in: app)
        navigate(to: "设置", in: app)
        assertScreen("screen.settings", in: app)
        navigate(to: "空教室", in: app)
        assertScreen("screen.planner", in: app)
    }

    func testInformationQueriesAreAPrimaryNavigationDestination() {
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "查询", in: app)
        assertScreen("screen.information-queries", in: app)
        XCTAssertTrue(app.segmentedControls.buttons["班车查询"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["queries.shuttle.status"]
            .waitForExistence(timeout: 5))
        let events = app.segmentedControls.buttons["重要事件"]
        XCTAssertTrue(events.waitForExistence(timeout: 5))
        events.tap()
        let showEnded = app.switches["queries.events.show-ended"]
        XCTAssertTrue(showEnded.waitForExistence(timeout: 5))
        XCTAssertEqual(showEnded.value as? String, "0")
        XCTAssertTrue(app.staticTexts["示例学术会议"].waitForExistence(timeout: 5))
        for category in ["all", "schoolNotice", "competition", "conference", "summerCamp", "hackathon"] {
            XCTAssertTrue(app.descendants(matching: .any)["queries.events.type.\(category)"]
                .waitForExistence(timeout: 5))
        }
        XCTAssertFalse(app.descendants(matching: .any)["queries.events.type.journalSpecialIssue"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["queries.events.type.preAdmission"].exists)

        navigate(to: "教学日历", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["calendar.open-information-queries"].exists)
        navigate(to: "设置", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["settings.open-information-queries"].exists)
    }

    func testLiveShuttleDataRendersOnIPhone() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone-only live query check")
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["WTS_RUN_LIVE_SHUTTLE_TESTS"] == "1",
            "Set WTS_RUN_LIVE_SHUTTLE_TESTS=1 to exercise the production shuttle API."
        )
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--ui-testing-live"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "查询", in: app)
        assertScreen("screen.information-queries", in: app)
        let status = app.descendants(matching: .any)["queries.shuttle.status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 30))
        XCTAssertTrue(
            ["今日班车按时刻表运行", "今日没有计划班次"].contains(status.label),
            "Unexpected shuttle state: \(status.label)"
        )
        XCTAssertFalse(app.staticTexts["班车信息暂不可用"].exists)
        XCTAssertTrue(app.staticTexts["西土城路校区 → 沙河校区"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["沙河校区 → 西土城路校区"].waitForExistence(timeout: 5))
    }

    func testPhoneYearViewKeepsLastDateAboveFloatingTabBar() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone-only layout check")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        app.launch()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        navigate(to: "教学日历", in: app)
        let yearMode = app.segmentedControls.buttons["年"]
        XCTAssertTrue(yearMode.waitForExistence(timeout: 5))
        yearMode.tap()

        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let yearText = String(shanghaiCalendar.component(.year, from: Date()))
        XCTAssertTrue(
            app.buttons["calendar.mobile.year-month.\(yearText)-01"].waitForExistence(timeout: 5)
        )
        let yearScroll = app.scrollViews.firstMatch
        XCTAssertTrue(yearScroll.waitForExistence(timeout: 5))
        let lastDate = app.buttons["calendar.mobile.year-day.\(yearText)-12-31"].firstMatch
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)

        for _ in 0 ..< 12 {
            if lastDate.exists,
               lastDate.isHittable,
               lastDate.frame.maxY <= tabBar.frame.minY {
                break
            }
            verticalSwipe(in: app, within: yearScroll, upward: true, requestedTravel: 180)
        }

        XCTAssertTrue(lastDate.exists)
        XCTAssertTrue(lastDate.isHittable, "The last year date must scroll clear of the floating tab bar")
        XCTAssertLessThanOrEqual(lastDate.frame.maxY, tabBar.frame.minY)

        lastDate.tap()
        XCTAssertTrue(app.buttons["calendar.mobile.year-jump.日"].waitForExistence(timeout: 5))
    }

    func testPhoneLandscapeYearViewKeepsLastDateAboveFloatingTabBar() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone-only layout check")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        app.launch()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        navigate(to: "教学日历", in: app)
        let yearMode = app.segmentedControls.buttons["年"]
        XCTAssertTrue(yearMode.waitForExistence(timeout: 5))
        yearMode.tap()

        var shanghaiCalendar = Calendar(identifier: .gregorian)
        shanghaiCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let yearText = String(shanghaiCalendar.component(.year, from: Date()))
        XCTAssertTrue(
            app.buttons["calendar.mobile.year-month.\(yearText)-01"].waitForExistence(timeout: 5)
        )
        let lastDate = app.buttons["calendar.mobile.year-day.\(yearText)-12-31"].firstMatch
        let yearScroll = app.scrollViews.firstMatch
        let landscapeTabBar = app.tabBars.firstMatch
        XCTAssertTrue(yearScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(landscapeTabBar.exists)
        for _ in 0 ..< 12 {
            if lastDate.exists,
               lastDate.isHittable,
               lastDate.frame.maxY <= landscapeTabBar.frame.minY {
                break
            }
            verticalSwipe(in: app, within: yearScroll, upward: true, requestedTravel: 180)
        }

        let landscapeAttachment = XCTAttachment(screenshot: app.screenshot())
        landscapeAttachment.name = "calendar-year-last-date-landscape"
        landscapeAttachment.lifetime = .keepAlways
        add(landscapeAttachment)
        XCTAssertTrue(lastDate.isHittable, "The last year date must remain reachable in landscape")
        XCTAssertLessThanOrEqual(
            lastDate.frame.maxY,
            landscapeTabBar.frame.minY,
            "Landscape year content must also clear the floating tab bar"
        )

        lastDate.tap()
        XCTAssertTrue(app.buttons["calendar.mobile.year-jump.日"].waitForExistence(timeout: 5))
    }

    func testReviewDemoShowsLocalDataWithoutAccount() {
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        XCTAssertTrue(app.descendants(matching: .any)["banner.sample-mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["数据挖掘"].waitForExistence(timeout: 5))
        attachScreenshot(named: "store-iphone-planner")
        navigate(to: "教学日历", in: app)
        assertScreen("screen.calendar", in: app)
        attachScreenshot(named: "store-iphone-calendar-week")
        let actions = app.buttons["课表操作"]
        if actions.exists {
            actions.tap()
            app.buttons["导入系统日历"].tap()
        } else {
            app.buttons["导入系统日历"].tap()
        }
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH '示例模式已模拟同步 '")
        ).firstMatch.waitForExistence(timeout: 5))
        navigate(to: "设置", in: app)
        XCTAssertTrue(app.staticTexts["内置示例模式已开启，不会连接教务服务或读写真实用户数据。"]
            .waitForExistence(timeout: 5))
        attachScreenshot(named: "store-iphone-settings")
        let reminder = app.switches["每天 07:30 发送当日课程摘要"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        reminder.tap()
        XCTAssertTrue(app.staticTexts["示例模式已模拟开启每日课程摘要，未申请通知权限"]
            .waitForExistence(timeout: 5))
    }

    func testWeatherCardStartsCollapsedAndExpandsOnDemand() {
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        app.launch()
        defer { app.terminate() }

        let toggle = app.descendants(matching: .any)["weather.toggle"].firstMatch
        revealByScrolling(visibleElement: toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "已折叠")
        XCTAssertFalse(app.descendants(matching: .any)["weather.details"].firstMatch.exists)

        toggle.tap()

        XCTAssertTrue(waitForValue("已展开", of: toggle))
        let details = app.descendants(matching: .any)["weather.details"].firstMatch
        revealByScrolling(visibleElement: details, in: app)
        attachScreenshot(named: "planner-weather-expanded")
    }

    func testMobileCalendarPagingMonthExpansionAndYearJump() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "仅在 iPhone 模拟器验证")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        navigate(to: "教学日历", in: app)
        let periodLabel = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年[0-9]+月$")
        ).firstMatch
        XCTAssertTrue(periodLabel.waitForExistence(timeout: 5))
        let weekContext = app.staticTexts.matching(
            NSPredicate(
                format: "label MATCHES %@",
                "^公历第 [0-9]+ 周 · 第 [0-9]+ 教学周$"
            )
        ).firstMatch
        XCTAssertTrue(weekContext.waitForExistence(timeout: 5))
        XCTAssertTrue(weekContext.label.contains("公历第 "))
        XCTAssertTrue(weekContext.label.contains("教学周"))
        attachScreenshot(named: "calendar-week-single-viewport")
        let courseSummaryToggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '门课'")
        ).firstMatch
        XCTAssertTrue(courseSummaryToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(courseSummaryToggle.value as? String, "已展开")
        courseSummaryToggle.tap()
        XCTAssertTrue(waitForValue("已折叠", of: courseSummaryToggle))
        courseSummaryToggle.tap()
        XCTAssertTrue(waitForValue("已展开", of: courseSummaryToggle))
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS '全天' AND label CONTAINS '+'")
        ).firstMatch.waitForExistence(timeout: 5))
        let initialWeek = weekContext.label
        horizontalSwipe(in: app, atY: 0.29, toLeft: true)
        XCTAssertTrue(waitForLabelChange(of: weekContext, from: initialWeek))
        horizontalSwipe(in: app, atY: 0.29, toLeft: false)
        XCTAssertEqual(weekContext.label, initialWeek)

        app.segmentedControls.buttons["日"].tap()
        let dayHeader = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年[0-9]+月[0-9]+日$")
        ).firstMatch
        XCTAssertTrue(dayHeader.waitForExistence(timeout: 5))
        let initialDay = dayHeader.label
        horizontalSwipe(in: app, atY: 0.72, toLeft: true)
        XCTAssertTrue(waitForLabelChange(of: dayHeader, from: initialDay))
        let firstHour = app.staticTexts["calendar.mobile.hour.08"].firstMatch
        XCTAssertTrue(firstHour.waitForExistence(timeout: 5))
        let initialHourY = firstHour.frame.minY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.72))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.42))
            )
        XCTAssertLessThan(firstHour.frame.minY, initialHourY)

        app.segmentedControls.buttons["月"].tap()
        let monthHeadings = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年[0-9]+月$")
        )
        let monthHeading = monthHeadings.firstMatch
        let mondayHeading = app.staticTexts["calendar.mobile.month-weekday.一"].firstMatch
        let month = app.descendants(matching: .any)["calendar.mobile.month-state"].firstMatch
        XCTAssertTrue(monthHeading.waitForExistence(timeout: 5))
        XCTAssertEqual(monthHeadings.count, 1)
        XCTAssertTrue(mondayHeading.waitForExistence(timeout: 5))
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        XCTAssertEqual(month.value as? String, "已展开")
        let monthSummaryViewport = app.descendants(matching: .any)[
            "calendar.mobile.month-day-summary"
        ].firstMatch
        XCTAssertTrue(monthSummaryViewport.exists)
        XCTAssertFalse(
            monthSummaryViewport.isHittable,
            "The stable details viewport must remain non-interactive while the month is expanded"
        )
        let monthEventID = "calendar.mobile.month-event.\(currentShanghaiDateString())-assignment-sample-assignment"
        let monthEvent = app.staticTexts[monthEventID].firstMatch
        XCTAssertTrue(monthEvent.waitForExistence(timeout: 5))
        XCTAssertFalse(monthEvent.label.isEmpty)
        XCTAssertFalse(app.buttons[monthEventID].exists)
        monthEvent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(
            waitForValue("已收起", of: month),
            "Display-only event rows must pass the tap through to their month day"
        )
        XCTAssertTrue(app.descendants(matching: .any)["calendar.mobile.month-day-summary"]
            .waitForExistence(timeout: 5))
        month.tap()
        XCTAssertTrue(waitForValue("已展开", of: month))
        attachScreenshot(named: "calendar-month-expanded")
        let initialMonthHeadingY = monthHeading.frame.minY
        let initialMondayHeadingY = mondayHeading.frame.minY

        let alternateDateKey = nearbyShanghaiDateString()
        let alternateDay = app.buttons[
            "calendar.mobile.month-day-number.\(alternateDateKey)"
        ].firstMatch
        XCTAssertTrue(alternateDay.waitForExistence(timeout: 5))
        alternateDay.tap()
        XCTAssertTrue(
            waitForValue("已收起", of: month),
            "A date tap must retarget an expansion animation without requiring a second tap"
        )
        let summaryCard = app.descendants(matching: .any)[
            "calendar.mobile.month-day-summary-card"
        ].firstMatch
        XCTAssertTrue(summaryCard.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(alternateDateKey, of: summaryCard))
        month.tap()
        XCTAssertTrue(waitForValue("已展开", of: month))

        let selectedDay = app.buttons[
            "calendar.mobile.month-day-number.\(currentShanghaiDateString())"
        ].firstMatch
        XCTAssertTrue(selectedDay.waitForExistence(timeout: 5))
        selectedDay.tap()
        XCTAssertTrue(waitForValue("已收起", of: month))
        XCTAssertTrue(app.descendants(matching: .any)["calendar.mobile.month-day-summary"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["calendar.mobile.month-day-summary-card"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["当日日程"].waitForExistence(timeout: 5))
        XCTAssertTrue(month.isHittable)
        month.tap()
        XCTAssertTrue(waitForValue("已展开", of: month))
        verticalSwipe(in: app, between: mondayHeading, and: month, upward: false)
        XCTAssertTrue(waitForValue("已展开", of: month))
        XCTAssertEqual(monthHeading.frame.minY, initialMonthHeadingY, accuracy: 2)
        verticalSwipe(in: app, between: mondayHeading, and: month, upward: true)
        XCTAssertTrue(waitForValue("已收起", of: month))
        XCTAssertEqual(monthHeading.frame.minY, initialMonthHeadingY, accuracy: 2)
        XCTAssertEqual(mondayHeading.frame.minY, initialMondayHeadingY, accuracy: 2)
        XCTAssertFalse(app.buttons["折叠"].exists)
        XCTAssertFalse(app.buttons["展开"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["calendar.mobile.month-day-summary"]
            .waitForExistence(timeout: 5))
        attachScreenshot(named: "calendar-month-collapsed")

        let collapsedMonthLabel = monthHeading.label
        let nextPeriod = app.buttons["下一时间段"].firstMatch
        let previousPeriod = app.buttons["上一时间段"].firstMatch
        XCTAssertTrue(nextPeriod.waitForExistence(timeout: 5))
        nextPeriod.tap()
        XCTAssertTrue(waitForLabelChange(of: monthHeading, from: collapsedMonthLabel))
        XCTAssertEqual(month.value as? String, "已收起")
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "calendar.mobile.month-day-summary")
                .count,
            1,
            "Month paging must keep one stable details viewport"
        )
        XCTAssertTrue(waitForValue(shiftedShanghaiDateString(months: 1), of: summaryCard))
        previousPeriod.tap()
        XCTAssertTrue(waitForLabel(collapsedMonthLabel, of: monthHeading))
        XCTAssertTrue(waitForValue(currentShanghaiDateString(), of: summaryCard))

        horizontalSwipe(in: app, atY: 0.42, toLeft: true)
        XCTAssertTrue(waitForLabelChange(of: monthHeading, from: collapsedMonthLabel))
        horizontalSwipe(in: app, atY: 0.42, toLeft: false)
        XCTAssertTrue(waitForLabel(collapsedMonthLabel, of: monthHeading))

        horizontalSwipe(in: app, atY: 0.42, toLeft: false)
        XCTAssertTrue(waitForLabelChange(of: monthHeading, from: collapsedMonthLabel))
        horizontalSwipe(in: app, atY: 0.42, toLeft: true)
        XCTAssertTrue(waitForLabel(collapsedMonthLabel, of: monthHeading))

        verticalSwipe(in: app, between: mondayHeading, and: month, upward: true)
        XCTAssertTrue(waitForValue("日程已展开", of: month))
        let monthSummary = app.descendants(matching: .any)["calendar.mobile.month-day-summary"].firstMatch
        XCTAssertTrue(monthSummary.waitForExistence(timeout: 5))
        attachScreenshot(named: "calendar-month-detail-raised")
        verticalSwipe(in: app, within: monthSummary, upward: false)
        XCTAssertTrue(waitForValue("已收起", of: month))
        verticalSwipe(in: app, within: monthSummary, upward: false)
        XCTAssertTrue(waitForValue("已展开", of: month))

        let initialMonth = monthHeading.label
        horizontalSwipe(in: app, atY: 0.56, toLeft: true)
        XCTAssertTrue(waitForLabelChange(of: monthHeading, from: initialMonth))
        horizontalSwipe(in: app, atY: 0.56, toLeft: false)
        XCTAssertTrue(waitForLabel(initialMonth, of: monthHeading))

        for mode in ["日", "周", "月"] {
            app.segmentedControls.buttons["年"].tap()
            let yearDay = app.buttons["calendar.mobile.year-day.\(currentShanghaiDateString())"]
            for _ in 0..<8 where !yearDay.exists {
                app.swipeUp()
            }
            XCTAssertTrue(yearDay.waitForExistence(timeout: 3))
            XCTAssertTrue(yearDay.isHittable)
            XCTAssertEqual(yearDay.value as? String, "assignment,schoolNotice")
            yearDay.tap()

            XCTAssertTrue(app.staticTexts["课程作业 DDL"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["校内竞赛通知"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["公开活动 DDL"].waitForExistence(timeout: 5))

            for target in ["日", "周", "月"] {
                XCTAssertTrue(app.buttons["\(target)视图"].waitForExistence(timeout: 5))
            }
            if mode == "日" {
                attachScreenshot(named: "calendar-year-date-actions")
            }
            app.buttons["\(mode)视图"].tap()
            XCTAssertTrue(app.segmentedControls.buttons[mode].waitForExistence(timeout: 5))
            XCTAssertTrue(app.segmentedControls.buttons[mode].isSelected)
        }
    }

    func testMobileCalendarModeTransitionsEnterFromHierarchyDirection() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "仅在 iPhone 模拟器验证")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo", "--ui-test-slow-calendar-animation"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        navigate(to: "教学日历", in: app)
        let monthButton = app.segmentedControls.buttons["月"]
        let yearButton = app.segmentedControls.buttons["年"]
        let dayButton = app.segmentedControls.buttons["日"]
        XCTAssertTrue(monthButton.waitForExistence(timeout: 5))

        monthButton.tap()
        XCTAssertTrue(waitForSelected(monthButton))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年[0-9]+月$")
        ).firstMatch.waitForExistence(timeout: 5))

        yearButton.tap()
        XCTAssertTrue(waitForSelected(yearButton))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年$")
        ).firstMatch.waitForExistence(timeout: 5))

        monthButton.tap()
        XCTAssertTrue(waitForSelected(monthButton))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年[0-9]+月$")
        ).firstMatch.waitForExistence(timeout: 5))

        dayButton.tap()
        XCTAssertTrue(waitForSelected(dayButton))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年[0-9]+月[0-9]+日$")
        ).firstMatch.waitForExistence(timeout: 5))
        yearButton.tap()
        XCTAssertTrue(waitForSelected(yearButton))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年$")
        ).firstMatch.waitForExistence(timeout: 5))

        dayButton.tap()
        XCTAssertTrue(waitForSelected(dayButton))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年[0-9]+月[0-9]+日$")
        ).firstMatch.waitForExistence(timeout: 5))
    }

    func testMobileWeekUsesCenteredDialogAndMonthKeepsDetailsInline() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "仅在 iPhone 模拟器验证")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "教学日历", in: app)
        let weekAllDayButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '全天' AND label CONTAINS '+'")
        ).firstMatch
        XCTAssertTrue(weekAllDayButton.waitForExistence(timeout: 5))
        weekAllDayButton.tap()

        let weekDialog = app.descendants(matching: .any)[
            "calendar.mobile.week-agenda-dialog"
        ].firstMatch
        XCTAssertTrue(weekDialog.waitForExistence(timeout: 5))
        XCTAssertEqual(weekDialog.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertLessThan(abs(weekDialog.frame.midY - app.frame.midY), 48)
        XCTAssertTrue(app.staticTexts["全国大学生示例竞赛"].exists)
        XCTAssertTrue(app.staticTexts["示例高校夏令营"].exists)
        app.buttons["关闭全天日程"].tap()

        app.segmentedControls.buttons["月"].tap()
        let monthState = app.descendants(matching: .any)["calendar.mobile.month-state"].firstMatch
        XCTAssertTrue(monthState.waitForExistence(timeout: 5))
        XCTAssertEqual(monthState.value as? String, "已展开")
        let markedMonthDay = app.descendants(matching: .any)[
            "calendar.mobile.month-day-cell.\(currentShanghaiDateString())"
        ].firstMatch
        XCTAssertTrue(markedMonthDay.waitForExistence(timeout: 5))
        XCTAssertEqual(markedMonthDay.value as? String, "assignment,schoolNotice")
        let monthOverflow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '查看其余'")
        ).firstMatch
        XCTAssertTrue(monthOverflow.waitForExistence(timeout: 5))
        monthOverflow.tap()

        XCTAssertFalse(app.descendants(matching: .any)[
            "calendar.mobile.month-agenda-dialog"
        ].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)[
            "calendar.mobile.month-day-summary-card"
        ].firstMatch.waitForExistence(timeout: 5))
    }

    func testMobileYearDeadlineBorderPriorityAndDetailContent() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "仅在 iPhone 模拟器验证")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "教学日历", in: app)
        app.segmentedControls.buttons["年"].tap()
        let yearDay = app.buttons[
            "calendar.mobile.year-day.\(currentShanghaiDateString())"
        ].firstMatch
        for _ in 0..<8 where !yearDay.exists {
            app.swipeUp()
        }
        XCTAssertTrue(yearDay.waitForExistence(timeout: 5))
        XCTAssertEqual(yearDay.value as? String, "assignment,schoolNotice")
        XCTAssertTrue(yearDay.label.contains("今天"))
        yearDay.tap()

        XCTAssertTrue(app.staticTexts["课程作业 DDL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["校内竞赛通知"].exists)
        XCTAssertTrue(app.staticTexts["公开活动 DDL"].exists)
        XCTAssertTrue(app.staticTexts["全国大学生示例竞赛"].exists)
        XCTAssertTrue(app.staticTexts["示例高校夏令营"].exists)
        XCTAssertTrue(app.staticTexts["示例校园黑客松"].exists)
    }

    func testEnglishInterfaceCanBeSelectedWithoutTranslatingSampleAPIContent() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone-only localization smoke test")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = "en"
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.tabBars.buttons["Academic Calendar"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Academic Calendar"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Day"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Month"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Year"].exists)
        let weekContext = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Calendar Week ")
        ).firstMatch
        XCTAssertTrue(weekContext.waitForExistence(timeout: 5))
        XCTAssertTrue(weekContext.label.contains(" · Teaching Week "))
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(weekContext.frame))
        XCTAssertTrue(app.staticTexts["Data Mining"].exists == false)
        XCTAssertTrue(app.staticTexts["数据挖掘"].waitForExistence(timeout: 5))

        app.segmentedControls.buttons["Month"].tap()
        let monthHeading = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[A-Za-z]+ [0-9]{4}$")
        ).firstMatch
        XCTAssertTrue(monthHeading.waitForExistence(timeout: 5))
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(monthHeading.frame))
        XCTAssertTrue(app.staticTexts["calendar.mobile.month-weekday.一"].waitForExistence(timeout: 5))
        let monthState = app.descendants(matching: .any)[
            "calendar.mobile.month-state"
        ].firstMatch
        XCTAssertTrue(monthState.waitForExistence(timeout: 5))
        XCTAssertTrue(["Collapse month", "Expand month"].contains(monthState.label))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.language"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Interface Language"].exists)
        let filingButton = app.descendants(matching: .any)["action.open-app-filing"]
        revealByScrolling(visibleElement: filingButton, in: app)
        XCTAssertEqual(filingButton.label, "App filing: 琼ICP备2026012322号-2A")
        XCTAssertTrue(app.buttons["English"].exists || app.staticTexts["English"].exists)
        XCTAssertTrue(app.textFields["settings.custom-deadlines-url"].exists)
        XCTAssertTrue(app.buttons["settings.custom-deadlines-save"].exists)
    }

    func testFavoriteDeadlineSurvivesNavigationAndCanBeRemovedFromManagement() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone-only favorite flow")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "教学日历", in: app)
        let allDayButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '全天' AND label CONTAINS '+'")
        ).firstMatch
        XCTAssertTrue(allDayButton.waitForExistence(timeout: 5))
        allDayButton.tap()
        let favorite = app.buttons["calendar.favorite.contest_ddl.sample-competition"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        XCTAssertEqual(favorite.label, "收藏日程")
        favorite.tap()
        XCTAssertEqual(favorite.label, "取消收藏")
        app.buttons["关闭全天日程"].tap()

        app.tabBars.buttons["设置"].tap()
        let management = app.buttons["settings.favorite-management"]
        revealByScrolling(visibleElement: management, in: app)
        management.tap()
        XCTAssertTrue(app.descendants(matching: .any)["favorites.page"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["favorites.dismiss"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "收藏管理页面必须覆盖在主导航之上")
        XCTAssertTrue(app.staticTexts["全国大学生示例竞赛"].waitForExistence(timeout: 5))
        attachScreenshot(named: "favorites-fullscreen-management")
        let remove = app.buttons["favorites.remove.contest_ddl.sample-competition"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.staticTexts["暂无收藏日程"].waitForExistence(timeout: 5))
    }

    func testCustomFeedSettingsRejectUnsafeURLWithoutNetworkRequest() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone-only custom feed form")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--ui-testing-live"]
        app.launch()
        defer { app.terminate() }

        app.tabBars.buttons["设置"].tap()
        let field = app.textFields["settings.custom-deadlines-url"]
        revealByScrolling(visibleElement: field, in: app)
        field.tap()
        field.typeText("http://localhost/feed.json\n")
        let status = app.staticTexts["settings.custom-deadlines-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("HTTPS"))
    }

    func testSelectingAnOutOfMonthDatePagesToAndSelectsItsMonth() throws {
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }

        navigate(to: "教学日历", in: app)
        let monthMode = app.segmentedControls.buttons["月"]
        XCTAssertTrue(monthMode.waitForExistence(timeout: 5))
        monthMode.tap()

        let destinationDate = firstDayOfNextShanghaiMonth()
        let destinationKey = shanghaiDateString(destinationDate)
        let compactDay = app.buttons[
            "calendar.mobile.month-day-number.\(destinationKey)"
        ].firstMatch
        let regularDay = app.descendants(matching: .any)[
            "calendar.regular.month-day-cell.\(destinationKey)"
        ].firstMatch
        let destination = compactDay.waitForExistence(timeout: 2) ? compactDay : regularDay
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()

        let expectedHeading = shanghaiMonthHeading(destinationDate)
        let heading = app.staticTexts[expectedHeading].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        let selectedCell = app.descendants(matching: .any)[
            compactDay.exists
                ? "calendar.mobile.month-day-cell.\(destinationKey)"
                : "calendar.regular.month-day-cell.\(destinationKey)"
        ].firstMatch
        XCTAssertTrue(selectedCell.waitForExistence(timeout: 5))
        XCTAssertTrue(selectedCell.isSelected)
    }

    func testEnglishCalendarControlsFitExpandedIPadLayout() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad-only localization layout test")
        continueAfterFailure = false
        let app = configuredApplication(language: "en")
        app.launchArguments = ["--review-demo"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }

        navigateFromSidebar(to: "教学日历", in: app)
        for title in ["Day", "Week", "Month", "Year"] {
            let button = app.segmentedControls.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(button.frame))
        }
        let weekContext = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Teaching week")
        ).firstMatch
        XCTAssertTrue(weekContext.waitForExistence(timeout: 5))
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(weekContext.frame))

        app.segmentedControls.buttons["Month"].tap()
        let monthHeading = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[A-Za-z]+ [0-9]{4}$")
        ).firstMatch
        XCTAssertTrue(monthHeading.waitForExistence(timeout: 5))
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(monthHeading.frame))
        XCTAssertTrue(app.buttons["Collapse month"].waitForExistence(timeout: 5))
    }

    func testExpandedIPadWeekKeepsAllDayEventsInTheirDateColumnAndSelectsWholeHeader() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad-only expanded week test")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }

        navigateFromSidebar(to: "教学日历", in: app)
        let dateKey = nearbyShanghaiWeekDateString()
        let header = app.buttons["calendar.timeline.day-header.\(dateKey)"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(header.isHittable)

        let assignmentLink = app.descendants(matching: .any)[
            "calendar.timeline.all-day.\(dateKey).\(dateKey)-assignment-sample-assignment"
        ].firstMatch
        XCTAssertTrue(assignmentLink.waitForExistence(timeout: 5))
        XCTAssertTrue(assignmentLink.isHittable)
        XCTAssertTrue(assignmentLink.label.contains("23:59"))
        XCTAssertTrue(assignmentLink.label.contains("示例课程作业"))
        XCTAssertGreaterThanOrEqual(assignmentLink.frame.midX, header.frame.minX)
        XCTAssertLessThanOrEqual(assignmentLink.frame.midX, header.frame.maxX)

        header.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.78)).tap()
        XCTAssertTrue(waitForSelected(header))
    }

    func testCompactTabBarRestoresGeometryAfterLanguageRoundTrip() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone-only tab layout test")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = "zh-Hans"
        app.launch()
        defer { app.terminate() }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        let initialTabBarFrame = tabBar.frame
        let chineseTitles = ["空教室", "教学日历", "设置"]
        let initialButtonFrames = chineseTitles.map { title -> CGRect in
            let button = app.tabBars.buttons[title].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            return button.frame
        }

        app.tabBars.buttons["设置"].tap()
        let chinesePicker = app.segmentedControls["settings.language"].firstMatch
        revealByScrolling(visibleElement: chinesePicker, in: app)
        chinesePicker.buttons["English"].tap()

        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        let englishPicker = app.segmentedControls["settings.language"].firstMatch
        revealByScrolling(visibleElement: englishPicker, in: app)
        englishPicker.buttons["Simplified Chinese"].tap()

        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))
        let restoredTabBar = app.tabBars.firstMatch
        XCTAssertTrue(waitForFrame(initialTabBarFrame, of: restoredTabBar))
        for (index, title) in chineseTitles.enumerated() {
            XCTAssertTrue(
                waitForFrame(initialButtonFrames[index], of: app.tabBars.buttons[title].firstMatch),
                "The \(title) tab must return to its original centered geometry"
            )
        }
    }

    func testIPhoneLandscapeMonthUsesOnlyExpandedAndSelectedWeekStops() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "仅在 iPhone 模拟器验证")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        navigate(to: "教学日历", in: app)
        let monthMode = app.segmentedControls.buttons["月"]
        XCTAssertTrue(monthMode.waitForExistence(timeout: 5))
        monthMode.tap()

        let mondayHeading = app.staticTexts["calendar.mobile.month-weekday.一"].firstMatch
        let monthState = app.descendants(matching: .any)["calendar.mobile.month-state"].firstMatch
        let dateKey = currentShanghaiDateString()
        let dayCell = app.descendants(matching: .any)["calendar.mobile.month-day-cell.\(dateKey)"].firstMatch
        let dayNumber = app.buttons["calendar.mobile.month-day-number.\(dateKey)"].firstMatch
        XCTAssertTrue(mondayHeading.waitForExistence(timeout: 5))
        XCTAssertTrue(monthState.waitForExistence(timeout: 5))
        XCTAssertTrue(dayCell.waitForExistence(timeout: 5))
        XCTAssertTrue(dayNumber.waitForExistence(timeout: 5))
        XCTAssertEqual(monthState.value as? String, "已展开")

        let expandedTopInset = dayNumber.frame.minY - dayCell.frame.minY
        verticalSwipe(in: app, between: mondayHeading, and: monthState, upward: false)
        XCTAssertTrue(waitForValue("已展开", of: monthState))

        dayNumber.tap()
        XCTAssertTrue(waitForValue("日程已展开", of: monthState))
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(monthState.value as? String, "日程已展开")
        let collapsedTopInset = dayNumber.frame.minY - dayCell.frame.minY
        XCTAssertEqual(collapsedTopInset, expandedTopInset, accuracy: 1)
        XCTAssertGreaterThan(dayCell.frame.width, dayCell.frame.height * 1.5)
        attachScreenshot(named: "calendar-month-landscape-collapsed")

        XCTAssertTrue(app.descendants(matching: .any)["calendar.mobile.month-day-summary"]
            .waitForExistence(timeout: 5))
        let monthSummary = app.descendants(matching: .any)["calendar.mobile.month-day-summary"].firstMatch
        let deadlineCard = app.descendants(matching: .any)["calendar.mobile.deadlines"].firstMatch
        verticalSwipe(in: app, within: monthSummary, upward: true, requestedTravel: 48)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(
            waitForValue("已滚动", of: monthSummary),
            "The month detail scroll offset must be observable before testing gesture ownership"
        )
        verticalSwipe(in: app, within: monthSummary, upward: false, requestedTravel: 160)
        XCTAssertTrue(
            waitForValue("日程已展开", of: monthState),
            "A pull that starts before details reach the top must not change the month detent"
        )
        dayNumber.tap()
        XCTAssertTrue(waitForValue("日程已展开", of: monthState))
        XCTAssertTrue(waitForValue("顶部", of: monthSummary))
        verticalSwipe(in: app, within: monthSummary, upward: false, requestedTravel: 160)
        XCTAssertTrue(
            waitForValue("已展开", of: monthState),
            "The first new pull that begins at the real top must change the month detent"
        )
        dayNumber.tap()
        XCTAssertTrue(waitForValue("日程已展开", of: monthState))
        for _ in 0..<16 {
            verticalSwipe(in: app, within: monthSummary, upward: true, requestedTravel: 160)
        }
        XCTAssertTrue(deadlineCard.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            deadlineCard.frame.intersection(app.frame).height,
            8,
            "The taller DDL card must remain reachable in the raised detail scroller"
        )
        XCTAssertEqual(monthState.value as? String, "日程已展开")
        attachScreenshot(named: "calendar-month-landscape-details-scrolled")

        verticalSwipe(in: app, within: monthSummary, upward: true)
        XCTAssertTrue(waitForValue("日程已展开", of: monthState))
        attachScreenshot(named: "calendar-month-landscape-detail-raised")

        monthState.tap()
        XCTAssertTrue(waitForValue("已展开", of: monthState))
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(monthState.value as? String, "已展开")
        XCTAssertEqual(dayNumber.frame.minY - dayCell.frame.minY, expandedTopInset, accuracy: 1)
        attachScreenshot(named: "calendar-month-landscape-expanded")
    }

    func testSettingsCanEnterAndExitBuiltInSampleMode() {
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--ui-testing-live"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "设置", in: app)
        let enterButton = app.descendants(matching: .any)["action.enter-sample-mode"]
        XCTAssertTrue(enterButton.waitForExistence(timeout: 5))
        enterButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["banner.sample-mode"].waitForExistence(timeout: 5))

        let exitButton = app.descendants(matching: .any)["action.exit-sample-mode"]
        XCTAssertTrue(exitButton.waitForExistence(timeout: 5))
        exitButton.tap()
        XCTAssertFalse(app.descendants(matching: .any)["banner.sample-mode"].waitForExistence(timeout: 1))
    }

    func testSettingsKeyboardDismissesAfterEnteringCredentials() {
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--ui-testing-live"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        navigate(to: "设置", in: app)
        let accountField = app.textFields["field.account"]
        XCTAssertTrue(accountField.waitForExistence(timeout: 5))
        accountField.tap()
        accountField.typeText("2026000000")

        let passwordField = app.secureTextFields["field.password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText("keyboard-test")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let doneButton = app.buttons["action.dismiss-keyboard"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 2))
        doneButton.tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
    }

    func testPrivacyPolicyOpensInsideTheAppAndOffersGitHubLink() {
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--ui-testing-live"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "设置", in: app)
        let filingButton = app.descendants(matching: .any)["action.open-app-filing"]
        revealByScrolling(visibleElement: filingButton, in: app)
        XCTAssertTrue(filingButton.waitForExistence(timeout: 5))
        XCTAssertEqual(filingButton.label, "APP 备案：琼ICP备2026012322号-2A")
        let openButton = app.descendants(matching: .any)["action.open-privacy-policy"]
        revealByScrolling(visibleElement: openButton, in: app)
        openButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.privacy-policy"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "本项目只运营用于整理公开班车与活动数据的固定接口"
                )
            ).firstMatch.waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "项目不运营应用后端")
            ).firstMatch.exists
        )
        XCTAssertTrue(app.descendants(matching: .any)["action.open-privacy-github"]
            .waitForExistence(timeout: 5))

        let dismissButton = app.buttons["action.dismiss-privacy-policy"].firstMatch
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 5))
        dismissButton.tap()
        assertScreen("screen.settings", in: app)
    }

    func testSettingsShowsLiveWidgetSizePreview() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "仅在 iPhone 模拟器验证")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--ui-testing-live"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "设置", in: app)
        let preview = app.descendants(matching: .any)["widget.preview"].firstMatch
        revealByScrolling(visibleElement: preview, in: app)
        XCTAssertTrue(preview.label.contains("中号样式预览"))
        let mediumFrame = preview.frame
        attachScreenshot(named: "settings-widget-preview-medium")

        let sixCourseButton = app.segmentedControls.buttons["6"].firstMatch
        XCTAssertTrue(sixCourseButton.waitForExistence(timeout: 5))
        sixCourseButton.tap()
        let largeButton = app.segmentedControls.buttons["大号"].firstMatch
        XCTAssertTrue(largeButton.waitForExistence(timeout: 5))
        largeButton.tap()
        revealByScrolling(visibleElement: preview, in: app)
        XCTAssertTrue(preview.label.contains("大号样式预览"))
        XCTAssertGreaterThan(preview.frame.height, mediumFrame.height)
        attachScreenshot(named: "settings-widget-preview-large-top")
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<6 where preview.frame.maxY > tabBar.frame.minY {
            app.swipeUp()
        }
        XCTAssertLessThanOrEqual(preview.frame.maxY, tabBar.frame.minY)
        attachScreenshot(named: "settings-widget-preview-large-bottom")
    }

    func testPlannerSummaryLabelsRemainSeparatedOnIPhone() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "仅在 iPhone 模拟器验证")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }

        let firstLabel = app.descendants(matching: .any)["planner.summary.label.0"].firstMatch
        for _ in 0..<8 where !firstLabel.isHittable {
            app.swipeUp()
        }

        let labels = (0..<3).map {
            app.descendants(matching: .any)["planner.summary.label.\($0)"].firstMatch
        }
        for label in labels {
            XCTAssertTrue(label.waitForExistence(timeout: 5))
        }
        XCTAssertTrue(firstLabel.isHittable)
        attachScreenshot(named: "planner-summary")
        XCTAssertLessThan(labels[0].frame.maxX, labels[1].frame.minX)
        XCTAssertLessThan(labels[1].frame.maxX, labels[2].frame.minX)
    }

    func testCompactTabBottomSafeAreaPolicyIsSectionSpecific() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "仅在 iPhone 模拟器验证")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        let plannerSummary = app.staticTexts["查询概览"]
        scrollToBottom(visibleElement: plannerSummary, in: app)
        XCTAssertLessThan(plannerSummary.frame.maxY, tabBar.frame.minY)
        attachScreenshot(named: "planner-bottom-safe-area")

        navigate(to: "教学日历", in: app)
        let weekMode = app.segmentedControls.buttons["周"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 5))
        weekMode.tap()
        let firstHour = app.staticTexts["calendar.mobile.hour.08"].firstMatch
        XCTAssertTrue(firstHour.waitForExistence(timeout: 5))
        let timeline = app.scrollViews.containing(
            .staticText,
            identifier: "calendar.mobile.hour.08"
        ).firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(timeline.frame.maxY, tabBar.frame.minY)
        attachScreenshot(named: "calendar-under-tab-bar")

        navigate(to: "设置", in: app)
        let privacyButton = app.descendants(matching: .any)["action.open-privacy-policy"]
        scrollToBottom(visibleElement: privacyButton, in: app)
        XCTAssertLessThan(privacyButton.frame.maxY, tabBar.frame.minY)
        attachScreenshot(named: "settings-bottom-safe-area")
    }

    func testIPadUsesPersistentSidebarAndExpandedLayoutsAcrossRotation() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "仅在 iPad 模拟器验证")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--ui-testing"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        assertRegularSidebar(in: app)
        assertScreen("screen.planner", in: app)
        attachScreenshot(named: "store-ipad-planner-landscape")
        navigateFromSidebar(to: "教学日历", in: app)
        assertScreen("screen.calendar", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["layout.calendar.expanded"]
            .waitForExistence(timeout: 5))
        let sidebarToggle = app.buttons["navigation.sidebar-toggle"]
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
        sidebarToggle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["layout.calendar.expanded"]
            .waitForExistence(timeout: 3))
        let selectedSidebarItem = app.descendants(matching: .any)["navigation.calendar"].firstMatch
        XCTAssertTrue(selectedSidebarItem.waitForExistence(timeout: 3))
        XCTAssertEqual(selectedSidebarItem.frame.width, selectedSidebarItem.frame.height, accuracy: 2)
        sidebarToggle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["layout.calendar.expanded"]
            .waitForExistence(timeout: 3))
        let monthMode = app.segmentedControls.buttons["月"]
        XCTAssertTrue(monthMode.waitForExistence(timeout: 5))
        monthMode.tap()
        let monthHeading = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年[0-9]+月$")
        ).firstMatch
        XCTAssertTrue(monthHeading.waitForExistence(timeout: 5))
        let initialMonth = monthHeading.label
        let collapseMonth = app.buttons["折叠月历"]
        XCTAssertTrue(collapseMonth.waitForExistence(timeout: 5))
        collapseMonth.tap()
        XCTAssertTrue(app.buttons["展开日程"].waitForExistence(timeout: 5))
        horizontalSwipe(in: app, atY: 0.52, toLeft: true)
        XCTAssertTrue(waitForLabelChange(of: monthHeading, from: initialMonth))
        let pagedMonth = monthHeading.label
        attachScreenshot(named: "ipad-calendar-landscape")

        XCUIDevice.shared.orientation = .portrait
        assertRegularSidebar(in: app)
        let compactMonthState = app.descendants(matching: .any)["calendar.mobile.month-state"]
        if compactMonthState.waitForExistence(timeout: 2) {
            let compactPeriod = app.staticTexts.matching(
                NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年[0-9]+月$")
            ).firstMatch
            XCTAssertTrue(compactPeriod.waitForExistence(timeout: 2))
            XCTAssertTrue(compactPeriod.label.range(
                of: "^[0-9]{4}年[0-9]+月$",
                options: .regularExpression
            ) != nil)
            XCTAssertTrue(app.segmentedControls.buttons["月"].isSelected)
            XCTAssertEqual(monthHeading.label, pagedMonth)
            XCTAssertEqual(compactMonthState.value as? String, "已收起")
            attachScreenshot(named: "ipad-calendar-portrait-compact-state-preserved")
        } else {
            XCTAssertTrue(app.descendants(matching: .any)["layout.calendar.expanded"]
                .waitForExistence(timeout: 5))
            XCTAssertTrue(app.segmentedControls.buttons["月"].isSelected)
            XCTAssertEqual(monthHeading.label, pagedMonth)
            XCTAssertTrue(app.buttons["展开日程"].waitForExistence(timeout: 5))
            attachScreenshot(named: "ipad-calendar-portrait-expanded-state-preserved")
        }
        navigateFromSidebar(to: "查询", in: app)
        assertScreen("screen.information-queries", in: app)
        XCTAssertTrue(app.segmentedControls.buttons["班车查询"].waitForExistence(timeout: 5))
        navigateFromSidebar(to: "设置", in: app)
        assertScreen("screen.settings", in: app)
        attachScreenshot(named: "ipad-settings-portrait")
    }

    func testStoreIPad13LandscapeScreenshots() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "仅在 iPad 模拟器生成")
        continueAfterFailure = false
        let app = configuredApplication()
        app.launchArguments = ["--review-demo"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        assertRegularSidebar(in: app)
        assertScreen("screen.planner", in: app)
        let weatherToggle = app.descendants(matching: .any)["weather.toggle"].firstMatch
        if weatherToggle.waitForExistence(timeout: 5), weatherToggle.value as? String == "已折叠" {
            weatherToggle.tap()
            XCTAssertTrue(waitForValue("已展开", of: weatherToggle))
        }
        let clearSlots = app.buttons["清空"]
        if clearSlots.waitForExistence(timeout: 3) {
            clearSlots.tap()
            let firstSlot = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "第 1 节")
            ).firstMatch
            XCTAssertTrue(firstSlot.waitForExistence(timeout: 3))
            firstSlot.tap()
        }
        for building in ["教1", "教2", "主楼"] {
            let button = app.buttons[building]
            if button.waitForExistence(timeout: 3) {
                button.tap()
            }
        }
        attachScreenshot(named: "effect-ipad-13-landscape-planner")
        let firstRoom = app.staticTexts["教1-101"]
        if firstRoom.waitForExistence(timeout: 3) {
            revealByScrolling(visibleElement: firstRoom, in: app)
            attachScreenshot(named: "effect-ipad-13-landscape-planner-results")
        }

        navigateFromSidebar(to: "教学日历", in: app)
        assertScreen("screen.calendar", in: app)
        let monthMode = app.segmentedControls.buttons["月"]
        XCTAssertTrue(monthMode.waitForExistence(timeout: 5))
        monthMode.tap()
        let collapseMonth = app.buttons["折叠月历"]
        if collapseMonth.waitForExistence(timeout: 5) {
            collapseMonth.tap()
            XCTAssertTrue(app.buttons["展开日程"].waitForExistence(timeout: 5))
        }
        attachScreenshot(named: "effect-ipad-13-landscape-calendar")

        navigateFromSidebar(to: "设置", in: app)
        assertScreen("screen.settings", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.reference-notice"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["学科竞赛 DDL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["校内竞赛通知"].waitForExistence(timeout: 5))
        attachScreenshot(named: "effect-ipad-13-landscape-settings")

        let privacyButton = app.descendants(matching: .any)["action.open-privacy-policy"].firstMatch
        revealByScrolling(visibleElement: privacyButton, in: app)
        privacyButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.privacy-policy"]
            .waitForExistence(timeout: 5))
        attachScreenshot(named: "effect-ipad-13-landscape-privacy")
    }

    private func assertMobileCalendarControls(in app: XCUIApplication) {
        let weekMode = app.segmentedControls.buttons["周"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 5))
        attachScreenshot(named: "calendar-week")

        let dayMode = app.segmentedControls.buttons["日"]
        XCTAssertTrue(dayMode.waitForExistence(timeout: 5))
        dayMode.tap()
        attachScreenshot(named: "calendar-day")

        let monthMode = app.segmentedControls.buttons["月"]
        XCTAssertTrue(monthMode.exists)
        monthMode.tap()
        attachScreenshot(named: "calendar-month")

        let yearMode = app.segmentedControls.buttons["年"]
        XCTAssertTrue(yearMode.exists)
        yearMode.tap()
        attachScreenshot(named: "calendar-year")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForLabelChange(of element: XCUIElement, from label: String) -> Bool {
        let predicate = NSPredicate(format: "label != %@", label)
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 5
        ) == .completed
    }

    private func waitForLabel(_ label: String, of element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 5
        ) == .completed
    }

    private func waitForFrame(
        _ expected: CGRect,
        of element: XCUIElement,
        accuracy: CGFloat = 2
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let candidate = object as? XCUIElement else { return false }
            let frame = candidate.frame
            return abs(frame.minX - expected.minX) <= accuracy
                && abs(frame.minY - expected.minY) <= accuracy
                && abs(frame.width - expected.width) <= accuracy
                && abs(frame.height - expected.height) <= accuracy
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 5
        ) == .completed
    }

    private func horizontalSwipe(in app: XCUIApplication, atY y: CGFloat, toLeft: Bool) {
        let startX: CGFloat = toLeft ? 0.82 : 0.18
        let endX: CGFloat = toLeft ? 0.18 : 0.82
        app.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: y))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: y))
            )
    }

    private func verticalSwipe(
        in app: XCUIApplication,
        between topElement: XCUIElement,
        and bottomElement: XCUIElement,
        upward: Bool
    ) {
        let topY = topElement.frame.maxY
        let bottomY = bottomElement.frame.minY
        let distance = bottomY - topY
        XCTAssertGreaterThan(distance, 32)
        let centerY = topY + distance * 0.5
        let travel = min(distance * 0.5, 180)
        let startY = centerY + (upward ? travel * 0.5 : -travel * 0.5)
        let endY = centerY + (upward ? -travel * 0.5 : travel * 0.5)
        let appOrigin = app.coordinate(withNormalizedOffset: .zero)
        let start = appOrigin.withOffset(CGVector(
            dx: app.frame.midX - app.frame.minX,
            dy: startY - app.frame.minY
        ))
        let end = appOrigin.withOffset(CGVector(
            dx: app.frame.midX - app.frame.minX,
            dy: endY - app.frame.minY
        ))
        start
            .press(
                forDuration: 0.05,
                thenDragTo: end
            )
    }

    private func verticalSwipe(
        in app: XCUIApplication,
        within element: XCUIElement,
        upward: Bool,
        requestedTravel: CGFloat? = nil
    ) {
        let frame = element.frame.intersection(app.frame)
        XCTAssertGreaterThan(frame.height, 80)
        // The compact floating tab bar overlays the lower edge of the calendar
        // ScrollView in landscape. Start above that overlay so XCTest exercises
        // the same visible card surface that a user can actually drag.
        let unobscuredBottom = min(frame.maxY - 28, app.frame.maxY - 96)
        let unobscuredTop = frame.minY + 20
        let availableTravel = max(unobscuredBottom - unobscuredTop, 1)
        let travel = min(
            requestedTravel ?? max(frame.height * 0.35, 72),
            availableTravel
        )
        let startY = upward ? unobscuredBottom : unobscuredTop
        let endY = upward ? startY - travel : startY + travel
        let appOrigin = app.coordinate(withNormalizedOffset: .zero)
        let start = appOrigin.withOffset(CGVector(
            dx: frame.midX - app.frame.minX,
            dy: startY - app.frame.minY
        ))
        let end = appOrigin.withOffset(CGVector(
            dx: frame.midX - app.frame.minX,
            dy: endY - app.frame.minY
        ))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func scrollToBottom(visibleElement: XCUIElement, in app: XCUIApplication) {
        revealByScrolling(visibleElement: visibleElement, in: app)
        app.swipeUp()
    }

    private func revealByScrolling(visibleElement: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 where !visibleElement.exists || !visibleElement.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(visibleElement.waitForExistence(timeout: 5))
        XCTAssertTrue(visibleElement.isHittable)
    }

    private func waitForValue(_ value: String, of element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 5
        ) == .completed
    }

    private func waitForSelected(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate { object, _ in
            (object as? XCUIElement)?.isSelected == true
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 5
        ) == .completed
    }

    private func currentShanghaiDateString() -> String {
        shanghaiDateString(Date())
    }

    private func nearbyShanghaiDateString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = Date()
        let day = calendar.component(.day, from: today)
        let lastDay = calendar.range(of: .day, in: .month, for: today)?.last ?? day
        let offset = day < lastDay ? 1 : -1
        return shanghaiDateString(calendar.date(byAdding: .day, value: offset, to: today)!)
    }

    private func nearbyShanghaiWeekDateString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let offset = calendar.component(.weekday, from: Date()) == 1 ? -1 : 1
        return shanghaiDateString(calendar.date(byAdding: .day, value: offset, to: Date())!)
    }

    private func shiftedShanghaiDateString(months: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return shanghaiDateString(
            calendar.date(byAdding: .month, value: months, to: Date())!
        )
    }

    private func firstDayOfNextShanghaiMonth() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let currentMonth = calendar.dateInterval(of: .month, for: Date())!.start
        return calendar.date(byAdding: .month, value: 1, to: currentMonth)!
    }

    private func shanghaiMonthHeading(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private func shanghaiDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func configuredApplication(language: String = "zh-Hans") -> XCUIApplication {
        let app = XCUIApplication()
        // UI tests share the simulator's persisted defaults and may run in a
        // different order on CI. Pin each launch so an English-language test
        // cannot change the labels expected by the next test.
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = language
        return app
    }

    private func navigate(to title: String, in app: XCUIApplication) {
        let tabDestination = app.tabBars.buttons[title]
        if tabDestination.exists {
            XCTAssertTrue(tabDestination.waitForExistence(timeout: 5), "Missing navigation item: \(title)")
            tabDestination.tap()
        } else {
            navigateFromSidebar(to: title, in: app)
        }
    }

    private func navigateFromSidebar(to title: String, in app: XCUIApplication) {
        let destination = app.descendants(matching: .any)["navigation.\(sectionID(for: title))"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "Missing navigation item: \(title)")
        destination.tap()
    }

    private func assertRegularSidebar(in app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["layout.regular-sidebar"]
            .waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    private func sectionID(for title: String) -> String {
        switch title {
        case "空教室": return "planner"
        case "教学日历": return "calendar"
        case "查询": return "queries"
        case "设置": return "settings"
        default:
            XCTFail("Unknown section: \(title)")
            return ""
        }
    }

    private func assertScreen(_ identifier: String, in app: XCUIApplication) {
        let screen = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "Missing screen: \(identifier)")
    }
}
