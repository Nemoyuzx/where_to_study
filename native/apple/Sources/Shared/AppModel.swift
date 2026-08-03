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
    @Published var selectedSlots = Set<Int>()
    @Published var schedule: ScheduleSnapshot?
    @Published var classrooms: [Classroom] = []
    @Published var statusMessage = ""
    @Published var isRefreshingSchedule = false

    let slots = SlotMetadata.defaults
    private let credentialStore: any CredentialStoring
    private let scheduleStore: any ScheduleStoring
    private let scheduleClient: any ScheduleFetching
    private let defaults: UserDefaults

    init(
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        scheduleStore: any ScheduleStoring = FileScheduleStore(),
        scheduleClient: any ScheduleFetching = SJDScheduleClient(),
        defaults: UserDefaults = .standard
    ) {
        self.credentialStore = credentialStore
        self.scheduleStore = scheduleStore
        self.scheduleClient = scheduleClient
        self.defaults = defaults
        termID = defaults.string(forKey: "termID") ?? ScheduleDefaults.termID
        termStartDate = defaults.string(forKey: "termStartDate") ?? ScheduleDefaults.termStartDate
        campusID = defaults.string(forKey: "campusID") ?? "01"
        loadCredentials()
        loadSchedule()
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

    func toggleSlot(_ slot: Int) {
        if selectedSlots.contains(slot) {
            selectedSlots.remove(slot)
        } else {
            selectedSlots.insert(slot)
        }
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
                statusMessage = "个人课表已更新，共 \(fetched.courses.count) 门课程"
            } catch {
                statusMessage = error.localizedDescription
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
