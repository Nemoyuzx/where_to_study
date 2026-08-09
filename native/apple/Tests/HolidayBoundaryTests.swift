import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class HolidayBoundaryTests: XCTestCase {
    func testEmptyNameAndInvalidDateAreRejectedBeforeUnknownTypeIsSkipped() {
        assertParserRejects(
            source(dates: #"[{"date":"2026-01-01","name":"  ","type":"future-type"}]"#),
            message: "节假日名称不能为空。"
        )
        assertParserRejects(
            source(dates: #"[{"date":"invalid","name":"测试","type":"future-type"}]"#),
            message: "节假日数据日期格式不正确。"
        )
    }

    func testEmptyAndAllUnknownResponsesAreRejected() {
        assertParserRejects(
            source(dates: "[]"),
            message: "节假日数据没有可识别的法定节假日或调休记录。"
        )
        assertParserRejects(
            source(dates: #"[{"date":"2026-01-01","name":"测试","type":"future-type"}]"#),
            message: "节假日数据没有可识别的法定节假日或调休记录。"
        )
    }

    func testTransportMetadataUsesLicensedHTTPSSource() {
        XCTAssertEqual(
            HolidayDefaults.source,
            "https://unpkg.com/holiday-calendar@1.3.3/data/CN"
        )
    }

    func testRejectedRemotePayloadDoesNotReplaceValidCache() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cached = snapshot(
            source: "cached-source",
            fetchedAt: "2026-01-01T00:00:00Z",
            items: [HolidayItem(date: "2026-01-01", name: "缓存假期", type: "holiday")]
        )
        try store.save(cached)
        let originalData = try Data(contentsOf: cacheURL(in: directory, year: 2026))

        XCTAssertThrowsError(try parse(source(dates: "[]")))

        XCTAssertEqual(try store.load(year: 2026), cached)
        XCTAssertEqual(try Data(contentsOf: cacheURL(in: directory, year: 2026)), originalData)
    }

    func test2026OfflineFallbackMatchesContractAndRustDataset() throws {
        let fallback = try XCTUnwrap(HolidayOfflineFallback.snapshot(
            year: 2026,
            fetchedAt: "2026-01-05T08:00:00+08:00"
        ))

        XCTAssertEqual(fallback.year, 2026)
        XCTAssertEqual(
            fallback.source,
            "https://www.gov.cn/yaowen/liebiao/202511/content_7047099.htm"
        )
        XCTAssertEqual(fallback.items.count, 39)
        XCTAssertEqual(fallback.items.first, HolidayItem(
            date: "2026-01-01",
            name: "元旦",
            type: "holiday"
        ))
        XCTAssertTrue(fallback.items.contains(HolidayItem(
            date: "2026-02-28",
            name: "春节补班",
            type: "workday"
        )))
        XCTAssertTrue(fallback.items.contains(HolidayItem(
            date: "2026-10-07",
            name: "国庆节",
            type: "holiday"
        )))
        XCTAssertEqual(fallback.items.last, HolidayItem(
            date: "2026-10-10",
            name: "国庆节补班",
            type: "workday"
        ))

        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(fallback)
        XCTAssertEqual(try store.load(year: 2026), fallback)
        XCTAssertNil(HolidayOfflineFallback.snapshot(year: 2025))
        XCTAssertNil(HolidayOfflineFallback.snapshot(year: 2027))
    }

    func testMismatchedYearAndMalformedEnvelopeAreRejected() {
        assertParserRejects(
            #"{"year":2025,"region":"CN","dates":[]}"#,
            message: "节假日数据年份与请求不一致。"
        )
        assertParserRejects(
            #"{"year":2026,"region":"CN","dates":{}}"#,
            message: "节假日数据格式不正确。"
        )
        assertParserRejects(
            source(dates: #"[{"date":"2025-12-31","name":"跨年","type":"public_holiday"}]"#),
            message: "节假日数据包含其他年份的日期。"
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

    private func source(dates: String) -> String {
        #"{"year":2026,"region":"CN","dates":\#(dates)}"#
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
