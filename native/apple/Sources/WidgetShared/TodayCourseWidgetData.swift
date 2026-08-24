import Foundation

enum TodayCourseWidgetData {
    static let appGroupIdentifier = "group.com.nemoyu.wheretostudy.native"
    static let languageDefaultsKey = "appLanguage"
    static let archiveFileName = "widget-schedule.json"
    static let preferencesFileName = "widget-preferences.json"
    static let emptyMessage = "今日无课"
    static let maximumCourseLimit = 6

    enum Language: String, Equatable, Sendable {
        case simplifiedChinese = "zh-Hans"
        case english = "en"

        static func resolve(
            rawValue: String?,
            preferredLanguages: [String] = Locale.preferredLanguages
        ) -> Language {
            if rawValue == simplifiedChinese.rawValue { return .simplifiedChinese }
            if rawValue == english.rawValue { return .english }
            return preferredLanguages.first?.lowercased().hasPrefix("zh") == true
                ? .simplifiedChinese
                : .english
        }

        func text(chinese: String, english: String) -> String {
            self == .english ? english : chinese
        }
    }

    static func saveLanguage(rawValue: String) {
        UserDefaults(suiteName: appGroupIdentifier)?.set(rawValue, forKey: languageDefaultsKey)
    }

    static func loadLanguage(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Language {
        Language.resolve(
            rawValue: UserDefaults(suiteName: appGroupIdentifier)?.string(
                forKey: languageDefaultsKey
            ),
            preferredLanguages: preferredLanguages
        )
    }

    static func emptyMessage(language: Language) -> String {
        language.text(chinese: emptyMessage, english: "No classes today")
    }

    struct Preferences: Codable, Equatable, Sendable {
        let showsLocation: Bool
        let showsTeacher: Bool
        let courseLimit: Int

        static let `default` = Preferences(
            showsLocation: true,
            showsTeacher: true,
            courseLimit: 4
        )

        init(showsLocation: Bool, showsTeacher: Bool = true, courseLimit: Int) {
            self.showsLocation = showsLocation
            self.showsTeacher = showsTeacher
            self.courseLimit = courseLimit
        }

        var normalized: Preferences {
            Preferences(
                showsLocation: showsLocation,
                showsTeacher: showsTeacher,
                courseLimit: min(max(courseLimit, 1), maximumCourseLimit)
            )
        }

        private enum CodingKeys: String, CodingKey {
            case showsLocation
            case showsTeacher
            case courseLimit
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            showsLocation = try container.decodeIfPresent(Bool.self, forKey: .showsLocation) ?? true
            showsTeacher = try container.decodeIfPresent(Bool.self, forKey: .showsTeacher) ?? true
            courseLimit = try container.decodeIfPresent(Int.self, forKey: .courseLimit)
                ?? Self.default.courseLimit
        }
    }

    struct Archive: Codable, Equatable, Sendable {
        let termStartDate: String
        let fetchedAt: String
        let courses: [Course]
    }

    struct Course: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let teacher: String?
        let room: String
        let timeRange: String
        let sectionText: String?
        let weekday: Int
        let weekNumbers: [Int]
        let startSlot: Int
        let endSlot: Int?

        init(
            id: String,
            name: String,
            teacher: String? = nil,
            room: String,
            timeRange: String,
            sectionText: String? = nil,
            weekday: Int,
            weekNumbers: [Int],
            startSlot: Int,
            endSlot: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.teacher = teacher
            self.room = room
            self.timeRange = timeRange
            self.sectionText = sectionText
            self.weekday = weekday
            self.weekNumbers = weekNumbers
            self.startSlot = startSlot
            self.endSlot = endSlot
        }
    }

    enum CoursePhase: Equatable, Sendable {
        case upcoming
        case inProgress
        case finished

        var badgeText: String {
            badgeText(language: .simplifiedChinese)
        }

        func badgeText(language: Language) -> String {
            switch self {
            case .upcoming: language.text(chinese: "下一节", english: "Next")
            case .inProgress: language.text(chinese: "进行中", english: "Now")
            case .finished: language.text(chinese: "已结束", english: "Finished")
            }
        }
    }

    static func save(schedule: ScheduleSnapshot) throws {
        let archive = Archive(
            termStartDate: schedule.termStartDate,
            fetchedAt: schedule.fetchedAt,
            courses: schedule.courses.map {
                Course(
                    id: $0.id,
                    name: $0.name,
                    teacher: $0.teacher,
                    room: $0.room,
                    timeRange: $0.timeRange,
                    sectionText: $0.sectionText,
                    weekday: $0.weekday,
                    weekNumbers: $0.weekNumbers,
                    startSlot: $0.startSlot,
                    endSlot: $0.endSlot
                )
            }
        )
        let data = try JSONEncoder().encode(archive)
        var saved = false
        var lastError: Error?
        for fileURL in writableFileURLs(named: archiveFileName) {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: .atomic)
                saved = true
            } catch {
                lastError = error
            }
        }
        if !saved, let lastError { throw lastError }
    }

    static func load() -> Archive? {
        for fileURL in readableFileURLs(named: archiveFileName) {
            guard
                let data = try? Data(contentsOf: fileURL),
                !data.isEmpty,
                let archive = try? JSONDecoder().decode(Archive.self, from: data)
            else { continue }
            return archive
        }
        return nil
    }

    static func clear() {
        for fileURL in writableFileURLs(named: archiveFileName)
        where FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    static func save(preferences: Preferences) throws {
        let data = try JSONEncoder().encode(preferences.normalized)
        var saved = false
        var lastError: Error?
        for fileURL in writableFileURLs(named: preferencesFileName) {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: .atomic)
                saved = true
            } catch {
                lastError = error
            }
        }
        if !saved, let lastError { throw lastError }
    }

    static func loadPreferences() -> Preferences {
        for fileURL in readableFileURLs(named: preferencesFileName) {
            guard
                let data = try? Data(contentsOf: fileURL),
                !data.isEmpty,
                let preferences = try? JSONDecoder().decode(Preferences.self, from: data)
            else { continue }
            return preferences.normalized
        }
        return .default
    }

    static func courses(on date: Date, archive: Archive?, calendar: Calendar = .shanghai) -> [Course] {
        guard
            let archive,
            let termStart = StrictContractDateParser.date(from: archive.termStartDate, calendar: calendar)
        else { return [] }
        let week = ScheduleLogic.weekNumber(on: date, termStart: termStart, calendar: calendar)
        let weekday = ((calendar.component(.weekday, from: date) + 5) % 7) + 1
        return archive.courses
            .filter { $0.weekday == weekday && $0.weekNumbers.contains(week) }
            .sorted { lhs, rhs in
                lhs.startSlot == rhs.startSlot ? lhs.name < rhs.name : lhs.startSlot < rhs.startSlot
            }
    }

    static func weekNumber(
        on date: Date,
        archive: Archive?,
        calendar: Calendar = .shanghai
    ) -> Int? {
        guard
            let archive,
            let termStart = StrictContractDateParser.date(from: archive.termStartDate, calendar: calendar)
        else { return nil }
        let week = ScheduleLogic.weekNumber(on: date, termStart: termStart, calendar: calendar)
        guard let lastTeachingWeek = archive.courses.flatMap(\.weekNumbers).max(),
              lastTeachingWeek > 0
        else { return nil }
        return (1 ... lastTeachingWeek).contains(week) ? week : nil
    }

    static func dayContext(
        on date: Date,
        weekNumber: Int?,
        language: Language = .simplifiedChinese,
        calendar: Calendar = .shanghai,
        compact: Bool = false
    ) -> String {
        if language == .english {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MMM d · EEE"
            var values = [formatter.string(from: date)]
            values.append(compact
                ? "Cal W\(ScheduleLogic.civilWeekNumber(on: date, calendar: calendar))"
                : "Calendar Week \(ScheduleLogic.civilWeekNumber(on: date, calendar: calendar))")
            if let weekNumber, weekNumber > 0 {
                values.append(compact ? "Teach W\(weekNumber)" : "Teaching Week \(weekNumber)")
            } else {
                values.append(compact ? "Outside term" : "Outside teaching weeks")
            }
            return values.joined(separator: " · ")
        }
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let weekdayIndex = ((calendar.component(.weekday, from: date) + 5) % 7)
        let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        var values = [
            "\(month)月\(day)日",
            weekdays[weekdayIndex],
            compact
                ? "公历\(ScheduleLogic.civilWeekNumber(on: date, calendar: calendar))周"
                : "公历第\(ScheduleLogic.civilWeekNumber(on: date, calendar: calendar))周"
        ]
        if let weekNumber, weekNumber > 0 {
            values.append(compact ? "教学\(weekNumber)周" : "第\(weekNumber)教学周")
        } else {
            values.append("非教学周")
        }
        return values.joined(separator: " · ")
    }

    static func coursePhase(
        _ course: Course,
        at date: Date,
        calendar: Calendar = .shanghai
    ) -> CoursePhase? {
        guard let range = minuteRange(for: course) else { return nil }
        let minute = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        if minute < range.lowerBound { return .upcoming }
        if minute <= range.upperBound { return .inProgress }
        return .finished
    }

    static func highlightedCourseID(
        in courses: [Course],
        at date: Date,
        calendar: Calendar = .shanghai
    ) -> String? {
        courses.first { coursePhase($0, at: date, calendar: calendar) == .inProgress }?.id
            ?? courses.first { coursePhase($0, at: date, calendar: calendar) == .upcoming }?.id
    }

    static func statusSummary(
        for courses: [Course],
        at date: Date,
        language: Language = .simplifiedChinese,
        calendar: Calendar = .shanghai
    ) -> String {
        guard !courses.isEmpty else { return emptyMessage(language: language) }
        if let course = courses.first(where: {
            coursePhase($0, at: date, calendar: calendar) == .inProgress
        }) {
            let end = timeParts(course.timeRange)?.end ?? ""
            return end.isEmpty
                ? language.text(chinese: "课程进行中", english: "Class in progress")
                : language.text(chinese: "进行中 · \(end) 下课", english: "Now · ends \(end)")
        }
        if let course = courses.first(where: {
            coursePhase($0, at: date, calendar: calendar) == .upcoming
        }) {
            let start = timeParts(course.timeRange)?.start ?? ""
            return start.isEmpty
                ? language.text(chinese: "还有待上课程", english: "Classes remaining")
                : language.text(chinese: "下一节 · \(start)", english: "Next · \(start)")
        }
        return language.text(chinese: "今日课程已结束", english: "Today's classes are finished")
    }

    static func timelineDates(
        after date: Date,
        archive: Archive?,
        calendar: Calendar = .shanghai
    ) -> [Date] {
        let midnight = nextMidnight(after: date, calendar: calendar)
        var dates = [date, midnight]
        for course in courses(on: date, archive: archive, calendar: calendar) {
            guard let range = minuteRange(for: course) else { continue }
            for minute in [range.lowerBound, range.upperBound + 1] {
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                components.hour = minute / 60
                components.minute = minute % 60
                components.second = 0
                if let boundary = calendar.date(from: components), boundary > date, boundary < midnight {
                    dates.append(boundary)
                }
            }
        }
        return Array(Set(dates)).sorted()
    }

    static func previewCourses() -> [Course] {
        [
            Course(
                id: "widget-preview-calculus",
                name: "高等数学",
                teacher: "示例教师",
                room: "教2-101",
                timeRange: "08:00-09:35",
                sectionText: "1-2节",
                weekday: 1,
                weekNumbers: [8],
                startSlot: 0,
                endSlot: 1
            ),
            Course(
                id: "widget-preview-data-mining",
                name: "数据挖掘",
                teacher: "示例教师",
                room: "教3-335",
                timeRange: "09:50-12:15",
                sectionText: "3-5节",
                weekday: 1,
                weekNumbers: [8],
                startSlot: 2,
                endSlot: 4
            ),
            Course(
                id: "widget-preview-network",
                name: "计算机网络",
                teacher: "示例教师",
                room: "教4-201",
                timeRange: "13:00-14:35",
                sectionText: "6-7节",
                weekday: 1,
                weekNumbers: [8],
                startSlot: 5,
                endSlot: 6
            ),
            Course(
                id: "widget-preview-neural-network",
                name: "神经网络与深度学习",
                teacher: "示例教师",
                room: "教3-539",
                timeRange: "14:45-16:25",
                sectionText: "8-9节",
                weekday: 1,
                weekNumbers: [8],
                startSlot: 7,
                endSlot: 8
            ),
            Course(
                id: "widget-preview-sports",
                name: "体育",
                teacher: "示例教师",
                room: "体育馆",
                timeRange: "16:35-18:10",
                sectionText: "10-11节",
                weekday: 1,
                weekNumbers: [8],
                startSlot: 9,
                endSlot: 10
            ),
            Course(
                id: "widget-preview-english",
                name: "学术英语",
                teacher: "示例教师",
                room: "主楼-201",
                timeRange: "18:30-20:05",
                sectionText: "12-13节",
                weekday: 1,
                weekNumbers: [8],
                startSlot: 11,
                endSlot: 12
            )
        ]
    }

    static func nextMidnight(after date: Date, calendar: Calendar = .shanghai) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date.addingTimeInterval(24 * 60 * 60)
    }

    private static func minuteRange(for course: Course) -> ClosedRange<Int>? {
        guard let parts = timeParts(course.timeRange) else { return nil }
        guard let start = minutes(parts.start), let end = minutes(parts.end), end >= start else {
            return nil
        }
        return start ... end
    }

    private static func timeParts(_ value: String) -> (start: String, end: String)? {
        let normalized = value
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        let parts = normalized.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private static func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":", maxSplits: 1).compactMap { Int($0) }
        guard parts.count == 2, (0 ... 23).contains(parts[0]), (0 ... 59).contains(parts[1]) else {
            return nil
        }
        return parts[0] * 60 + parts[1]
    }

    private static func readableFileURLs(named fileName: String) -> [URL] {
        writableFileURLs(named: fileName).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func writableFileURLs(named fileName: String) -> [URL] {
        var fileURLs = [URL]()
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            fileURLs.append(groupURL.appendingPathComponent(fileName, isDirectory: false))
        }

        #if !APP_STORE_BUILD
        // Ad-hoc local packages have no registered App Group container. Keep a
        // compatibility copy inside Application Support for preview builds.
        if let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            fileURLs.append(supportDirectory
                .appendingPathComponent("WhereToStudyNative", isDirectory: true)
                .appendingPathComponent(fileName, isDirectory: false))
        }
        #endif
        return fileURLs
    }
}
