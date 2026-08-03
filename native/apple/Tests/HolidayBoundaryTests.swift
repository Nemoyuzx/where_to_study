import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class HolidayBoundaryTests: XCTestCase {
    func testEmptyNameAndRangeAreRejectedBeforeUnknownTypeIsSkipped() {
        assertParserRejects(
            #"[{"name":"  ","range":["2026-01-01"],"type":"future-type"}]"#,
            message: "节假日名称不能为空。"
        )
        assertParserRejects(
            #"[{"name":"测试","range":[],"type":"future-type"}]"#,
            message: "节假日日期范围不能为空。"
        )
    }

    func testValidUnknownTypeIsIgnored() throws {
        let snapshot = try parse(
            #"[{"name":"测试","range":["2026-01-01"],"type":"future-type"}]"#
        )

        XCTAssertTrue(snapshot.items.isEmpty)
    }

    func testTransportMetadataUsesRawHTTPS() {
        XCTAssertEqual(
            HolidayDefaults.source,
            "https://raw.githubusercontent.com/bastengao/chinese-holidays-data/master/data"
        )
    }

    func testHolidayStoreRoundTripsMaximumContractValues() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = String(repeating: "n", count: HolidaySourceLimits.maximumNameLength)
        let item = HolidayItem(date: "2026-01-01", name: name, type: "holiday")
        let expected = snapshot(
            source: String(repeating: "s", count: 512),
            fetchedAt: "2026-01-05T00:00:00Z",
            items: Array(repeating: item, count: HolidaySourceLimits.maximumExpandedItems)
        )

        try store.save(expected)

        XCTAssertEqual(try store.load(year: 2026), expected)
        let size = try Data(contentsOf: cacheURL(in: directory, year: 2026)).count
        XCTAssertLessThanOrEqual(size, HolidaySourceLimits.maximumPayloadBytes)
    }

    func testHolidayStoreAcceptsSupportedYearBoundaries() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        for year in [HolidayDefaults.supportedYears.lowerBound, HolidayDefaults.supportedYears.upperBound] {
            let expected = snapshot(
                year: year,
                items: [HolidayItem(date: "\(year)-01-01", name: "边界", type: "workday")]
            )
            try store.save(expected)
            XCTAssertEqual(try store.load(year: year), expected)
        }
    }

    func testHolidayStoreRejectsInvalidRequestedAndSnapshotYears() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        assertError(
            message: "节假日年份不在支持范围内。",
            expression: { try store.load(year: 1899) }
        )
        assertError(
            message: "节假日年份不在支持范围内。",
            expression: { try store.load(year: 2101) }
        )
        assertSaveRejects(
            snapshot(year: 1899, items: []),
            store: store,
            message: "本地节假日缓存的年份不在支持范围内。"
        )
        assertSaveRejects(
            snapshot(year: 2101, items: []),
            store: store,
            message: "本地节假日缓存的年份不在支持范围内。"
        )

        var mismatched = validRoot
        mismatched["year"] = 2025
        try writeCache(mismatched, to: directory, requestedYear: 2026)
        assertError(
            message: "本地节假日缓存年份与请求不一致。",
            expression: { try store.load(year: 2026) }
        )
    }

    func testHolidayStoreRejectsContractViolationsOnSave() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let validItem = HolidayItem(date: "2026-01-01", name: "测试", type: "holiday")

        let cases: [(HolidaysSnapshot, String)] = [
            (snapshot(source: " "), "本地节假日缓存的数据源不正确。"),
            (snapshot(source: String(repeating: "s", count: 513)), "本地节假日缓存的数据源不正确。"),
            (snapshot(fetchedAt: "2026-01-05T08:00:00.1+08:00"), "本地节假日缓存的获取时间不正确。"),
            (snapshot(fetchedAt: String(repeating: "x", count: 65)), "本地节假日缓存的获取时间不正确。"),
            (snapshot(fetchedAt: "2026-02-30T08:00:00+08:00"), "本地节假日缓存的获取时间不正确。"),
            (snapshot(fetchedAt: "2026-01-05T24:00:00+08:00"), "本地节假日缓存的获取时间不正确。"),
            (snapshot(fetchedAt: "2026-01-05T08:00:00+24:00"), "本地节假日缓存的获取时间不正确。"),
            (
                snapshot(items: Array(
                    repeating: validItem,
                    count: HolidaySourceLimits.maximumExpandedItems + 1
                )),
                "本地节假日缓存的条目数量超过限制。"
            ),
            (
                snapshot(items: [HolidayItem(date: "2026-02-30", name: "测试", type: "holiday")]),
                "本地节假日缓存的日期不正确。"
            ),
            (
                snapshot(items: [HolidayItem(date: "2025-12-31", name: "测试", type: "holiday")]),
                "本地节假日缓存包含其他年份的日期。"
            ),
            (
                snapshot(items: [HolidayItem(date: "2026-01-01", name: "  ", type: "holiday")]),
                "本地节假日缓存的名称不正确。"
            ),
            (
                snapshot(items: [HolidayItem(
                    date: "2026-01-01",
                    name: String(repeating: "节", count: HolidaySourceLimits.maximumNameLength + 1),
                    type: "holiday"
                )]),
                "本地节假日缓存的名称不正确。"
            ),
            (
                snapshot(items: [HolidayItem(date: "2026-01-01", name: "测试", type: "workingday")]),
                "本地节假日缓存的类型不正确。"
            )
        ]

        for (invalidSnapshot, message) in cases {
            assertSaveRejects(invalidSnapshot, store: store, message: message)
        }
    }

    func testHolidayStoreRejectsContractViolationsOnLoad() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let validItem = validItemRoot

        var cases = [(Any, String)]()
        var root = validRoot
        root["source"] = " "
        cases.append((root, "本地节假日缓存的数据源不正确。"))
        root = validRoot
        root["source"] = String(repeating: "s", count: 513)
        cases.append((root, "本地节假日缓存的数据源不正确。"))
        root = validRoot
        root["fetched_at"] = "2026-01-05T08:00:00.1+08:00"
        cases.append((root, "本地节假日缓存的获取时间不正确。"))
        root = validRoot
        root["fetched_at"] = String(repeating: "x", count: 65)
        cases.append((root, "本地节假日缓存的获取时间不正确。"))
        root = validRoot
        root["fetched_at"] = "2026-02-30T08:00:00+08:00"
        cases.append((root, "本地节假日缓存的获取时间不正确。"))
        root = validRoot
        root["fetched_at"] = "2026-01-05T24:00:00+08:00"
        cases.append((root, "本地节假日缓存的获取时间不正确。"))
        root = validRoot
        root["fetched_at"] = "2026-01-05T08:00:00+24:00"
        cases.append((root, "本地节假日缓存的获取时间不正确。"))
        root = validRoot
        root["items"] = Array(repeating: validItem, count: HolidaySourceLimits.maximumExpandedItems + 1)
        cases.append((root, "本地节假日缓存的条目数量超过限制。"))
        root = validRoot
        root["items"] = [["date": "2026-02-30", "name": "测试", "type": "holiday"]]
        cases.append((root, "本地节假日缓存的日期不正确。"))
        root = validRoot
        root["items"] = [["date": "2025-12-31", "name": "测试", "type": "holiday"]]
        cases.append((root, "本地节假日缓存包含其他年份的日期。"))
        root = validRoot
        root["items"] = [["date": "2026-01-01", "name": " ", "type": "holiday"]]
        cases.append((root, "本地节假日缓存的名称不正确。"))
        root = validRoot
        root["items"] = [[
            "date": "2026-01-01",
            "name": String(repeating: "节", count: HolidaySourceLimits.maximumNameLength + 1),
            "type": "holiday"
        ]]
        cases.append((root, "本地节假日缓存的名称不正确。"))
        root = validRoot
        root["items"] = [["date": "2026-01-01", "name": "测试", "type": "workingday"]]
        cases.append((root, "本地节假日缓存的类型不正确。"))

        for (object, message) in cases {
            try writeCache(object, to: directory, requestedYear: 2026)
            assertError(message: message, expression: { try store.load(year: 2026) })
        }
    }

    func testHolidayStoreRejectsUnknownRootAndItemFields() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var root = validRoot
        root["unexpected"] = true
        try writeCache(root, to: directory, requestedYear: 2026)
        assertError(
            message: "本地节假日缓存字段不正确。",
            expression: { try store.load(year: 2026) }
        )

        var item = validItemRoot
        item["unexpected"] = true
        root = validRoot
        root["items"] = [item]
        try writeCache(root, to: directory, requestedYear: 2026)
        assertError(
            message: "本地节假日缓存的条目字段不正确。",
            expression: { try store.load(year: 2026) }
        )
    }

    private func parse(_ value: String) throws -> HolidaysSnapshot {
        try HolidaySourceParser.parse(
            data: Data(value.utf8),
            year: 2026,
            source: HolidayDefaults.source,
            fetchedAt: "2026-01-05T08:00:00+08:00"
        )
    }

    private func assertParserRejects(
        _ value: String,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try parse(value), file: file, line: line) { error in
            XCTAssertEqual(error.localizedDescription, message, file: file, line: line)
        }
    }

    private func snapshot(
        year: Int = 2026,
        source: String = HolidayDefaults.source,
        fetchedAt: String = "2026-01-05T08:00:00+08:00",
        items: [HolidayItem]? = nil
    ) -> HolidaysSnapshot {
        HolidaysSnapshot(
            year: year,
            source: source,
            fetchedAt: fetchedAt,
            items: items ?? [HolidayItem(date: "2026-01-01", name: "测试", type: "holiday")]
        )
    }

    private var validRoot: [String: Any] {
        [
            "year": 2026,
            "source": HolidayDefaults.source,
            "fetched_at": "2026-01-05T08:00:00+08:00",
            "items": [validItemRoot]
        ]
    }

    private var validItemRoot: [String: Any] {
        ["date": "2026-01-01", "name": "测试", "type": "holiday"]
    }

    private func makeStore() throws -> (FileHolidayStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (FileHolidayStore(directoryURL: directory), directory)
    }

    private func cacheURL(in directory: URL, year: Int) -> URL {
        directory.appendingPathComponent("holidays_\(year).json", isDirectory: false)
    }

    private func writeCache(_ object: Any, to directory: URL, requestedYear: Int) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: cacheURL(in: directory, year: requestedYear), options: .atomic)
    }

    private func assertSaveRejects(
        _ snapshot: HolidaysSnapshot,
        store: FileHolidayStore,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertError(
            message: message,
            file: file,
            line: line,
            expression: { try store.save(snapshot) }
        )
    }

    private func assertError<T>(
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        expression: () throws -> T
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error.localizedDescription, message, file: file, line: line)
        }
    }
}
