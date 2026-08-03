import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case planner
    case calendar
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planner: "空教室"
        case .calendar: "教学日历"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .planner: "house"
        case .calendar: "calendar"
        case .settings: "gearshape"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .planner
    @Published var account = ""
    @Published var password = ""
    @Published var termID: String
    @Published var termStartDate: String
    @Published var campusID: String
    @Published var selectedSlots = Set(SlotMetadata.defaults.indices)
    @Published var selectedBuildings = Set<String>()
    @Published var usePersonalSchedule = true
    @Published var schedule: ScheduleSnapshot?
    @Published var classroomsCache: ClassroomsCache?
    @Published private(set) var holidaysByYear = [Int: HolidaysSnapshot]()
    @Published var statusMessage = ""
    @Published var classroomStatusMessage = ""
    @Published var calendarImportStatusMessage = ""
    @Published var isRefreshingSchedule = false
    @Published var isRefreshingClassrooms = false
    @Published var isImportingCalendar = false
    @Published private(set) var holidayStatusByYear = [Int: String]()

    let slots = SlotMetadata.defaults
    private let credentialStore: any CredentialStoring
    private let scheduleStore: any ScheduleStoring
    private let scheduleClient: any ScheduleFetching
    private let classroomStore: any ClassroomStoring
    private let classroomClient: any ClassroomFetching
    private let holidayStore: any HolidayStoring
    private let holidayClient: any HolidayFetching
    private let calendarImporter: any CalendarImporting
    private let defaults: UserDefaults
    private var holidayLoads = Set<Int>()
    private var localDataGeneration = 0
    private var dailyClassroomRefreshTask: Task<Void, Never>?

    init(
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        scheduleStore: any ScheduleStoring = FileScheduleStore(),
        scheduleClient: any ScheduleFetching = SJDScheduleClient(),
        classroomStore: any ClassroomStoring = FileClassroomStore(),
        classroomClient: any ClassroomFetching = SJDClassroomClient(),
        holidayStore: any HolidayStoring = FileHolidayStore(),
        holidayClient: any HolidayFetching = HolidayClient(),
        calendarImporter: any CalendarImporting = EventKitCalendarImporter(),
        defaults: UserDefaults = .standard
    ) {
        self.credentialStore = credentialStore
        self.scheduleStore = scheduleStore
        self.scheduleClient = scheduleClient
        self.classroomStore = classroomStore
        self.classroomClient = classroomClient
        self.holidayStore = holidayStore
        self.holidayClient = holidayClient
        self.calendarImporter = calendarImporter
        self.defaults = defaults
        termID = defaults.string(forKey: "termID") ?? ScheduleDefaults.termID
        termStartDate = defaults.string(forKey: "termStartDate") ?? ScheduleDefaults.termStartDate
        campusID = defaults.string(forKey: "campusID") ?? "01"
        loadCredentials()
        loadSchedule()
        loadClassrooms()
        synchronizeSelectedSlots()
        ensureHolidays(for: Calendar.shanghai.component(.year, from: .now))
    }

    var selectedCampusName: String {
        campusID == "04" ? "沙河" : "西土城"
    }

    var todayCourses: [Course] {
        courses(on: .now)
    }

    var tomorrowCourses: [Course] {
        guard let tomorrow = Calendar.shanghai.date(byAdding: .day, value: 1, to: .now) else { return [] }
        return courses(on: tomorrow)
    }

    func courses(on date: Date) -> [Course] {
        guard
            let schedule,
            let termStart = Self.dateFormatter.date(from: schedule.termStartDate)
        else { return [] }
        return ScheduleLogic.courses(on: date, termStart: termStart, courses: schedule.courses)
    }

    func weekNumber(on date: Date) -> Int? {
        guard
            let schedule,
            let termStart = Self.dateFormatter.date(from: schedule.termStartDate)
        else { return nil }
        return ScheduleLogic.weekNumber(on: date, termStart: termStart)
    }

    var personalBusySlots: Set<Int> {
        guard
            let schedule,
            let termStart = Self.dateFormatter.date(from: schedule.termStartDate)
        else { return [] }
        return ScheduleLogic.busySlots(on: .now, termStart: termStart, courses: schedule.courses)
    }

    var campusRooms: [Classroom] {
        classroomsCache?.campuses.first(where: { $0.campusID == campusID })?.rooms ?? []
    }

    var campusBuildings: [String] {
        Array(Set(campusRooms.map(\.building))).sorted()
    }

    var matchingRooms: [Classroom] {
        guard !selectedBuildings.isEmpty, !selectedSlots.isEmpty else { return [] }
        return campusRooms.filter { room in
            selectedBuildings.contains(room.building)
                && selectedSlots.allSatisfy(room.availableSlots.contains)
        }.sorted { ($0.building, $0.room) < ($1.building, $1.room) }
    }

    func toggleSlot(_ slot: Int) {
        guard !(usePersonalSchedule && personalBusySlots.contains(slot)) else { return }
        if selectedSlots.contains(slot) {
            selectedSlots.remove(slot)
        } else {
            selectedSlots.insert(slot)
        }
    }

    func setUsePersonalSchedule(_ enabled: Bool) {
        usePersonalSchedule = enabled
        if enabled {
            selectedSlots.subtract(personalBusySlots)
        } else {
            selectedSlots.formUnion(personalBusySlots)
        }
    }

    func selectFreeSlots() {
        selectedSlots = Set(slots.indices)
        if usePersonalSchedule { selectedSlots.subtract(personalBusySlots) }
    }

    func clearSelectedSlots() {
        selectedSlots.removeAll()
    }

    func toggleBuilding(_ building: String) {
        if !selectedBuildings.insert(building).inserted {
            selectedBuildings.remove(building)
        }
    }

    func selectCampus(_ id: String) {
        guard campusID != id else { return }
        campusID = id
        defaults.set(id, forKey: "campusID")
        selectedBuildings.removeAll()
    }

    func saveSettings() {
        do {
            try credentialStore.save(.init(account: account.trimmingCharacters(in: .whitespacesAndNewlines), password: password))
            termID = termID.trimmingCharacters(in: .whitespacesAndNewlines)
            termStartDate = termStartDate.trimmingCharacters(in: .whitespacesAndNewlines)
            if termID.isEmpty { termID = ScheduleDefaults.termID }
            if termStartDate.isEmpty { termStartDate = ScheduleDefaults.termStartDate }
            defaults.set(campusID, forKey: "campusID")
            defaults.set(termID, forKey: "termID")
            defaults.set(termStartDate, forKey: "termStartDate")
            statusMessage = "设置已保存"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearLocalData() {
        localDataGeneration &+= 1
        var failures = [String]()

        do {
            try credentialStore.clear()
            account = ""
            password = ""
        } catch {
            failures.append("账户密码")
        }

        do {
            try scheduleStore.clear()
            schedule = nil
            calendarImportStatusMessage = ""
        } catch {
            failures.append("个人课表")
        }

        do {
            try classroomStore.clear()
            classroomsCache = nil
            classroomStatusMessage = ""
        } catch {
            failures.append("空教室缓存")
        }

        do {
            try holidayStore.clear()
            holidaysByYear.removeAll()
            holidayStatusByYear.removeAll()
            holidayLoads.removeAll()
        } catch {
            failures.append("节假日缓存")
        }

        defaults.removeObject(forKey: "campusID")
        defaults.removeObject(forKey: "termID")
        defaults.removeObject(forKey: "termStartDate")
        campusID = "01"
        termID = ScheduleDefaults.termID
        termStartDate = ScheduleDefaults.termStartDate
        selectedBuildings.removeAll()
        usePersonalSchedule = true
        synchronizeSelectedSlots()

        statusMessage = failures.isEmpty
            ? "本地数据已清除"
            : "以下本地数据未能清除：\(failures.joined(separator: "、"))"
    }

    func refreshSchedule() {
        guard !isRefreshingSchedule else { return }
        isRefreshingSchedule = true
        statusMessage = "正在获取个人课表…"
        let credentials = Credentials(
            account: account.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        let fallbackTermID = termID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ScheduleDefaults.termID : termID.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTermStart = termStartDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ScheduleDefaults.termStartDate : termStartDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let generation = localDataGeneration

        Task {
            defer { isRefreshingSchedule = false }
            do {
                let fetched = try await scheduleClient.fetch(
                    credentials: credentials,
                    fallbackTermID: fallbackTermID,
                    fallbackTermStartDate: fallbackTermStart
                )
                guard generation == localDataGeneration else { return }
                try scheduleStore.save(fetched)
                schedule = fetched
                calendarImportStatusMessage = ""
                termID = fetched.termID
                termStartDate = fetched.termStartDate
                defaults.set(termID, forKey: "termID")
                defaults.set(termStartDate, forKey: "termStartDate")
                synchronizeSelectedSlots()
                statusMessage = "个人课表已更新，共 \(fetched.courses.count) 门课程"
            } catch {
                guard generation == localDataGeneration else { return }
                statusMessage = error.localizedDescription
            }
        }
    }

    func importScheduleToCalendar() {
        guard !isImportingCalendar else { return }
        guard let schedule else {
            calendarImportStatusMessage = CalendarImportError.noSchedule.localizedDescription
            return
        }
        isImportingCalendar = true
        calendarImportStatusMessage = "正在导入系统日历…"
        let generation = localDataGeneration

        Task {
            defer { isImportingCalendar = false }
            do {
                let result = try await calendarImporter.importSchedule(schedule)
                guard generation == localDataGeneration else { return }
                if result.total == 0 {
                    calendarImportStatusMessage = "课表中没有可导入的课程日期"
                } else {
                    calendarImportStatusMessage = "日历导入完成：新增 \(result.inserted)，更新 \(result.updated)，已存在 \(result.unchanged)"
                }
            } catch {
                guard generation == localDataGeneration else { return }
                calendarImportStatusMessage = error.localizedDescription
            }
        }
    }

    func refreshClassroomsIfNeeded() {
        guard classroomsCache?.targetDate != Self.todayString else { return }
        guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            classroomStatusMessage = "请先在设置中保存教务账号和密码"
            return
        }
        refreshClassrooms(force: false)
    }

    func refreshClassrooms(force: Bool = true) {
        guard !isRefreshingClassrooms else { return }
        if !force, classroomsCache?.targetDate == Self.todayString { return }
        isRefreshingClassrooms = true
        classroomStatusMessage = "正在获取当天空教室…"
        let credentials = Credentials(
            account: account.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        let targetDate = Self.todayString
        let generation = localDataGeneration

        Task {
            defer { isRefreshingClassrooms = false }
            do {
                let fetched = try await classroomClient.fetch(
                    credentials: credentials,
                    targetDate: targetDate
                )
                guard generation == localDataGeneration else { return }
                try classroomStore.save(fetched)
                classroomsCache = fetched
                selectedBuildings.formIntersection(Set(campusBuildings))
                classroomStatusMessage = "当天空教室已更新"
            } catch {
                guard generation == localDataGeneration else { return }
                classroomStatusMessage = error.localizedDescription
            }
        }
    }

    func startDailyClassroomRefresh() {
        guard dailyClassroomRefreshTask == nil else { return }
        dailyClassroomRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                let next = DailyRefreshLogic.nextRefresh(after: now)
                let delay = max(1, next.timeIntervalSince(now))
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                self.refreshClassrooms(force: true)
            }
        }
    }

    func holidayItems(for year: Int) -> [HolidayItem] {
        holidaysByYear[year]?.items ?? []
    }

    func ensureHolidays(for year: Int, force: Bool = false) {
        guard HolidayDefaults.supportedYears.contains(year) else { return }
        if holidaysByYear[year] == nil {
            do {
                holidaysByYear[year] = try holidayStore.load(year: year)
            } catch {
                holidayStatusByYear[year] = "本地节假日读取失败"
            }
        }
        if !force, let cached = holidaysByYear[year], Self.isFreshHolidaySnapshot(cached) {
            return
        }
        guard holidayLoads.insert(year).inserted else { return }
        let cached = holidaysByYear[year]
        let generation = localDataGeneration

        Task {
            defer { holidayLoads.remove(year) }
            do {
                let fetched = try await holidayClient.fetch(year: year)
                guard generation == localDataGeneration else { return }
                try holidayStore.save(fetched)
                holidaysByYear[year] = fetched
                holidayStatusByYear.removeValue(forKey: year)
            } catch {
                guard generation == localDataGeneration else { return }
                holidayStatusByYear[year] = cached == nil
                    ? "节假日数据暂不可用"
                    : "节假日更新失败，正在使用本地缓存"
            }
        }
    }

    private func loadCredentials() {
        do {
            guard let credentials = try credentialStore.load() else { return }
            account = credentials.account
            password = credentials.password
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadSchedule() {
        do {
            schedule = try scheduleStore.load()
            if let schedule {
                termID = schedule.termID
                termStartDate = schedule.termStartDate
            }
        } catch {
            statusMessage = "本地课表读取失败：\(error.localizedDescription)"
        }
    }

    private func loadClassrooms() {
        do {
            guard let cached = try classroomStore.load(), cached.targetDate == Self.todayString else {
                return
            }
            classroomsCache = cached
        } catch {
            classroomStatusMessage = "本地空教室读取失败：\(error.localizedDescription)"
        }
    }

    private func synchronizeSelectedSlots() {
        selectedSlots = Set(slots.indices)
        if usePersonalSchedule { selectedSlots.subtract(personalBusySlots) }
    }

    private static var todayString: String {
        dateFormatter.string(from: .now)
    }

    private static func isFreshHolidaySnapshot(_ snapshot: HolidaysSnapshot, now: Date = .now) -> Bool {
        guard let fetchedAt = ISO8601DateFormatter().date(from: snapshot.fetchedAt) else { return false }
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age <= HolidayDefaults.refreshInterval
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum DailyRefreshLogic {
    static func nextRefresh(
        after date: Date,
        hour: Int = 7,
        minute: Int = 0,
        calendar: Calendar = .shanghai
    ) -> Date {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let candidate = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: day.year,
            month: day.month,
            day: day.day,
            hour: hour,
            minute: minute
        )) ?? date.addingTimeInterval(60)
        if candidate > date { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate)
            ?? date.addingTimeInterval(24 * 60 * 60)
    }
}
