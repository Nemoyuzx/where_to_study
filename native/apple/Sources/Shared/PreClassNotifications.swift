import Foundation
import CoreFoundation
import CryptoKit

enum PreClassNotificationSettings {
    static let enabledKey = "preClassNotificationsEnabled"
    static let offsetsKey = "preClassNotificationOffsets"
    static let defaultOffsets = [10]
    static let maximumCount = 5

    static func isValid(_ offsets: [Int]) -> Bool {
        (1 ... maximumCount).contains(offsets.count)
            && offsets.allSatisfy { (1 ... 1440).contains($0) }
            && Set(offsets).count == offsets.count
    }

    static func parse(_ values: [String]) -> [Int]? {
        var offsets = [Int]()
        for value in values {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.utf8.allSatisfy({ (48 ... 57).contains($0) }),
                  let minutes = Int(text) else { return nil }
            offsets.append(minutes)
        }
        return isValid(offsets) ? offsets : nil
    }

    static func loadOffsets(defaults: UserDefaults) -> [Int] {
        guard let values = defaults.array(forKey: offsetsKey) else { return defaultOffsets }
        var offsets = [Int]()
        for raw in values {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  (1 ... 1440).contains(number.doubleValue),
                  number.doubleValue == Double(number.intValue) else { return defaultOffsets }
            offsets.append(number.intValue)
        }
        return isValid(offsets) ? offsets : defaultOffsets
    }
}

enum CourseNotificationCategory: Sendable {
    case dailySummary
    case preClass

    var identifierPrefix: String {
        switch self {
        case .dailySummary: DailyCourseNotificationPlanner.identifierPrefix
        case .preClass: PreClassNotificationPlanner.identifierPrefix
        }
    }

    static func owns(_ identifier: String) -> Bool {
        identifier.hasPrefix(dailySummary.identifierPrefix)
            || identifier.hasPrefix(preClass.identifierPrefix)
    }
}

enum PreClassNotificationPlanner {
    static let identifierPrefix = "pre-class-reminder."

    static func requests(
        for schedule: ScheduleSnapshot,
        after now: Date,
        offsets: [Int] = PreClassNotificationSettings.defaultOffsets,
        language: AppLanguage = .simplifiedChinese,
        calendar: Calendar = .shanghai
    ) -> [DailyCourseNotificationRequest] {
        guard PreClassNotificationSettings.isValid(offsets),
              let termStart = StrictContractDateParser.date(from: schedule.termStartDate, calendar: calendar)
        else { return [] }
        let today = calendar.startOfDay(for: now)
        var requests = [DailyCourseNotificationRequest]()
        var seen = Set<String>()
        // Include tomorrow even for a reminder up to 24 hours before a class;
        // compute one start per effective occurrence, never one per lesson slot.
        for dayOffset in 0 ... DailyCourseNotificationPlanner.maximumScanDayCount {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let date = StrictContractDateParser.string(from: day, calendar: calendar)
            let courses = ScheduleLogic.courses(on: day, termStart: termStart, courses: schedule.courses,
                                               exams: schedule.examSchedule, calendar: calendar)
            for course in courses {
                guard let interval = course.minuteInterval,
                      let start = calendar.date(byAdding: .minute, value: interval.lowerBound, to: day)
                else { continue }
                let sourceID = course.sourceCourseID?.trimmingCharacters(in: .whitespacesAndNewlines)
                let identity = sourceID.flatMap { $0.isEmpty ? nil : $0 } ?? course.id
                let occurrence = [schedule.termID, date, course.isExam ? "exam" : "course",
                                  identity, String(interval.lowerBound)].joined(separator: "\u{1F}")
                let digest = SHA256.hash(data: Data(occurrence.utf8)).map { String(format: "%02x", $0) }.joined()
                let clock = String(format: "%02d:%02d", interval.lowerBound / 60, interval.lowerBound % 60)
                for minutes in offsets {
                    let fireDate = start.addingTimeInterval(-Double(minutes) * 60)
                    let identifier = "\(identifierPrefix)\(digest).\(minutes)"
                    guard fireDate > now, seen.insert(identifier).inserted else { continue }
                    let titleKey = course.isExam ? "考试将在 %d 分钟后开始" : "课程将在 %d 分钟后开始"
                    let location = course.room.isEmpty ? "" : " · \(course.room)"
                    requests.append(DailyCourseNotificationRequest(
                        identifier: identifier, fireDate: fireDate,
                        title: String(format: AppLocalization.string(titleKey, language: language),
                                      locale: language.locale, minutes),
                        body: "\(date) \(clock) · \(course.name)\(location)"
                    ))
                }
            }
        }
        return CourseNotificationPlan.earliest(requests, after: now)
    }
}

enum CourseNotificationPlan {
    // Share the existing 63-slot budget across both categories, leaving the
    // same reserved system slot as before. Foreground reconciliation refills it.
    static func earliest(_ requests: [DailyCourseNotificationRequest], after now: Date) -> [DailyCourseNotificationRequest] {
        var identifiers = Set<String>()
        return Array(requests.filter { $0.fireDate > now }.sorted {
            ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier)
        }.filter { identifiers.insert($0.identifier).inserted }
            .prefix(DailyCourseNotificationPlanner.maximumPendingRequestCount))
    }
}
