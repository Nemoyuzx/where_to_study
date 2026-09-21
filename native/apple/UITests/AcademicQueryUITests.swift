import XCTest

@MainActor
final class AcademicQueryUITests: XCTestCase {
    func testPhoneQueryIconsKeepAccessibleNamesAndSelectionAtAllTextSizes() {
        continueAfterFailure = false
        let originalAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = originalAppearance }
        for language in ["zh-Hans", "en"] {
            for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXL"] {
                let app = XCUIApplication()
                app.launchArguments = ["--ui-testing", "--ui-testing-academic",
                                       "-UIPreferredContentSizeCategoryName", category]
                app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = language
                app.launch()
                navigate("queries", title: language == "en" ? "Search" : "查询", in: app)
                let picker = app.segmentedControls["queries.mode"]
                XCTAssertTrue(picker.waitForExistence(timeout: 10))
                let names = language == "en"
                    ? ["Shuttle Search", "Important Events", "Grades", "Exams", "Assignment Deadlines"]
                    : ["班车查询", "重要事件", "成绩查询", "考试安排", "课程作业 DDL"]
                for name in names {
                    let segment = picker.buttons[name]
                    XCTAssertTrue(segment.exists, "Missing full accessible title: \(name)")
                    XCTAssertTrue(segment.isHittable)
                    XCTAssertGreaterThanOrEqual(segment.frame.minX, picker.frame.minX - 1)
                    XCTAssertLessThanOrEqual(segment.frame.maxX, picker.frame.maxX + 1)
                    segment.tap()
                    XCTAssertTrue(segment.isSelected)
                }
                XCTAssertGreaterThanOrEqual(picker.frame.minX, app.frame.minX)
                XCTAssertLessThanOrEqual(picker.frame.maxX, app.frame.maxX)
                for appearance in [XCUIDevice.Appearance.light, .dark] {
                    XCUIDevice.shared.appearance = appearance
                    // The system appearance transition can outlive XCTest's
                    // idle check; capture the settled palette, not its first frame.
                    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                    XCTAssertTrue(picker.buttons[names[4]].isSelected)
                    capture("query-icons-\(language)-\(category)-\(appearance == .dark ? "dark" : "light")")
                }
                app.terminate()
            }
        }
    }

    func testSyntheticGradeQueryEnglish() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-academic"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = "en"
        app.launch()
        defer { app.terminate() }
        navigate("queries", title: "Search", in: app)
        let assignments = app.segmentedControls.buttons["Assignment Deadlines"]
        XCTAssertTrue(assignments.waitForExistence(timeout: 10))
        assignments.tap()
        XCTAssertTrue(app.staticTexts["Sample assignments; no teaching cloud connection"].waitForExistence(timeout: 10))
        capture("synthetic-assignment-query-english")
        app.segmentedControls.buttons["Exams"].tap()
        XCTAssertTrue(app.staticTexts["Sample exams; no school connection"].waitForExistence(timeout: 10))
        let grades = app.segmentedControls.buttons["Grades"]
        XCTAssertTrue(grades.waitForExistence(timeout: 10))
        grades.tap()
        XCTAssertTrue(app.staticTexts["Information Search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample grades; no school connection"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["All records"].exists)
        capture("synthetic-grades-query-english")
    }

    func testSyntheticGradeQueryAndExamCalendar() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-academic"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = "zh-Hans"
        app.launch()
        defer { app.terminate() }
        navigate("queries", title: "查询", in: app)
        let assignments = app.segmentedControls.buttons["课程作业 DDL"]
        XCTAssertTrue(assignments.waitForExistence(timeout: 10))
        assignments.tap()
        XCTAssertTrue(app.staticTexts["示例课程作业"].waitForExistence(timeout: 10))
        app.buttons["assignments.refresh"].tap()
        XCTAssertTrue(app.staticTexts["示例课程作业"].waitForExistence(timeout: 5))
        capture("synthetic-assignment-query")
        app.segmentedControls.buttons["考试安排"].tap()
        XCTAssertTrue(app.staticTexts["示例考试（非真实安排）"].waitForExistence(timeout: 10))
        capture("synthetic-exam-query")
        let grades = app.segmentedControls.buttons["成绩查询"]
        XCTAssertTrue(grades.waitForExistence(timeout: 10))
        grades.tap()
        XCTAssertTrue(app.staticTexts["示例课程（非真实成绩）"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["优秀"].exists)
        app.buttons["grades.refresh"].tap()
        XCTAssertTrue(app.staticTexts["示例课程（非真实成绩）"].waitForExistence(timeout: 5))
        capture("synthetic-grades-query")
        navigate("calendar", title: "教学日历", in: app)
        let day = app.segmentedControls.buttons["日"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10))
        day.tap()
        XCTAssertTrue(app.staticTexts["示例考试（非真实安排）"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["数据挖掘"].exists)
        capture("synthetic-exam-calendar")
    }

    private func navigate(_ id: String, title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        if tab.waitForExistence(timeout: 2) { tab.tap(); return }
        let destination = app.descendants(matching: .any)["navigation.\(id)"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
