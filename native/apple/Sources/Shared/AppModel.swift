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
    @Published var campusID: String
    @Published var selectedSlots = Set<Int>()
    @Published var schedule: ScheduleSnapshot?
    @Published var classrooms: [Classroom] = []
    @Published var statusMessage = ""

    let slots = SlotMetadata.defaults
    private let credentialStore: any CredentialStoring
    private let defaults: UserDefaults

    init(
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        defaults: UserDefaults = .standard
    ) {
        self.credentialStore = credentialStore
        self.defaults = defaults
        campusID = defaults.string(forKey: "campusID") ?? "01"
        loadCredentials()
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
            defaults.set(campusID, forKey: "campusID")
            statusMessage = "设置已保存"
        } catch {
            statusMessage = error.localizedDescription
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
