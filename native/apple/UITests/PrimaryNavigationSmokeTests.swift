import XCTest
import UIKit

@MainActor
final class PrimaryNavigationSmokeTests: XCTestCase {
    func testPrimaryPagesAreNavigable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }

        assertScreen("screen.planner", in: app)
        navigate(to: "教学日历", in: app)
        assertScreen("screen.calendar", in: app)
        assertMobileCalendarControls(in: app)
        navigate(to: "设置", in: app)
        assertScreen("screen.settings", in: app)
        navigate(to: "空教室", in: app)
        assertScreen("screen.planner", in: app)
    }

    func testReviewDemoShowsLocalDataWithoutAccount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--review-demo"]
        app.launch()
        defer { app.terminate() }

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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
        app.launchArguments = ["--review-demo"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "教学日历", in: app)
        let periodLabel = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年[0-9]+月 第 [0-9]+ 周$")
        ).firstMatch
        XCTAssertTrue(periodLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(periodLabel.label.contains("第 "))
        XCTAssertTrue(periodLabel.label.hasSuffix(" 周"))
        attachScreenshot(named: "calendar-week-single-viewport")
        let initialWeek = periodLabel.label
        horizontalSwipe(in: app, atY: 0.29, toLeft: true)
        XCTAssertTrue(waitForLabelChange(of: periodLabel, from: initialWeek))
        horizontalSwipe(in: app, atY: 0.29, toLeft: false)
        XCTAssertEqual(periodLabel.label, initialWeek)

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
        XCTAssertFalse(app.descendants(matching: .any)["calendar.mobile.month-day-summary"].exists)
        let monthEventID = "calendar.mobile.month-event.course-sample-data-mining"
        let monthEvent = app.staticTexts[monthEventID].firstMatch
        XCTAssertTrue(monthEvent.waitForExistence(timeout: 5))
        XCTAssertFalse(monthEvent.label.isEmpty)
        XCTAssertFalse(app.buttons[monthEventID].exists)
        monthEvent.tap()
        XCTAssertEqual(month.value as? String, "已展开")
        XCTAssertFalse(app.descendants(matching: .any)["calendar.mobile.month-day-summary"].exists)
        attachScreenshot(named: "calendar-month-expanded")
        let initialMonthHeadingY = monthHeading.frame.minY
        let initialMondayHeadingY = mondayHeading.frame.minY
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
            yearDay.tap()

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

    func testIPhoneLandscapeMonthUsesOnlyExpandedAndSelectedWeekStops() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "仅在 iPhone 模拟器验证")
        continueAfterFailure = false
        let app = XCUIApplication()
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
        for _ in 0..<10 where !deadlineCard.isHittable {
            verticalSwipe(in: app, within: monthSummary, upward: true)
        }
        XCTAssertTrue(deadlineCard.waitForExistence(timeout: 5))
        XCTAssertTrue(deadlineCard.isHittable)
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-live"]
        app.launch()
        defer { app.terminate() }

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

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.18)).tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        passwordField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        let doneButton = app.buttons["action.dismiss-keyboard"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 2))
        doneButton.tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
    }

    func testPrivacyPolicyOpensInsideTheAppAndOffersGitHubLink() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-live"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "设置", in: app)
        let openButton = app.descendants(matching: .any)["action.open-privacy-policy"]
        revealByScrolling(visibleElement: openButton, in: app)
        openButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.privacy-policy"]
            .waitForExistence(timeout: 5))
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        navigateFromSidebar(to: "设置", in: app)
        assertScreen("screen.settings", in: app)
        attachScreenshot(named: "ipad-settings-portrait")
    }

    func testStoreIPad13LandscapeScreenshots() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "仅在 iPad 模拟器生成")
        continueAfterFailure = false
        let app = XCUIApplication()
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
        attachScreenshot(named: "effect-ipad-13-landscape-planner")

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
            timeout: 3
        ) == .completed
    }

    private func waitForLabel(_ label: String, of element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 3
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
            timeout: 3
        ) == .completed
    }

    private func currentShanghaiDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
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
