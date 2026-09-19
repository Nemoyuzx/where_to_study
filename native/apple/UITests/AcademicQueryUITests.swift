import XCTest

@MainActor
final class AcademicQueryUITests: XCTestCase {
    func testSyntheticGradeQueryEnglish() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-academic"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = "en"
        app.launch()
        defer { app.terminate() }
        navigate("queries", title: "Queries", in: app)
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
