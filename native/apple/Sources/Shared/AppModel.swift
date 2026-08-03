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
    @Published var statusMessage = ""
    @Published var classroomStatusMessage = ""
    @Published var isRefreshingSchedule = false
    @Published var isRefreshingClassrooms = false

    let slots = SlotMetadata.defaults
    private let credentialStore: any CredentialStoring
    private let scheduleStore: any ScheduleStoring
    private let scheduleClient: any ScheduleFetching
    private let classroomStore: any ClassroomStoring
    private let classroomClient: any ClassroomFetching
    private let defaults: UserDefaults

    init(
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        scheduleStore: any ScheduleStoring = FileScheduleStore(),
        scheduleClient: any ScheduleFetching = SJDScheduleClient(),
        classroomStore: any ClassroomStoring = FileClassroomStore(),
        classroomClient: any ClassroomFetching = SJDClassroomClient(),
        defaults: UserDefaults = .standard
    ) {
        self.credentialStore = credentialStore
        self.scheduleStore = scheduleStore
        self.scheduleClient = scheduleClient
        self.classroomStore = classroomStore
        self.classroomClient = classroomClient
        self.defaults = defaults
        termID = defaults.string(forKey: "termID") ?? ScheduleDefaults.termID
        termStartDate = defaults.string(forKey: "termStartDate") ?? ScheduleDefaults.termStartDate
        campusID = defaults.string(forKey: "campusID") ?? "01"
        loadCredentials()
        loadSchedule()
        loadClassrooms()
        synchronizeSelectedSlots()
    }

    var selectedCampusName: String {
        campusID == "04" ? "沙河" : "西土城"
    }

    var todayCourses: [Course] {
        guard
            let schedule,
            let termStart = Self.dateFormatter.date(from: schedule.termStartDate)
        else { return [] }
        return ScheduleLogic.courses(on: .now, termStart: termStart, courses: schedule.courses)
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

        Task {
            defer { isRefreshingSchedule = false }
            do {
                let fetched = try await scheduleClient.fetch(
                    credentials: credentials,
                    fallbackTermID: fallbackTermID,
                    fallbackTermStartDate: fallbackTermStart
                )
                try scheduleStore.save(fetched)
                schedule = fetched
                termID = fetched.termID
                termStartDate = fetched.termStartDate
                defaults.set(termID, forKey: "termID")
                defaults.set(termStartDate, forKey: "termStartDate")
                synchronizeSelectedSlots()
                statusMessage = "个人课表已更新，共 \(fetched.courses.count) 门课程"
            } catch {
                statusMessage = error.localizedDescription
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

        Task {
            defer { isRefreshingClassrooms = false }
            do {
                let fetched = try await classroomClient.fetch(
                    credentials: credentials,
                    targetDate: targetDate
                )
                try classroomStore.save(fetched)
                classroomsCache = fetched
                selectedBuildings.formIntersection(Set(campusBuildings))
                classroomStatusMessage = "当天空教室已更新"
            } catch {
                classroomStatusMessage = error.localizedDescription
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
