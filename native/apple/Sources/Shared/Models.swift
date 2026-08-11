import Foundation

enum StrictContractDateParser {
    static func date(from value: String, calendar: Calendar = .shanghai) -> Date? {
        let bytes = Array(value.utf8)
        guard
            bytes.count == 10,
            bytes[4] == 0x2D,
            bytes[7] == 0x2D,
            [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy({ (0x30 ... 0x39).contains(bytes[$0]) })
        else { return nil }

        let year = number(in: bytes[0 ... 3])
        let month = number(in: bytes[5 ... 6])
        let day = number(in: bytes[8 ... 9])
        guard year > 0 else { return nil }

        let components = DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else {
            return nil
        }
        return date
    }

    static func string(from date: Date, calendar: Calendar = .shanghai) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func number(in bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { $0 * 10 + Int($1 - 0x30) }
    }
}

struct SlotMetadata: Codable, Identifiable, Equatable, Sendable {
    let index: Int
    let label: String
    let start: String
    let end: String

    var id: Int { index }

    static let defaults: [SlotMetadata] = [
        .init(index: 0, label: "1", start: "08:00", end: "08:45"),
        .init(index: 1, label: "2", start: "08:50", end: "09:35"),
        .init(index: 2, label: "3", start: "09:50", end: "10:35"),
        .init(index: 3, label: "4", start: "10:40", end: "11:25"),
        .init(index: 4, label: "5", start: "11:30", end: "12:15"),
        .init(index: 5, label: "6", start: "13:00", end: "13:45"),
        .init(index: 6, label: "7", start: "13:50", end: "14:35"),
        .init(index: 7, label: "8", start: "14:45", end: "15:30"),
        .init(index: 8, label: "9", start: "15:40", end: "16:25"),
        .init(index: 9, label: "10", start: "16:35", end: "17:20"),
        .init(index: 10, label: "11", start: "17:25", end: "18:10"),
        .init(index: 11, label: "12", start: "18:30", end: "19:15"),
        .init(index: 12, label: "13", start: "19:20", end: "20:05"),
        .init(index: 13, label: "14", start: "20:10", end: "20:55")
    ]
}

struct Course: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let teacher: String
    let room: String
    let weekText: String
    let weekNumbers: [Int]
    let examWeekNumbers: [Int]
    let weekday: Int
    let startSlot: Int
    let endSlot: Int
    let sectionText: String
    let timeRange: String

    enum CodingKeys: String, CodingKey {
        case id, name, teacher, room, weekday
        case weekText = "week_text"
        case weekNumbers = "week_numbers"
        case examWeekNumbers = "exam_week_numbers"
        case startSlot = "start_slot"
        case endSlot = "end_slot"
        case sectionText = "section_text"
        case timeRange = "time_range"
    }
}

struct ScheduleSnapshot: Codable, Equatable, Sendable {
    let termID: String
    let termStartDate: String
    let fetchedAt: String
    let courses: [Course]

    enum CodingKeys: String, CodingKey {
        case courses
        case termID = "term_id"
        case termStartDate = "term_start_date"
        case fetchedAt = "fetched_at"
    }
}

enum ScheduleDefaults {
    static let termID = "2025-2026-2"
    static let termStartDate = "2026-03-02"
}

struct Classroom: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let building: String
    let room: String
    let name: String
    let size: Int?
    let type: String
    let availableSlots: [Int]
    let source: String

    enum CodingKeys: String, CodingKey {
        case id, building, room, name, size, type, source
        case availableSlots = "available_slots"
    }
}

struct CampusClassrooms: Codable, Equatable, Sendable {
    let campusID: String
    let campusName: String
    let targetDate: String
    let fetchedAt: String
    let realtime: Bool
    let provider: String
    let rooms: [Classroom]

    enum CodingKeys: String, CodingKey {
        case realtime, provider, rooms
        case campusID = "campus_id"
        case campusName = "campus_name"
        case targetDate = "target_date"
        case fetchedAt = "fetched_at"
    }
}

struct ClassroomsCache: Codable, Equatable, Sendable {
    let cacheVersion: Int
    let targetDate: String
    let fetchedAt: String
    let realtime: Bool
    let provider: String
    let campuses: [CampusClassrooms]

    enum CodingKeys: String, CodingKey {
        case realtime, provider, campuses
        case cacheVersion = "cache_version"
        case targetDate = "target_date"
        case fetchedAt = "fetched_at"
    }
}

struct HolidayItem: Codable, Identifiable, Equatable, Sendable {
    let date: String
    let name: String
    let type: String

    var id: String { "\(date)|\(type)|\(name)" }
}

struct HolidaysSnapshot: Codable, Equatable, Sendable {
    let year: Int
    let source: String
    let fetchedAt: String
    let items: [HolidayItem]

    enum CodingKeys: String, CodingKey {
        case year, source, items
        case fetchedAt = "fetched_at"
    }
}

enum HolidayDefaults {
    static let source = "https://unpkg.com/holiday-calendar@1.3.3/data/CN"
    static let supportedYears = 1900 ... 2100
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
}

enum ClassroomDefaults {
    static let cacheVersion = 2
    static let campuses = [
        (id: "01", name: "西土城"),
        (id: "04", name: "沙河")
    ]
}

enum ScheduleLogic {
    static func examWeeks(in courses: [Course]) -> Set<Int> {
        let weeks = Array(Set(courses.flatMap(\.weekNumbers).filter { $0 > 0 })).sorted()
        return Set([weeks[safe: 16], weeks[safe: 17]].compactMap { $0 })
    }

    static func weekNumber(on date: Date, termStart: Date, calendar: Calendar = .shanghai) -> Int {
        let start = calendar.startOfDay(for: termStart)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        guard days >= 0 else { return 0 }
        return days / 7 + 1
    }

    static func applyingExamWeeks(to courses: [Course]) -> [Course] {
        let examWeeks = examWeeks(in: courses)
        return courses.map { course in
            Course(
                id: course.id,
                name: course.name,
                teacher: course.teacher,
                room: course.room,
                weekText: course.weekText,
                weekNumbers: course.weekNumbers,
                examWeekNumbers: course.weekNumbers.filter(examWeeks.contains),
                weekday: course.weekday,
                startSlot: course.startSlot,
                endSlot: course.endSlot,
                sectionText: course.sectionText,
                timeRange: course.timeRange
            )
        }
    }

    static func courses(
        on date: Date,
        termStart: Date,
        courses: [Course],
        calendar: Calendar = .shanghai
    ) -> [Course] {
        let week = weekNumber(on: date, termStart: termStart, calendar: calendar)
        let weekday = ((calendar.component(.weekday, from: date) + 5) % 7) + 1
        return courses
            .filter { $0.weekday == weekday && $0.weekNumbers.contains(week) }
            .sorted { lhs, rhs in
                lhs.startSlot == rhs.startSlot ? lhs.name < rhs.name : lhs.startSlot < rhs.startSlot
            }
    }

    static func busySlots(
        on date: Date,
        termStart: Date,
        courses: [Course],
        calendar: Calendar = .shanghai
    ) -> Set<Int> {
        Set(self.courses(on: date, termStart: termStart, courses: courses, calendar: calendar)
            .flatMap { $0.startSlot ... $0.endSlot }
            .filter { SlotMetadata.defaults.indices.contains($0) })
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Calendar {
    static var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }
}
