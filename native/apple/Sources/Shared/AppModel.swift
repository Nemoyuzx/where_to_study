import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum CredentialSettingsError: LocalizedError, Equatable {
    case accountRequired
    case passwordRequiredForChangedAccount
    case accountDataResetFailed
    case calendarImportInProgress
    case invalidTermID
    case invalidTermStartDate

    var errorDescription: String? {
        let language = AppLocalization.persistedLanguage()
        return switch self {
        case .accountRequired:
            AppLocalization.string("请输入教务账号。", language: language)
        case .passwordRequiredForChangedAccount:
            AppLocalization.string("更换教务账号时必须输入新密码。", language: language)
        case .accountDataResetFailed:
            AppLocalization.string("无法清除原账号的课表与空教室缓存，账号未更改。", language: language)
        case .calendarImportInProgress:
            AppLocalization.string("系统日历正在同步，请完成后再更换账号。", language: language)
        case .invalidTermID:
            AppLocalization.string("学期编号格式不正确，请使用 yyyy-yyyy-1 或 yyyy-yyyy-2。", language: language)
        case .invalidTermStartDate:
            AppLocalization.string("第一周周一日期格式不正确，请使用 yyyy-MM-dd。", language: language)
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

    var titleKey: String {
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

    var keyboardShortcutDigit: Character {
        switch self {
        case .planner: "1"
        case .calendar: "2"
        case .settings: "3"
        }
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

enum AutomaticScheduleRefreshLogic {
    static func shouldRequest(
        isSampleMode: Bool,
        automaticTermDetectionEnabled: Bool,
        hasSavedPassword: Bool,
        alreadyRequested: Bool
    ) -> Bool {
        !isSampleMode
            && automaticTermDetectionEnabled
            && hasSavedPassword
            && !alreadyRequested
    }
}

enum HolidayDisplayLogic {
    static func isAuthoritativeRestDaySource(_ snapshot: HolidaysSnapshot) -> Bool {
        snapshot.source != DeviceCalendarHolidayLogic.sourceLabel
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
    @Published private(set) var automaticTermDetectionEnabled: Bool
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
    @Published private(set) var widgetShowsLocation: Bool
    @Published private(set) var widgetShowsTeacher: Bool
    @Published private(set) var widgetCourseLimit: Int
    @Published private(set) var weatherEnabled: Bool
    @Published private(set) var almanacEnabled: Bool
    @Published private(set) var competitionDeadlinesEnabled: Bool
    @Published private(set) var schoolContestNoticesEnabled: Bool
    @Published private(set) var conferenceDeadlinesEnabled: Bool
    @Published private(set) var summerCampDeadlinesEnabled: Bool
    @Published private(set) var hackathonDeadlinesEnabled: Bool
    @Published private(set) var customDeadlinesEnabled: Bool
    @Published var customDeadlinesURL: String
    @Published private(set) var savedCustomDeadlinesURL: String
    @Published private(set) var favoriteDeadlines: [PublicDeadlineItem]
    @Published private(set) var appLanguage: AppLanguage

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
    private let now: @Sendable () -> Date
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
    private var hasRequestedAutomaticScheduleRefresh = false

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
        now: @escaping @Sendable () -> Date = Date.init,
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
        self.now = now
        self.defaults = defaults
        appLanguage = AppLocalization.persistedLanguage(defaults: defaults)
        let initialAutomaticTermDetection = defaults.object(
            forKey: Self.automaticTermDetectionKey
        ) as? Bool ?? true
        automaticTermDetectionEnabled = initialAutomaticTermDetection
        let initialTerm = SemesterLogic.resolveSettings(
            automaticDetectionEnabled: initialAutomaticTermDetection,
            persistedTermID: defaults.string(forKey: "termID"),
            persistedTermStartDate: defaults.string(forKey: "termStartDate"),
            for: now()
        )
        termID = initialTerm.termID
        termStartDate = initialTerm.termStartDate
        let savedCampusID = defaults.string(forKey: "campusID") ?? "01"
        campusID = savedCampusID
        queryCampusID = savedCampusID
        dailyCourseNotificationsEnabled = defaults.bool(forKey: Self.dailyCourseNotificationsKey)
        widgetShowsLocation = defaults.object(forKey: Self.widgetShowsLocationKey) as? Bool ?? true
        widgetShowsTeacher = defaults.object(forKey: Self.widgetShowsTeacherKey) as? Bool ?? true
        let savedWidgetCourseLimit = defaults.integer(forKey: Self.widgetCourseLimitKey)
        widgetCourseLimit = savedWidgetCourseLimit == 0
            ? TodayCourseWidgetData.Preferences.default.courseLimit
            : min(max(savedWidgetCourseLimit, 1), TodayCourseWidgetData.maximumCourseLimit)
        weatherEnabled = defaults.object(forKey: Self.weatherEnabledKey) as? Bool ?? true
        almanacEnabled = defaults.object(forKey: Self.almanacEnabledKey) as? Bool ?? true
        competitionDeadlinesEnabled = defaults.object(
            forKey: Self.competitionDeadlinesEnabledKey
        ) as? Bool ?? true
        schoolContestNoticesEnabled = defaults.object(
            forKey: Self.schoolContestNoticesEnabledKey
        ) as? Bool ?? true
        conferenceDeadlinesEnabled = defaults.object(
            forKey: Self.conferenceDeadlinesEnabledKey
        ) as? Bool ?? true
        summerCampDeadlinesEnabled = defaults.object(
            forKey: Self.summerCampDeadlinesEnabledKey
        ) as? Bool ?? true
        hackathonDeadlinesEnabled = defaults.object(
            forKey: Self.hackathonDeadlinesEnabledKey
        ) as? Bool ?? true
        if runtimeMode.isSample {
            customDeadlinesEnabled = false
            customDeadlinesURL = ""
            savedCustomDeadlinesURL = ""
            favoriteDeadlines = []
        } else {
            customDeadlinesEnabled = defaults.object(
                forKey: Self.customDeadlinesEnabledKey
            ) as? Bool ?? false
            let storedCustomDeadlinesURL = defaults.string(
                forKey: Self.customDeadlinesURLKey
            ) ?? ""
            customDeadlinesURL = storedCustomDeadlinesURL
            savedCustomDeadlinesURL = storedCustomDeadlinesURL
            favoriteDeadlines = Self.loadFavoriteDeadlines(defaults: defaults)
        }
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
        customDeadlinesEnabled = false
        customDeadlinesURL = ""
        savedCustomDeadlinesURL = ""
        favoriteDeadlines = []
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
        restoreTermSettingsFromDefaults()
        campusID = defaults.string(forKey: "campusID") ?? "01"
        queryCampusID = campusID
        dailyCourseNotificationsEnabled = defaults.bool(forKey: Self.dailyCourseNotificationsKey)
        widgetShowsLocation = defaults.object(forKey: Self.widgetShowsLocationKey) as? Bool ?? true
        widgetShowsTeacher = defaults.object(forKey: Self.widgetShowsTeacherKey) as? Bool ?? true
        let savedWidgetCourseLimit = defaults.integer(forKey: Self.widgetCourseLimitKey)
        widgetCourseLimit = savedWidgetCourseLimit == 0
            ? TodayCourseWidgetData.Preferences.default.courseLimit
            : min(max(savedWidgetCourseLimit, 1), TodayCourseWidgetData.maximumCourseLimit)
        customDeadlinesEnabled = defaults.object(
            forKey: Self.customDeadlinesEnabledKey
        ) as? Bool ?? false
        customDeadlinesURL = defaults.string(forKey: Self.customDeadlinesURLKey) ?? ""
        savedCustomDeadlinesURL = customDeadlinesURL
        favoriteDeadlines = Self.loadFavoriteDeadlines(defaults: defaults)
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
            let manualTermID = normalizedTermID
            let manualTermStartDate = normalizedTermStartDate
            guard automaticTermDetectionEnabled || SemesterLogic.isValidTermID(manualTermID) else {
                throw CredentialSettingsError.invalidTermID
            }
            guard automaticTermDetectionEnabled
                    || StrictContractDateParser.date(from: manualTermStartDate) != nil
            else {
                throw CredentialSettingsError.invalidTermStartDate
            }

            let storedCredentials = try credentialStore.load()
            let hadStoredPassword = !(storedCredentials?.password.isEmpty ?? true)
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
            let credentialsBecameAvailable = !hadStoredPassword && hasSavedPassword
            if accountChanged || credentialsBecameAvailable {
                hasRequestedAutomaticScheduleRefresh = false
            }
            account = CredentialSettingsLogic.normalizedAccount(account)
            password = ""
            if automaticTermDetectionEnabled {
                let automaticTerm = accountChanged
                    ? SemesterLogic.resolveSettings(
                        automaticDetectionEnabled: true,
                        persistedTermID: nil,
                        persistedTermStartDate: nil,
                        for: now()
                    )
                    : automaticTermSettings()
                termID = automaticTerm.termID
                termStartDate = automaticTerm.termStartDate
            } else {
                termID = manualTermID
                termStartDate = manualTermStartDate
            }
            defaults.set(campusID, forKey: "campusID")
            defaults.set(termID, forKey: "termID")
            defaults.set(termStartDate, forKey: "termStartDate")
            defaults.set(automaticTermDetectionEnabled, forKey: Self.automaticTermDetectionKey)
            setStatusMessage("设置已保存", autoDismiss: true)
            if automaticTermDetectionEnabled && (accountChanged || credentialsBecameAvailable) {
                refreshScheduleAutomaticallyIfNeeded()
            }
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

    func setAutomaticTermDetectionEnabled(_ enabled: Bool) {
        guard !isSampleMode else { return }
        let wasEnabled = automaticTermDetectionEnabled
        automaticTermDetectionEnabled = enabled
        defaults.set(enabled, forKey: Self.automaticTermDetectionKey)
        if enabled {
            if let schedule,
               SemesterLogic.acceptedCachedSettings(
                   termID: schedule.termID,
                   termStartDate: schedule.termStartDate,
                   for: now()
               ) == nil {
                self.schedule = nil
                synchronizeWidgetSchedule()
                synchronizeSelectedSlots()
            }
            let automaticTerm = automaticTermSettings()
            termID = automaticTerm.termID
            termStartDate = automaticTerm.termStartDate
            defaults.set(termID, forKey: "termID")
            defaults.set(termStartDate, forKey: "termStartDate")
            if !wasEnabled {
                hasRequestedAutomaticScheduleRefresh = false
                refreshScheduleAutomaticallyIfNeeded()
            }
        } else if wasEnabled {
            termID = ScheduleDefaults.termID
            termStartDate = ScheduleDefaults.termStartDate
            defaults.set(termID, forKey: "termID")
            defaults.set(termStartDate, forKey: "termStartDate")
        }
    }

    func setWidgetShowsLocation(_ enabled: Bool) {
        guard !isSampleMode else { return }
        widgetShowsLocation = enabled
        defaults.set(enabled, forKey: Self.widgetShowsLocationKey)
        synchronizeWidgetSchedule()
    }

    func setWidgetShowsTeacher(_ enabled: Bool) {
        guard !isSampleMode else { return }
        widgetShowsTeacher = enabled
        defaults.set(enabled, forKey: Self.widgetShowsTeacherKey)
        synchronizeWidgetSchedule()
    }

    func setWidgetCourseLimit(_ limit: Int) {
        guard !isSampleMode else { return }
        let normalized = min(max(limit, 1), TodayCourseWidgetData.maximumCourseLimit)
        widgetCourseLimit = normalized
        defaults.set(normalized, forKey: Self.widgetCourseLimitKey)
        synchronizeWidgetSchedule()
    }

    func setWeatherEnabled(_ enabled: Bool) {
        guard !isSampleMode else { return }
        weatherEnabled = enabled
        defaults.set(enabled, forKey: Self.weatherEnabledKey)
    }

    func setAlmanacEnabled(_ enabled: Bool) {
        guard !isSampleMode else { return }
        almanacEnabled = enabled
        defaults.set(enabled, forKey: Self.almanacEnabledKey)
    }

    func setCompetitionDeadlinesEnabled(_ enabled: Bool) {
        guard !isSampleMode else { return }
        competitionDeadlinesEnabled = enabled
        defaults.set(enabled, forKey: Self.competitionDeadlinesEnabledKey)
    }

    func setSchoolContestNoticesEnabled(_ enabled: Bool) {
        guard !isSampleMode else { return }
        schoolContestNoticesEnabled = enabled
        defaults.set(enabled, forKey: Self.schoolContestNoticesEnabledKey)
    }

    func setConferenceDeadlinesEnabled(_ enabled: Bool) {
        guard !isSampleMode else { return }
        conferenceDeadlinesEnabled = enabled
        defaults.set(enabled, forKey: Self.conferenceDeadlinesEnabledKey)
    }

    func setSummerCampDeadlinesEnabled(_ enabled: Bool) {
        guard !isSampleMode else { return }
        summerCampDeadlinesEnabled = enabled
        defaults.set(enabled, forKey: Self.summerCampDeadlinesEnabledKey)
    }

    func setHackathonDeadlinesEnabled(_ enabled: Bool) {
        guard !isSampleMode else { return }
        hackathonDeadlinesEnabled = enabled
        defaults.set(enabled, forKey: Self.hackathonDeadlinesEnabledKey)
    }

    func setCustomDeadlinesEnabled(_ enabled: Bool) {
        guard !isSampleMode else { return }
        customDeadlinesEnabled = enabled
        defaults.set(enabled, forKey: Self.customDeadlinesEnabledKey)
    }

    @discardableResult
    func saveCustomDeadlineSettings() throws -> URL? {
        guard !isSampleMode else {
            throw CalendarDeadlineError.service("示例模式不会保存自定义日程设置。")
        }
        let normalized = customDeadlinesURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            guard !customDeadlinesEnabled else {
                throw CalendarDeadlineError.service("请先填写自定义日程 HTTPS 地址。")
            }
            customDeadlinesURL = ""
            savedCustomDeadlinesURL = ""
            defaults.removeObject(forKey: Self.customDeadlinesURLKey)
            return nil
        }
        let url = try CustomDeadlineFeedURLValidator.validatedURL(normalized)
        customDeadlinesURL = url.absoluteString
        savedCustomDeadlinesURL = customDeadlinesURL
        defaults.set(customDeadlinesURL, forKey: Self.customDeadlinesURLKey)
        defaults.set(customDeadlinesEnabled, forKey: Self.customDeadlinesEnabledKey)
        return url
    }

    var customDeadlineSourceURL: URL? {
        guard customDeadlinesEnabled else { return nil }
        return try? CustomDeadlineFeedURLValidator.validatedURL(savedCustomDeadlinesURL)
    }

    func isFavorite(_ item: PublicDeadlineItem) -> Bool {
        favoriteDeadlines.contains { $0.favoriteID == item.favoriteID }
    }

    func setFavorite(_ item: PublicDeadlineItem, isFavorite: Bool) {
        let key = item.favoriteID
        var updated = favoriteDeadlines.filter { $0.favoriteID != key }
        if isFavorite {
            updated.insert(item, at: 0)
            updated = Array(updated.prefix(Self.maximumFavoriteDeadlines))
        }
        favoriteDeadlines = updated
        guard !isSampleMode else { return }
        persistFavoriteDeadlines()
    }

    func favoriteDeadlineItems(on date: Date) -> [PublicDeadlineItem] {
        favoriteDeadlineItems(on: StrictContractDateParser.string(from: date))
    }

    func favoriteDeadlineItems(on date: String) -> [PublicDeadlineItem] {
        favoriteDeadlines.filter { String($0.deadline.prefix(10)) == date }
    }

    func isDeadlineEnabled(_ item: PublicDeadlineItem) -> Bool {
        CalendarDeadlinePresentation.isVisible(
            item,
            competitionEnabled: competitionDeadlinesEnabled,
            schoolNoticeEnabled: schoolContestNoticesEnabled,
            conferenceEnabled: conferenceDeadlinesEnabled,
            summerCampEnabled: summerCampDeadlinesEnabled,
            hackathonEnabled: hackathonDeadlinesEnabled,
            customEnabled: customDeadlinesEnabled
        )
    }

    func visibleDeadlineItems(
        liveItems: [PublicDeadlineItem],
        on date: String
    ) -> [PublicDeadlineItem] {
        visibleDeadlineItems(
            liveItems: liveItems,
            favoriteItems: favoriteDeadlineItems(on: date)
        )
    }

    func visibleDeadlineItems(
        liveItems: [PublicDeadlineItem],
        favoriteItems: [PublicDeadlineItem]
    ) -> [PublicDeadlineItem] {
        var seen = Set<String>()
        var result = [PublicDeadlineItem]()
        for item in liveItems.filter(isDeadlineEnabled) + favoriteItems {
            if seen.insert(item.favoriteID).inserted {
                result.append(item)
            }
        }
        return result.sorted { ($0.deadline, $0.name) < ($1.deadline, $1.name) }
    }

    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        defaults.set(language.rawValue, forKey: AppLocalization.defaultsKey)
        synchronizeWidgetSchedule()
    }

    func localized(_ key: String) -> String {
        AppLocalization.string(key, language: appLanguage)
    }

    func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: appLanguage.locale, arguments: arguments)
    }

    var hasEnabledBuiltInPublicDeadlines: Bool {
        competitionDeadlinesEnabled || schoolContestNoticesEnabled
            || conferenceDeadlinesEnabled || summerCampDeadlinesEnabled
            || hackathonDeadlinesEnabled
    }

    var hasEnabledPublicDeadlines: Bool {
        hasEnabledBuiltInPublicDeadlines || customDeadlineSourceURL != nil
    }

    var hasCalendarDeadlinesToDisplay: Bool {
        hasEnabledPublicDeadlines || !favoriteDeadlines.isEmpty
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
        dailyClassroomRefreshTask?.cancel()
        dailyClassroomRefreshTask = nil
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
        defaults.removeObject(forKey: Self.automaticTermDetectionKey)
        defaults.removeObject(forKey: Self.widgetShowsLocationKey)
        defaults.removeObject(forKey: Self.widgetShowsTeacherKey)
        defaults.removeObject(forKey: Self.widgetCourseLimitKey)
        defaults.removeObject(forKey: Self.weatherEnabledKey)
        defaults.removeObject(forKey: Self.almanacEnabledKey)
        defaults.removeObject(forKey: Self.competitionDeadlinesEnabledKey)
        defaults.removeObject(forKey: Self.schoolContestNoticesEnabledKey)
        defaults.removeObject(forKey: Self.conferenceDeadlinesEnabledKey)
        defaults.removeObject(forKey: Self.summerCampDeadlinesEnabledKey)
        defaults.removeObject(forKey: Self.hackathonDeadlinesEnabledKey)
        defaults.removeObject(forKey: Self.customDeadlinesEnabledKey)
        defaults.removeObject(forKey: Self.customDeadlinesURLKey)
        defaults.removeObject(forKey: Self.favoriteDeadlinesKey)
        defaults.removeObject(forKey: AppLocalization.defaultsKey)
        campusID = "01"
        queryCampusID = "01"
        automaticTermDetectionEnabled = true
        let clearedTerm = SemesterLogic.resolveSettings(
            automaticDetectionEnabled: true,
            persistedTermID: nil,
            persistedTermStartDate: nil,
            for: now()
        )
        termID = clearedTerm.termID
        termStartDate = clearedTerm.termStartDate
        widgetShowsLocation = true
        widgetShowsTeacher = true
        widgetCourseLimit = TodayCourseWidgetData.Preferences.default.courseLimit
        weatherEnabled = true
        almanacEnabled = true
        competitionDeadlinesEnabled = true
        schoolContestNoticesEnabled = true
        conferenceDeadlinesEnabled = true
        summerCampDeadlinesEnabled = true
        hackathonDeadlinesEnabled = true
        customDeadlinesEnabled = false
        customDeadlinesURL = ""
        savedCustomDeadlinesURL = ""
        favoriteDeadlines = []
        appLanguage = .system
        selectedBuildings.removeAll()
        usePersonalSchedule = true
        synchronizeSelectedSlots()
        synchronizeWidgetSchedule()

        statusMessage = failures.isEmpty
            ? "本地数据已清除"
            : localized("以下本地数据未能清除：") + failures.joined(separator: "、")
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
        let usesAutomaticTermDetection = automaticTermDetectionEnabled
        let automaticFallback = automaticTermSettings()
        let normalizedTermID = termID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTermStartDate = termStartDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTermID = usesAutomaticTermDetection
            ? automaticFallback.termID
            : normalizedTermID
        let fallbackTermStart = usesAutomaticTermDetection
            ? automaticFallback.termStartDate
            : normalizedTermStartDate
        guard usesAutomaticTermDetection || SemesterLogic.isValidTermID(fallbackTermID) else {
            isRefreshingSchedule = false
            setStatusMessage(CredentialSettingsError.invalidTermID.localizedDescription)
            return
        }
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
                let resolvedSchedule = usesAutomaticTermDetection ? fetched : ScheduleSnapshot(
                    termID: fallbackTermID,
                    termStartDate: fallbackTermStart,
                    fetchedAt: fetched.fetchedAt,
                    courses: fetched.courses
                )
                try scheduleStore.save(resolvedSchedule)
                schedule = resolvedSchedule
                synchronizeWidgetSchedule()
                calendarImportStatusMessage = ""
                termID = resolvedSchedule.termID
                termStartDate = resolvedSchedule.termStartDate
                defaults.set(termID, forKey: "termID")
                defaults.set(termStartDate, forKey: "termStartDate")
                synchronizeSelectedSlots()
                reconcileDailyCourseNotifications(requestPermissionIfNeeded: false)
                setStatusMessage(
                    localizedFormat(
                        "个人课表已更新，共 %d 门课程",
                        resolvedSchedule.courses.count
                    ),
                    autoDismiss: true
                )
            } catch {
                guard generation == localDataGeneration, refreshToken == scheduleRefreshToken else { return }
                setStatusMessage(error.localizedDescription)
            }
        }
    }

    func refreshScheduleAutomaticallyIfNeeded() {
        guard AutomaticScheduleRefreshLogic.shouldRequest(
            isSampleMode: isSampleMode,
            automaticTermDetectionEnabled: automaticTermDetectionEnabled,
            hasSavedPassword: hasSavedPassword,
            alreadyRequested: hasRequestedAutomaticScheduleRefresh
        ) else { return }
        hasRequestedAutomaticScheduleRefresh = true
        refreshSchedule()
    }

    private func setStatusMessage(_ message: String, autoDismiss: Bool = false) {
        statusMessageRevision &+= 1
        let revision = statusMessageRevision
        statusMessageDismissTask?.cancel()
        statusMessageDismissTask = nil
        let displayedMessage = localized(message)
        statusMessage = displayedMessage

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
                self.statusMessage == displayedMessage
            else { return }
            self.statusMessage = ""
            self.statusMessageDismissTask = nil
        }
    }

    func importScheduleToCalendar() {
        guard !isSampleMode else {
            if isReviewDemo, let schedule {
                let count = (try? CalendarImportLogic.eventDrafts(from: schedule).count) ?? 0
                calendarImportStatusMessage = localizedFormat(
                    "示例模式已模拟同步 %d 个课程日期，未写入系统日历",
                    count
                )
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
                    calendarImportStatusMessage = localizedFormat(
                        "日历同步完成：新增 %d，更新 %d，删除 %d，已存在 %d",
                        result.inserted,
                        result.updated,
                        result.deleted,
                        result.unchanged
                    )
                }
            } catch {
                guard generation == localDataGeneration, importToken == calendarImportToken else { return }
                calendarImportStatusMessage = error.localizedDescription
            }
        }
    }

    func importFavoriteDeadlinesToCalendar() {
        let items = favoriteDeadlines
        guard !items.isEmpty else {
            calendarImportStatusMessage = "暂无已收藏日程可导入"
            return
        }
        guard !isSampleMode else {
            calendarImportStatusMessage = localizedFormat(
                "示例模式已模拟同步 %d 个收藏日程，未写入系统日历",
                items.count
            )
            return
        }
        guard !isImportingCalendar else { return }
        isImportingCalendar = true
        calendarImportToken &+= 1
        let importToken = calendarImportToken
        calendarImportStatusMessage = "正在导入已收藏日程…"
        let generation = localDataGeneration

        Task {
            defer {
                if importToken == calendarImportToken { isImportingCalendar = false }
            }
            do {
                let result = try await calendarImporter.importFavorites(items)
                guard generation == localDataGeneration, importToken == calendarImportToken else { return }
                calendarImportStatusMessage = localizedFormat(
                    "收藏日程同步完成：新增 %d，更新 %d，删除 %d，已存在 %d",
                    result.inserted,
                    result.updated,
                    result.deleted,
                    result.unchanged
                )
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

    private func fetchHolidaySnapshot(year: Int) async throws -> HolidaysSnapshot {
        // Only the statutory-holiday dataset is authoritative for 休/班.
        // Device holiday calendars also contain ordinary festivals, so using
        // them here incorrectly labels every festival as a rest day on iOS.
        return try await holidayClient.fetch(year: year)
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
                let stored = try holidayStore.load(year: year)
                if stored.map(HolidayDisplayLogic.isAuthoritativeRestDaySource) ?? true {
                    holidaysByYear[year] = stored
                }
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
                let fetched = try await fetchHolidaySnapshot(year: year)
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
            let cachedSchedule = try scheduleStore.load()
            if isSampleMode {
                schedule = cachedSchedule
                if let cachedSchedule {
                    termID = cachedSchedule.termID
                    termStartDate = cachedSchedule.termStartDate
                }
            } else if automaticTermDetectionEnabled {
                let currentDate = now()
                let acceptedSettings = SemesterLogic.acceptedCachedSettings(
                    termID: cachedSchedule?.termID,
                    termStartDate: cachedSchedule?.termStartDate,
                    for: currentDate
                )
                schedule = acceptedSettings == nil ? nil : cachedSchedule
                let automaticTerm = acceptedSettings ?? SemesterLogic.resolveSettings(
                    automaticDetectionEnabled: true,
                    persistedTermID: defaults.string(forKey: "termID"),
                    persistedTermStartDate: defaults.string(forKey: "termStartDate"),
                    for: currentDate
                )
                termID = automaticTerm.termID
                termStartDate = automaticTerm.termStartDate
                if acceptedSettings != nil {
                    defaults.set(termID, forKey: "termID")
                    defaults.set(termStartDate, forKey: "termStartDate")
                }
            } else {
                schedule = cachedSchedule
            }
            synchronizeWidgetSchedule()
        } catch {
            schedule = nil
            synchronizeWidgetSchedule()
            statusMessage = localized("本地课表读取失败：") + error.localizedDescription
        }
    }

    private func restoreTermSettingsFromDefaults() {
        automaticTermDetectionEnabled = defaults.object(
            forKey: Self.automaticTermDetectionKey
        ) as? Bool ?? true
        let restoredTerm = SemesterLogic.resolveSettings(
            automaticDetectionEnabled: automaticTermDetectionEnabled,
            persistedTermID: defaults.string(forKey: "termID"),
            persistedTermStartDate: defaults.string(forKey: "termStartDate"),
            for: now()
        )
        termID = restoredTerm.termID
        termStartDate = restoredTerm.termStartDate
    }

    private func automaticTermSettings() -> SemesterLogic.Settings {
        SemesterLogic.resolveSettings(
            automaticDetectionEnabled: true,
            persistedTermID: defaults.string(forKey: "termID"),
            persistedTermStartDate: defaults.string(forKey: "termStartDate"),
            cachedTermID: schedule?.termID,
            cachedTermStartDate: schedule?.termStartDate,
            for: now()
        )
    }

    private func synchronizeWidgetSchedule() {
        #if canImport(WidgetKit)
        let snapshot = schedule
        let preferences = TodayCourseWidgetData.Preferences(
            showsLocation: widgetShowsLocation,
            showsTeacher: widgetShowsTeacher,
            courseLimit: widgetCourseLimit
        )
        let languageRawValue = appLanguage.rawValue
        Task.detached(priority: .utility) {
            Self.writeWidgetSchedule(
                snapshot,
                preferences: preferences,
                languageRawValue: languageRawValue
            )
        }
        #endif
    }

    #if canImport(WidgetKit)
    nonisolated private static func writeWidgetSchedule(
        _ schedule: ScheduleSnapshot?,
        preferences: TodayCourseWidgetData.Preferences,
        languageRawValue: String
    ) {
        guard !AppLaunchConfiguration.isXCTestRunning else { return }
        TodayCourseWidgetData.saveLanguage(rawValue: languageRawValue)
        try? TodayCourseWidgetData.save(preferences: preferences)
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
            classroomStatusMessage = localized("本地空教室读取失败：") + error.localizedDescription
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
                        : localizedFormat("已安排未来 %d 个有课日的课程摘要", count)
                }
            } catch {
                guard revision == dailyCourseNotificationRevision else { return }
                dailyCourseNotificationsEnabled = false
                defaults.set(false, forKey: Self.dailyCourseNotificationsKey)
                dailyCourseNotificationScheduler.cancelPending(revision: revision)
                dailyCourseNotificationStatusMessage = localized("课程摘要安排失败：")
                    + localized(error.localizedDescription)
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
        guard HolidayDisplayLogic.isAuthoritativeRestDaySource(snapshot) else { return false }
        guard let fetchedAt = ISO8601DateFormatter().date(from: snapshot.fetchedAt) else { return false }
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age <= HolidayDefaults.refreshInterval
    }

    private static let dailyCourseNotificationsKey = DailyCourseNotificationSettings.enabledKey
    private static let automaticTermDetectionKey = "automaticTermDetectionEnabled"
    private static let widgetShowsLocationKey = "widgetShowsLocation"
    private static let widgetShowsTeacherKey = "widgetShowsTeacher"
    private static let widgetCourseLimitKey = "widgetCourseLimit"
    private static let weatherEnabledKey = "weatherEnabled"
    private static let almanacEnabledKey = "almanacEnabled"
    private static let competitionDeadlinesEnabledKey = "competitionDeadlinesEnabled"
    private static let schoolContestNoticesEnabledKey = "schoolContestNoticesEnabled"
    private static let conferenceDeadlinesEnabledKey = "conferenceDeadlinesEnabled"
    private static let summerCampDeadlinesEnabledKey = "summerCampDeadlinesEnabled"
    private static let hackathonDeadlinesEnabledKey = "hackathonDeadlinesEnabled"
    private static let customDeadlinesEnabledKey = "customDeadlinesEnabled"
    private static let customDeadlinesURLKey = "customDeadlinesURL"
    private static let favoriteDeadlinesKey = "favoriteDeadlines.v1"
    static let maximumFavoriteDeadlines = 500

    private static func loadFavoriteDeadlines(defaults: UserDefaults) -> [PublicDeadlineItem] {
        guard let data = defaults.data(forKey: favoriteDeadlinesKey),
              let decoded = try? JSONDecoder().decode([PublicDeadlineItem].self, from: data)
        else { return [] }
        var seen = Set<String>()
        return Array(decoded.filter { seen.insert($0.favoriteID).inserted }
            .prefix(maximumFavoriteDeadlines))
    }

    private func persistFavoriteDeadlines() {
        guard let data = try? JSONEncoder().encode(favoriteDeadlines) else { return }
        defaults.set(data, forKey: Self.favoriteDeadlinesKey)
    }
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
