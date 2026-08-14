import Foundation
#if os(macOS)
import WidgetKit
#endif

enum CredentialSettingsError: LocalizedError, Equatable {
    case accountRequired
    case passwordRequiredForChangedAccount
    case accountDataResetFailed
    case calendarImportInProgress
    case invalidTermStartDate

    var errorDescription: String? {
        switch self {
        case .accountRequired:
            "请输入教务账号。"
        case .passwordRequiredForChangedAccount:
            "更换教务账号时必须输入新密码。"
        case .accountDataResetFailed:
            "无法清除原账号的课表与空教室缓存，账号未更改。"
        case .calendarImportInProgress:
            "系统日历正在同步，请完成后再更换账号。"
        case .invalidTermStartDate:
            "第一周周一日期格式不正确，请使用 yyyy-MM-dd。"
        }
    }
}

enum CredentialSaveAction: Equatable {
    case preserve
    case replace(Credentials)
    case clear
}

enum CredentialSettingsLogic {
    static func saveAction(
        account inputAccount: String,
        password inputPassword: String,
        storedAccount: String?,
        hasStoredPassword: Bool
    ) throws -> CredentialSaveAction {
        let account = normalizedAccount(inputAccount)
        if account.isEmpty {
            guard inputPassword.isEmpty else { throw CredentialSettingsError.accountRequired }
            return .clear
        }
        if !inputPassword.isEmpty {
            return .replace(Credentials(account: account, password: inputPassword))
        }
        if hasStoredPassword, normalizedAccount(storedAccount ?? "") == account {
            return .preserve
        }
        throw CredentialSettingsError.passwordRequiredForChangedAccount
    }

    static func credentialsForRequest(
        account inputAccount: String,
        password inputPassword: String,
        storedCredentials: Credentials?
    ) throws -> Credentials {
        let action = try saveAction(
            account: inputAccount,
            password: inputPassword,
            storedAccount: storedCredentials?.account,
            hasStoredPassword: !(storedCredentials?.password.isEmpty ?? true)
        )
        switch action {
        case let .replace(credentials):
            return credentials
        case .preserve:
            guard let storedCredentials else {
                throw CredentialSettingsError.passwordRequiredForChangedAccount
            }
            return Credentials(
                account: normalizedAccount(inputAccount),
                password: storedCredentials.password
            )
        case .clear:
            throw CredentialSettingsError.accountRequired
        }
    }

    static func normalizedAccount(_ account: String) -> String {
        account.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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

    var accessibilityIdentifier: String {
        "navigation.\(rawValue)"
    }
}

struct HolidayLoadState {
    private var tokensByYear = [Int: UUID]()

    mutating func begin(year: Int) -> UUID? {
        guard tokensByYear[year] == nil else { return nil }
        let token = UUID()
        tokensByYear[year] = token
        return token
    }

    mutating func finish(year: Int, token: UUID) {
        guard tokensByYear[year] == token else { return }
        tokensByYear.removeValue(forKey: year)
    }

    mutating func reset() {
        tokensByYear.removeAll()
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .planner
    @Published var account = ""
    @Published var password = ""
    @Published private(set) var hasSavedPassword = false
    @Published var termID: String
    @Published var termStartDate: String
    @Published var campusID: String
    @Published private(set) var queryCampusID: String
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
    @Published private(set) var dailyCourseNotificationsEnabled = false
    @Published private(set) var dailyCourseNotificationStatusMessage = ""

    let slots = SlotMetadata.defaults
    @Published private(set) var runtimeMode: AppRuntimeMode
    private let credentialStore: any CredentialStoring
    private let scheduleStore: any ScheduleStoring
    private let scheduleClient: any ScheduleFetching
    private let classroomStore: any ClassroomStoring
    private let classroomClient: any ClassroomFetching
    private let holidayStore: any HolidayStoring
    private let holidayClient: any HolidayFetching
    private let calendarImporter: any CalendarImporting
    private let dailyCourseNotificationScheduler: any DailyCourseNotificationScheduling
    private let dailyCourseNotificationAuthorizationTimeout: Duration
    private let statusMessageAutoDismissDelay: Duration
    private let defaults: UserDefaults
    private let supportsRuntimeModeSwitching: Bool
    private var holidayLoads = HolidayLoadState()
    private var localDataGeneration = 0
    private var scheduleRefreshToken = 0
    private var classroomRefreshToken = 0
    private var calendarImportToken = 0
    private var dailyCourseNotificationRevision: UInt64 = 0
    private var dailyClassroomRefreshTask: Task<Void, Never>?
    private var statusMessageDismissTask: Task<Void, Never>?
    private var statusMessageRevision: UInt64 = 0
    private var savedCredentialAccount: String?

    init(
        runtimeMode: AppRuntimeMode = .live,
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        scheduleStore: any ScheduleStoring = FileScheduleStore(),
        scheduleClient: any ScheduleFetching = SJDScheduleClient(),
        classroomStore: any ClassroomStoring = FileClassroomStore(),
        classroomClient: any ClassroomFetching = SJDClassroomClient(),
        holidayStore: any HolidayStoring = FileHolidayStore(),
        holidayClient: any HolidayFetching = HolidayClient(),
        calendarImporter: any CalendarImporting = EventKitCalendarImporter(),
        dailyCourseNotificationScheduler: any DailyCourseNotificationScheduling = UserNotificationCourseScheduler(),
        dailyCourseNotificationAuthorizationTimeout: Duration = .seconds(8),
        statusMessageAutoDismissDelay: Duration = .seconds(4),
        defaults: UserDefaults = .standard
    ) {
        self.runtimeMode = runtimeMode
        supportsRuntimeModeSwitching = runtimeMode == .live
        self.credentialStore = credentialStore
        self.scheduleStore = scheduleStore
        self.scheduleClient = scheduleClient
        self.classroomStore = classroomStore
        self.classroomClient = classroomClient
        self.holidayStore = holidayStore
        self.holidayClient = holidayClient
        self.calendarImporter = calendarImporter
        self.dailyCourseNotificationScheduler = dailyCourseNotificationScheduler
        self.dailyCourseNotificationAuthorizationTimeout = dailyCourseNotificationAuthorizationTimeout
        self.statusMessageAutoDismissDelay = statusMessageAutoDismissDelay
        self.defaults = defaults
        termID = defaults.string(forKey: "termID") ?? ScheduleDefaults.termID
        termStartDate = defaults.string(forKey: "termStartDate") ?? ScheduleDefaults.termStartDate
        let savedCampusID = defaults.string(forKey: "campusID") ?? "01"
        campusID = savedCampusID
        queryCampusID = savedCampusID
        dailyCourseNotificationsEnabled = defaults.bool(forKey: Self.dailyCourseNotificationsKey)
        loadCredentials()
        loadSchedule()
        loadClassrooms()
        synchronizeSelectedSlots()
        ensureHolidays(for: Calendar.shanghai.component(.year, from: .now))
        // Always reconcile on a cold launch so a previously scheduled batch is
        // removed even when the persisted feature switch is already off.
        reconcileDailyCourseNotifications(requestPermissionIfNeeded: false)
    }

    var selectedCampusName: String {
        queryCampusID == "04" ? "沙河" : "西土城"
    }

    var isSampleMode: Bool {
        runtimeMode.isSample
    }

    var isReviewDemo: Bool {
        runtimeMode.isReviewDemo
    }

    var canExitSampleMode: Bool {
        isSampleMode && supportsRuntimeModeSwitching
    }

    var canEnterReviewDemo: Bool {
        supportsRuntimeModeSwitching && !isSampleMode && !isImportingCalendar
    }

    var canPreserveSavedPassword: Bool {
        hasSavedPassword
            && CredentialSettingsLogic.normalizedAccount(account)
                == CredentialSettingsLogic.normalizedAccount(savedCredentialAccount ?? "")
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
            let termStart = StrictContractDateParser.date(from: schedule.termStartDate)
        else { return [] }
        return ScheduleLogic.courses(on: date, termStart: termStart, courses: schedule.courses)
    }

    func weekNumber(on date: Date) -> Int? {
        guard
            let schedule,
            let termStart = StrictContractDateParser.date(from: schedule.termStartDate)
        else { return nil }
        return ScheduleLogic.weekNumber(on: date, termStart: termStart)
    }

    var personalBusySlots: Set<Int> {
        guard
            let schedule,
            let termStart = StrictContractDateParser.date(from: schedule.termStartDate)
        else { return [] }
        return ScheduleLogic.busySlots(on: .now, termStart: termStart, courses: schedule.courses)
    }

    var campusRooms: [Classroom] {
        classroomsCache?.campuses.first(where: { $0.campusID == queryCampusID })?.rooms ?? []
    }

    var campusBuildings: [String] {
        let configuredBuildings = ClassroomDefaults.buildings(for: queryCampusID)
        return configuredBuildings.isEmpty
            ? Array(Set(campusRooms.map(\.building))).sorted()
            : configuredBuildings
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

    func selectQueryCampus(_ id: String) {
        guard queryCampusID != id else { return }
        queryCampusID = id
        selectedBuildings.removeAll()
    }

    func enterReviewDemo() {
        guard canEnterReviewDemo else { return }
        invalidatePendingOperations()
        dailyCourseNotificationRevision &+= 1
        dailyClassroomRefreshTask?.cancel()
        dailyClassroomRefreshTask = nil
        runtimeMode = .sample(review: true)

        account = ""
        password = ""
        updateSavedCredentialState(nil)
        schedule = SampleData.schedule()
        classroomsCache = SampleData.classrooms()
        termID = schedule?.termID ?? "review-demo"
        termStartDate = schedule?.termStartDate ?? ScheduleDefaults.termStartDate
        campusID = "01"
        queryCampusID = "01"
        selectedBuildings.removeAll()
        usePersonalSchedule = true
        synchronizeSelectedSlots()
        holidaysByYear.removeAll()
        holidayStatusByYear.removeAll()
        holidayLoads.reset()
        let year = Calendar.shanghai.component(.year, from: .now)
        holidaysByYear[year] = SampleData.holidays(year: year)
        dailyCourseNotificationsEnabled = false
        statusMessage = "正在展示内置示例课表，未连接北邮服务"
        classroomStatusMessage = "正在展示内置示例空教室，未连接北邮服务"
        calendarImportStatusMessage = ""
        dailyCourseNotificationStatusMessage = ""
        synchronizeWidgetSchedule()
    }

    func exitReviewDemo() {
        guard canExitSampleMode else { return }
        invalidatePendingOperations()
        runtimeMode = .live

        account = ""
        password = ""
        schedule = nil
        classroomsCache = nil
        holidaysByYear.removeAll()
        holidayStatusByYear.removeAll()
        holidayLoads.reset()
        statusMessage = ""
        classroomStatusMessage = ""
        calendarImportStatusMessage = ""
        dailyCourseNotificationStatusMessage = ""
        termID = defaults.string(forKey: "termID") ?? ScheduleDefaults.termID
        termStartDate = defaults.string(forKey: "termStartDate") ?? ScheduleDefaults.termStartDate
        campusID = defaults.string(forKey: "campusID") ?? "01"
        queryCampusID = campusID
        dailyCourseNotificationsEnabled = defaults.bool(forKey: Self.dailyCourseNotificationsKey)
        selectedBuildings.removeAll()
        usePersonalSchedule = true
        loadCredentials()
        loadSchedule()
        loadClassrooms()
        synchronizeSelectedSlots()
        ensureHolidays(for: Calendar.shanghai.component(.year, from: .now))
        reconcileDailyCourseNotifications(requestPermissionIfNeeded: false)
        #if os(macOS)
        startDailyClassroomRefresh()
        #endif
    }

    @discardableResult
    func saveSettings() -> Bool {
        guard !isSampleMode else {
            statusMessage = "示例模式不会保存账户或设置"
            return false
        }
        do {
            let normalizedTermID = termID.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTermStartDate = termStartDate.trimmingCharacters(in: .whitespacesAndNewlines)
            let nextTermID = normalizedTermID.isEmpty ? ScheduleDefaults.termID : normalizedTermID
            let nextTermStartDate = normalizedTermStartDate.isEmpty
                ? ScheduleDefaults.termStartDate : normalizedTermStartDate
            guard StrictContractDateParser.date(from: nextTermStartDate) != nil else {
                throw CredentialSettingsError.invalidTermStartDate
            }

            let storedCredentials = try credentialStore.load()
            let credentialAction = try CredentialSettingsLogic.saveAction(
                account: account,
                password: password,
                storedAccount: storedCredentials?.account,
                hasStoredPassword: !(storedCredentials?.password.isEmpty ?? true)
            )
            let nextCredentialAccount: String? = switch credentialAction {
            case .preserve:
                storedCredentials?.account
            case let .replace(credentials):
                credentials.account
            case .clear:
                nil
            }
            let accountChanged = CredentialSettingsLogic.normalizedAccount(
                storedCredentials?.account ?? ""
            ) != CredentialSettingsLogic.normalizedAccount(nextCredentialAccount ?? "")
            if accountChanged {
                guard !isImportingCalendar else {
                    throw CredentialSettingsError.calendarImportInProgress
                }
                try clearAccountScopedData()
            }
            switch credentialAction {
            case .preserve:
                updateSavedCredentialState(storedCredentials)
            case let .replace(credentials):
                try credentialStore.save(credentials)
                updateSavedCredentialState(credentials)
            case .clear:
                try credentialStore.clear()
                updateSavedCredentialState(nil)
            }
            account = CredentialSettingsLogic.normalizedAccount(account)
            password = ""
            termID = nextTermID
            termStartDate = nextTermStartDate
            defaults.set(campusID, forKey: "campusID")
            defaults.set(termID, forKey: "termID")
            defaults.set(termStartDate, forKey: "termStartDate")
            statusMessage = "设置已保存"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func setDailyCourseNotificationsEnabled(_ enabled: Bool) {
        guard !isSampleMode else {
            if isReviewDemo {
                dailyCourseNotificationsEnabled = enabled
                dailyCourseNotificationStatusMessage = enabled
                    ? "示例模式已模拟开启每日课程摘要，未申请通知权限"
                    : "示例模式已模拟关闭每日课程摘要"
            } else {
                dailyCourseNotificationStatusMessage = "示例模式不会申请通知权限"
            }
            return
        }
        dailyCourseNotificationsEnabled = enabled
        if enabled {
            dailyCourseNotificationStatusMessage = "正在确认通知权限…"
            reconcileDailyCourseNotifications(requestPermissionIfNeeded: true)
        } else {
            defaults.set(false, forKey: Self.dailyCourseNotificationsKey)
            dailyCourseNotificationStatusMessage = "每日课程摘要已关闭"
            cancelDailyCourseNotifications()
        }
    }

    func refreshDailyCourseNotificationAuthorization() {
        reconcileDailyCourseNotifications(requestPermissionIfNeeded: false)
    }

    func clearLocalData() {
        guard !isSampleMode else {
            statusMessage = "示例模式不读写真实本地数据"
            return
        }
        invalidatePendingOperations()
        dailyCourseNotificationsEnabled = false
        defaults.removeObject(forKey: Self.dailyCourseNotificationsKey)
        dailyCourseNotificationStatusMessage = ""
        cancelDailyCourseNotifications()
        var failures = [String]()

        do {
            try credentialStore.clear()
        } catch {
            failures.append("账户密码")
        }
        account = ""
        password = ""
        updateSavedCredentialState(nil)

        do {
            try scheduleStore.clear()
            schedule = nil
            synchronizeWidgetSchedule()
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
            holidayLoads.reset()
        } catch {
            failures.append("节假日缓存")
        }

        defaults.removeObject(forKey: "campusID")
        defaults.removeObject(forKey: "termID")
        defaults.removeObject(forKey: "termStartDate")
        campusID = "01"
        queryCampusID = "01"
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
        guard !isSampleMode else {
            statusMessage = "正在展示内置示例课表，未连接北邮服务"
            return
        }
        guard !isRefreshingSchedule else { return }
        let credentials: Credentials
        do {
            credentials = try credentialsForRequest()
        } catch {
            setStatusMessage(error.localizedDescription)
            return
        }
        isRefreshingSchedule = true
        scheduleRefreshToken &+= 1
        let refreshToken = scheduleRefreshToken
        setStatusMessage("正在获取个人课表…")
        let fallbackTermID = termID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ScheduleDefaults.termID : termID.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTermStart = termStartDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ScheduleDefaults.termStartDate : termStartDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard StrictContractDateParser.date(from: fallbackTermStart) != nil else {
            isRefreshingSchedule = false
            setStatusMessage(CredentialSettingsError.invalidTermStartDate.localizedDescription)
            return
        }
        let generation = localDataGeneration

        Task {
            defer {
                if refreshToken == scheduleRefreshToken { isRefreshingSchedule = false }
            }
            do {
                let fetched = try await scheduleClient.fetch(
                    credentials: credentials,
                    fallbackTermID: fallbackTermID,
                    fallbackTermStartDate: fallbackTermStart
                )
                guard generation == localDataGeneration, refreshToken == scheduleRefreshToken else { return }
                try scheduleStore.save(fetched)
                schedule = fetched
                synchronizeWidgetSchedule()
                calendarImportStatusMessage = ""
                termID = fetched.termID
                termStartDate = fetched.termStartDate
                defaults.set(termID, forKey: "termID")
                defaults.set(termStartDate, forKey: "termStartDate")
                synchronizeSelectedSlots()
                reconcileDailyCourseNotifications(requestPermissionIfNeeded: false)
                setStatusMessage(
                    "个人课表已更新，共 \(fetched.courses.count) 门课程",
                    autoDismiss: true
                )
            } catch {
                guard generation == localDataGeneration, refreshToken == scheduleRefreshToken else { return }
                setStatusMessage(error.localizedDescription)
            }
        }
    }

    private func setStatusMessage(_ message: String, autoDismiss: Bool = false) {
        statusMessageRevision &+= 1
        let revision = statusMessageRevision
        statusMessageDismissTask?.cancel()
        statusMessageDismissTask = nil
        statusMessage = message

        guard autoDismiss, !message.isEmpty else { return }
        statusMessageDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.statusMessageAutoDismissDelay ?? .seconds(4))
            } catch {
                return
            }
            guard
                let self,
                self.statusMessageRevision == revision,
                self.statusMessage == message
            else { return }
            self.statusMessage = ""
            self.statusMessageDismissTask = nil
        }
    }

    func importScheduleToCalendar() {
        guard !isSampleMode else {
            if isReviewDemo, let schedule {
                let count = (try? CalendarImportLogic.eventDrafts(from: schedule).count) ?? 0
                calendarImportStatusMessage = "示例模式已模拟同步 \(count) 个课程日期，未写入系统日历"
            } else {
                calendarImportStatusMessage = "示例模式不会访问系统日历"
            }
            return
        }
        guard !isImportingCalendar else { return }
        guard let schedule else {
            calendarImportStatusMessage = CalendarImportError.noSchedule.localizedDescription
            return
        }
        isImportingCalendar = true
        calendarImportToken &+= 1
        let importToken = calendarImportToken
        calendarImportStatusMessage = "正在导入系统日历…"
        let generation = localDataGeneration

        Task {
            defer {
                if importToken == calendarImportToken { isImportingCalendar = false }
            }
            do {
                let result = try await calendarImporter.importSchedule(schedule)
                guard generation == localDataGeneration, importToken == calendarImportToken else { return }
                if result.total == 0 {
                    calendarImportStatusMessage = "课表中没有可导入的课程日期"
                } else {
                    calendarImportStatusMessage = "日历同步完成：新增 \(result.inserted)，更新 \(result.updated)，删除 \(result.deleted)，已存在 \(result.unchanged)"
                }
            } catch {
                guard generation == localDataGeneration, importToken == calendarImportToken else { return }
                calendarImportStatusMessage = error.localizedDescription
            }
        }
    }

    func refreshClassroomsIfNeeded() {
        guard !isSampleMode else { return }
        guard classroomsCache?.targetDate != Self.todayString else { return }
        refreshClassrooms(force: false)
    }

    func refreshClassrooms(force: Bool = true) {
        guard !isSampleMode else {
            classroomStatusMessage = "正在展示内置示例空教室，未连接北邮服务"
            return
        }
        guard !isRefreshingClassrooms else { return }
        if !force, classroomsCache?.targetDate == Self.todayString { return }
        let credentials: Credentials
        do {
            credentials = try credentialsForRequest()
        } catch {
            classroomStatusMessage = error.localizedDescription
            return
        }
        isRefreshingClassrooms = true
        classroomRefreshToken &+= 1
        let refreshToken = classroomRefreshToken
        classroomStatusMessage = "正在获取当天空教室…"
        let targetDate = Self.todayString
        let generation = localDataGeneration

        Task {
            defer {
                if refreshToken == classroomRefreshToken { isRefreshingClassrooms = false }
            }
            do {
                let fetched = try await classroomClient.fetch(
                    credentials: credentials,
                    targetDate: targetDate
                )
                guard generation == localDataGeneration, refreshToken == classroomRefreshToken else { return }
                try classroomStore.save(fetched)
                classroomsCache = fetched
                selectedBuildings.formIntersection(Set(campusBuildings))
                classroomStatusMessage = "当天空教室已更新"
            } catch {
                guard generation == localDataGeneration, refreshToken == classroomRefreshToken else { return }
                classroomStatusMessage = error.localizedDescription
            }
        }
    }

    func startDailyClassroomRefresh() {
        guard !isSampleMode else { return }
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
        if isSampleMode {
            if holidaysByYear[year] == nil {
                holidaysByYear[year] = SampleData.holidays(year: year)
            }
            return
        }
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
        guard let loadToken = holidayLoads.begin(year: year) else { return }
        let cached = holidaysByYear[year]
        let generation = localDataGeneration

        Task {
            defer { holidayLoads.finish(year: year, token: loadToken) }
            do {
                let fetched = try await holidayClient.fetch(year: year)
                guard generation == localDataGeneration else { return }
                try holidayStore.save(fetched)
                holidaysByYear[year] = fetched
                holidayStatusByYear.removeValue(forKey: year)
            } catch {
                guard generation == localDataGeneration else { return }
                if cached != nil {
                    holidayStatusByYear[year] = "节假日更新失败，正在使用本地缓存"
                } else if let fallback = HolidayOfflineFallback.snapshot(year: year) {
                    holidaysByYear[year] = fallback
                    holidayStatusByYear[year] = "节假日更新失败，正在使用内置 2026 年数据"
                } else {
                    holidayStatusByYear[year] = "节假日数据暂不可用"
                }
            }
        }
    }

    private func loadCredentials() {
        do {
            guard let credentials = try credentialStore.load() else {
                password = ""
                updateSavedCredentialState(nil)
                return
            }
            account = credentials.account
            password = ""
            updateSavedCredentialState(credentials)
        } catch {
            password = ""
            updateSavedCredentialState(nil)
            statusMessage = error.localizedDescription
        }
    }

    private func credentialsForRequest() throws -> Credentials {
        try CredentialSettingsLogic.credentialsForRequest(
            account: account,
            password: password,
            storedCredentials: credentialStore.load()
        )
    }

    private func updateSavedCredentialState(_ credentials: Credentials?) {
        savedCredentialAccount = credentials?.account
        hasSavedPassword = !(credentials?.password.isEmpty ?? true)
    }

    private func clearAccountScopedData() throws {
        invalidatePendingAccountRequests()
        cancelDailyCourseNotifications()
        if dailyCourseNotificationsEnabled {
            dailyCourseNotificationStatusMessage = "账号已更改，获取课表后将重新安排摘要"
        }
        var failed = false
        do {
            try scheduleStore.clear()
        } catch {
            failed = true
        }
        schedule = nil
        synchronizeWidgetSchedule()
        calendarImportStatusMessage = ""
        do {
            try classroomStore.clear()
        } catch {
            failed = true
        }
        classroomsCache = nil
        classroomStatusMessage = ""
        selectedBuildings.removeAll()
        synchronizeSelectedSlots()
        if failed { throw CredentialSettingsError.accountDataResetFailed }
    }

    private func invalidatePendingAccountRequests() {
        localDataGeneration &+= 1
        scheduleRefreshToken &+= 1
        classroomRefreshToken &+= 1
        isRefreshingSchedule = false
        isRefreshingClassrooms = false
    }

    private func invalidatePendingOperations() {
        invalidatePendingAccountRequests()
        calendarImportToken &+= 1
        isImportingCalendar = false
    }

    private func loadSchedule() {
        do {
            schedule = try scheduleStore.load()
            if let schedule {
                termID = schedule.termID
                termStartDate = schedule.termStartDate
            }
            synchronizeWidgetSchedule()
        } catch {
            statusMessage = "本地课表读取失败：\(error.localizedDescription)"
        }
    }

    private func synchronizeWidgetSchedule() {
        #if os(macOS)
        let snapshot = schedule
        Task.detached(priority: .utility) {
            Self.writeWidgetSchedule(snapshot)
        }
        #endif
    }

    #if os(macOS)
    nonisolated private static func writeWidgetSchedule(_ schedule: ScheduleSnapshot?) {
        guard !AppLaunchConfiguration.isXCTestRunning else { return }
        if let schedule {
            try? TodayCourseWidgetData.save(schedule: schedule)
        } else {
            TodayCourseWidgetData.clear()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayCourseWidget")
    }
    #endif

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

    private func reconcileDailyCourseNotifications(requestPermissionIfNeeded: Bool) {
        guard !isSampleMode else {
            dailyCourseNotificationsEnabled = false
            return
        }
        dailyCourseNotificationRevision &+= 1
        let revision = dailyCourseNotificationRevision
        guard dailyCourseNotificationsEnabled else {
            dailyCourseNotificationScheduler.cancelPending(revision: revision)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await DailyCourseNotificationCoordinator(
                    scheduler: dailyCourseNotificationScheduler,
                    authorizationTimeout: dailyCourseNotificationAuthorizationTimeout
                ).reconcile(
                    enabled: dailyCourseNotificationsEnabled,
                    requestPermissionIfNeeded: requestPermissionIfNeeded,
                    hasCredentials: hasSavedPassword,
                    schedule: schedule,
                    revision: revision
                )
                guard revision == dailyCourseNotificationRevision else { return }
                switch outcome {
                case .disabled:
                    defaults.set(false, forKey: Self.dailyCourseNotificationsKey)
                case .permissionDenied:
                    dailyCourseNotificationsEnabled = false
                    defaults.set(false, forKey: Self.dailyCourseNotificationsKey)
                    dailyCourseNotificationStatusMessage = "通知权限未开启，未安排课程摘要"
                case .waitingForSchedule:
                    defaults.set(true, forKey: Self.dailyCourseNotificationsKey)
                    dailyCourseNotificationStatusMessage = "每日课程摘要已开启，获取课表后自动安排"
                case let .scheduled(count):
                    defaults.set(true, forKey: Self.dailyCourseNotificationsKey)
                    dailyCourseNotificationStatusMessage = count == 0
                        ? "每日课程摘要已开启，当前课表没有待通知课程"
                        : "已安排未来 \(count) 个有课日的课程摘要"
                }
            } catch {
                guard revision == dailyCourseNotificationRevision else { return }
                dailyCourseNotificationsEnabled = false
                defaults.set(false, forKey: Self.dailyCourseNotificationsKey)
                dailyCourseNotificationScheduler.cancelPending(revision: revision)
                dailyCourseNotificationStatusMessage = "课程摘要安排失败：\(error.localizedDescription)"
            }
        }
    }

    private func cancelDailyCourseNotifications() {
        dailyCourseNotificationRevision &+= 1
        dailyCourseNotificationScheduler.cancelPending(revision: dailyCourseNotificationRevision)
    }

    private static var todayString: String {
        StrictContractDateParser.string(from: .now)
    }

    private static func isFreshHolidaySnapshot(_ snapshot: HolidaysSnapshot, now: Date = .now) -> Bool {
        guard let fetchedAt = ISO8601DateFormatter().date(from: snapshot.fetchedAt) else { return false }
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age <= HolidayDefaults.refreshInterval
    }

    private static let dailyCourseNotificationsKey = DailyCourseNotificationSettings.enabledKey
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
