import EventKit
import Foundation

// Reads China statutory holidays from the device's OS-provided holiday
// calendar. It is a read-only source that never prompts for permission: it
// only proceeds when calendar access was already granted (for example by the
// schedule-import feature). The system calendar marks rest days but does not
// reliably list makeup-workday adjustments, so the caller merges those from
// the remote/offline source (see AppModel.fetchHolidaySnapshot).

enum DeviceCalendarHolidayLogic {
    static let sourceLabel = "device-calendar"

    static func isHolidayCalendar(_ calendar: EKCalendar) -> Bool {
        let title = calendar.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if holidayCalendarTitles.contains(where: { title.localizedCaseInsensitiveContains($0) }) {
            return true
        }
        return calendar.type == .subscription
            && (title.contains("节假日") || title.localizedCaseInsensitiveContains("holiday"))
    }

    static func item(from event: EKEvent, year: Int, calendar: Calendar = .shanghai) -> HolidayItem? {
        guard let name = normalizedName(event.title) else { return nil }
        guard let date = dateString(event.startDate, year: year, calendar: calendar) else { return nil }
        return HolidayItem(date: date, name: name, type: kind(from: event.title))
    }

    static func normalizedName(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(HolidaySourceLimits.maximumNameLength))
    }

    static func kind(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["补班", "调休", "上班"].contains(where: trimmed.contains) {
            return "workday"
        }
        return "holiday"
    }

    static func dateString(_ date: Date, year: Int, calendar: Calendar = .shanghai) -> String? {
        guard calendar.component(.year, from: date) == year else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: Date())
    }

    static func mergingWorkdays(into snapshot: HolidaysSnapshot, workdays: [HolidayItem]) -> HolidaysSnapshot {
        var existingIDs = Set(snapshot.items.map(\.id))
        var additions: [HolidayItem] = []
        for workday in workdays where workday.type == "workday" && !existingIDs.contains(workday.id) {
            existingIDs.insert(workday.id)
            additions.append(workday)
        }
        guard !additions.isEmpty else { return snapshot }
        return HolidaysSnapshot(
            year: snapshot.year,
            source: snapshot.source,
            fetchedAt: snapshot.fetchedAt,
            items: (snapshot.items + additions).sorted {
                ($0.date, $0.type, $0.name) < ($1.date, $1.type, $1.name)
            }
        )
    }

    private static let holidayCalendarTitles = [
        "中国大陆节假日",
        "中国节假日",
        "中国法定节假日",
        "中国大陆法定节假日",
        "Chinese Holidays",
        "China Holidays",
        "Holidays in China",
    ]
}

struct DeviceCalendarHolidayClient: HolidayFetching {
    func fetch(year: Int) async throws -> HolidaysSnapshot {
        guard HolidayDefaults.supportedYears.contains(year) else {
            throw HolidayClientError.service("节假日年份不在支持范围内。")
        }
        guard Self.isAuthorized() else {
            throw HolidayClientError.service("未获得系统日历访问权限。")
        }
        return try await Task.detached(priority: .userInitiated) {
            try Self.read(year: year)
        }.value
    }

    static func isAuthorized() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, iOS 17.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    private static func read(year: Int) throws -> HolidaysSnapshot {
        let store = EKEventStore()
        let calendars = store.calendars(for: .event)
            .filter(DeviceCalendarHolidayLogic.isHolidayCalendar)
        guard !calendars.isEmpty else {
            throw HolidayClientError.service("设备日历中未找到中国节假日日历。")
        }
        guard
            let start = Calendar.shanghai.date(from: DateComponents(year: year, month: 1, day: 1)),
            let end = Calendar.shanghai.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else {
            throw HolidayClientError.service("无法计算节假日年份范围。")
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
        let items = events.compactMap { event in
            DeviceCalendarHolidayLogic.item(from: event, year: year)
        }
        guard !items.isEmpty else {
            throw HolidayClientError.service("设备日历中该年份没有节假日记录。")
        }
        guard items.count <= HolidaySourceLimits.maximumExpandedItems else {
            throw HolidayClientError.service("设备日历节假日记录过多。")
        }
        return HolidaysSnapshot(
            year: year,
            source: DeviceCalendarHolidayLogic.sourceLabel,
            fetchedAt: DeviceCalendarHolidayLogic.timestamp(),
            items: items.sorted { ($0.date, $0.type, $0.name) < ($1.date, $1.type, $1.name) }
        )
    }
}
