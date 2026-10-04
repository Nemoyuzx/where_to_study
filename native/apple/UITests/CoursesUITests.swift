import XCTest

@MainActor
final class CoursesUITests: XCTestCase {
    func testCoursesDefaultToCurrentTermAndQueriesContainOnlyPublicSources() {
        continueAfterFailure = false
        for language in ["zh-Hans", "en"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--ui-testing-academic"]
            app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = language
            app.launch()
            assertPrimaryNavigation(in: app, language: language)
            navigate("courses", title: language == "en" ? "Courses" : "课程", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["screen.courses"].waitForExistence(timeout: 5))
            let pageTitle = app.descendants(matching: .any)["courses.page-title"].firstMatch
            XCTAssertTrue(pageTitle.waitForExistence(timeout: 5))
            XCTAssertTrue(pageTitle.isHittable)
            #if os(iOS)
            // The page owns its single heading; no second system large title.
            XCTAssertEqual(app.navigationBars.count, 0)
            #endif
            let modes = app.segmentedControls["courses.mode"]
            let names = language == "en" ? ["Current Courses", "Assignment Deadlines", "Grades", "Exams"]
                : ["本学期课程", "课程作业 DDL", "成绩查询", "考试安排"]
            XCTAssertTrue(modes.waitForExistence(timeout: 5))
            XCTAssertTrue(modes.buttons[names[0]].isSelected)
            let courseRow = app.buttons["courses.ucloud.course.sample-course"].firstMatch
            XCTAssertTrue(courseRow.waitForExistence(timeout: 5))
            XCTAssertTrue(courseRow.isHittable)
            XCTAssertGreaterThanOrEqual(courseRow.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(courseRow.frame.maxX, app.frame.maxX)
            courseRow.tap()
            XCTAssertTrue(app.descendants(matching: .any)["course-detail.page"].waitForExistence(timeout: 5))
            let official = app.descendants(matching: .any)["course-detail.open-official"].firstMatch
            XCTAssertTrue(official.waitForExistence(timeout: 5))
            XCTAssertTrue(official.isHittable)
            let close = app.buttons["course-detail.close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
            XCTAssertTrue(modes.waitForExistence(timeout: 5))
            for name in names {
                let destination = modes.buttons[name]
                XCTAssertTrue(destination.isHittable)
                XCTAssertGreaterThanOrEqual(destination.frame.minX, modes.frame.minX - 1)
                XCTAssertLessThanOrEqual(destination.frame.maxX, modes.frame.maxX + 1)
                destination.tap(); XCTAssertTrue(destination.isSelected)
            }
            navigate("queries", title: language == "en" ? "Search" : "查询", in: app)
            let queryModes = app.segmentedControls["queries.mode"]
            XCTAssertEqual(queryModes.buttons.count, 2)
            XCTAssertFalse(queryModes.buttons[language == "en" ? "Grades" : "成绩查询"].exists)
            navigate("settings", title: language == "en" ? "Settings" : "设置", in: app)
            XCTAssertEqual(app.secureTextFields.matching(NSPredicate(format: "identifier CONTAINS[c] %@", "qmplus")).count, 0)
            app.terminate()
        }
    }

    private func navigate(_ id: String, title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.waitForExistence(timeout: 2) {
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            return
        }
        let sidebar = app.descendants(matching: .any)["navigation.\(id)"].firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "Missing navigation destination: \(title)")
        XCTAssertTrue(sidebar.isHittable)
        sidebar.tap()
    }

    private func assertPrimaryNavigation(in app: XCUIApplication, language: String) {
        let ids = ["planner", "calendar", "courses", "queries", "settings"]
        let titles = language == "en" ? ["Empty Rooms", "Academic Calendar", "Courses", "Search", "Settings"]
            : ["空教室", "教学日历", "课程", "查询", "设置"]
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 2) {
            XCTAssertEqual(tabBar.buttons.count, 5)
            for title in titles {
                let item = tabBar.buttons[title].firstMatch
                XCTAssertTrue(item.waitForExistence(timeout: 5))
                XCTAssertTrue(item.isHittable)
                XCTAssertGreaterThanOrEqual(item.frame.minX, tabBar.frame.minX - 1)
                XCTAssertLessThanOrEqual(item.frame.maxX, tabBar.frame.maxX + 1)
                XCTAssertGreaterThanOrEqual(item.frame.minY, tabBar.frame.minY - 1)
                XCTAssertLessThanOrEqual(item.frame.maxY, tabBar.frame.maxY + 1)
            }
        } else {
            for id in ids {
                let item = app.descendants(matching: .any)["navigation.\(id)"].firstMatch
                XCTAssertTrue(item.waitForExistence(timeout: 5))
                XCTAssertTrue(item.isHittable)
                XCTAssertGreaterThanOrEqual(item.frame.minX, app.frame.minX)
                XCTAssertLessThanOrEqual(item.frame.maxX, app.frame.maxX)
            }
        }
    }
}
