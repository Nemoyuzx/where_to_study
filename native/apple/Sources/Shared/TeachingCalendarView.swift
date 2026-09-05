import Combine
import SwiftUI

enum TeachingCalendarNavigationMotion {
    enum PageEdge: Equatable {
        case leading
        case trailing
    }

    struct TransitionEdges: Equatable {
        let insertion: PageEdge
        let removal: PageEdge
    }

    static var pageAnimation: Animation {
        let duration = AppLaunchConfiguration.usesSlowCalendarAnimation ? 2.0 : 0.24
        return .easeInOut(duration: duration)
    }

    static func direction(from current: Date, to destination: Date) -> Int {
        destination < current ? -1 : 1
    }

    static func modeDirection(from current: String, to destination: String) -> Int {
        let order = ["日", "周", "月", "年"]
        let currentIndex = order.firstIndex(of: current) ?? 0
        let destinationIndex = order.firstIndex(of: destination) ?? currentIndex
        return destinationIndex < currentIndex ? -1 : 1
    }

    static func transitionEdges(direction: Int) -> TransitionEdges {
        direction < 0
            ? TransitionEdges(insertion: .leading, removal: .trailing)
            : TransitionEdges(insertion: .trailing, removal: .leading)
    }

    static func transition(direction: Int, includesOpacity: Bool = false) -> AnyTransition {
        let edges = transitionEdges(direction: direction)
        let insertionEdge: Edge = edges.insertion == .leading ? .leading : .trailing
        let removalEdge: Edge = edges.removal == .leading ? .leading : .trailing
        let transition = AnyTransition.asymmetric(
            insertion: .move(edge: insertionEdge),
            removal: .move(edge: removalEdge)
        )
        return includesOpacity ? transition.combined(with: .opacity) : transition
    }
}

final class TeachingCalendarSessionState: ObservableObject {
    // Retain only bounded projections while another section is visible. The
    // SwiftUI page and its clock/geometry work can still be destroyed normally.
    @MainActor lazy var renderingCache = TeachingCalendarRenderingCache()

    private struct PendingModeTransition {
        let generation: UInt
        let source: String
        let destination: String
    }

    @Published var selectedDate = Date() {
        didSet {
            guard !isCommittingAnchoredMonthNavigation else { return }
            preferredMonthDay = Calendar.shanghai.component(.day, from: selectedDate)
        }
    }
    @Published var modeRawValue = "周"
    @Published var isMonthExpanded = true
    @Published var isMonthDetailRaised = false
    @Published private(set) var transitionDirection = 1
    @Published private(set) var dismissOverlayGeneration = 0
    private var modeTransitionGeneration: UInt = 0
    private var pendingModeTransition: PendingModeTransition?
    private var preferredMonthDay: Int?
    private var isCommittingAnchoredMonthNavigation = false

    func monthNavigationDestination(
        direction: Int,
        calendar: Calendar = .shanghai
    ) -> Date? {
        let preferredDay = preferredMonthDay
            ?? calendar.component(.day, from: selectedDate)
        preferredMonthDay = preferredDay
        return TeachingCalendarLogic.movedDate(
            from: selectedDate,
            unit: .month,
            direction: direction,
            preferredDayOfMonth: preferredDay,
            calendar: calendar
        )
    }

    func commitMonthNavigation(to date: Date) {
        isCommittingAnchoredMonthNavigation = true
        selectedDate = date
        isCommittingAnchoredMonthNavigation = false
    }

    func applyKeyboardAction(
        _ action: AppKeyboardAction,
        now: Date = .now,
        calendar: Calendar = .shanghai
    ) {
        switch action {
        case .dayView: setMode(CalendarMode.day.rawValue)
        case .weekView: setMode(CalendarMode.week.rawValue)
        case .monthView: setMode(CalendarMode.month.rawValue)
        case .yearView: setMode(CalendarMode.year.rawValue)
        case .previousPeriod, .nextPeriod:
            let unit: TeachingCalendarLogic.NavigationUnit = switch modeRawValue {
            case CalendarMode.day.rawValue: .day
            case CalendarMode.month.rawValue: .month
            case CalendarMode.year.rawValue: .year
            default: .week
            }
            let direction = action == .previousPeriod ? -1 : 1
            prepareTransition(direction: direction)
            let moved = unit == .month
                ? monthNavigationDestination(direction: direction, calendar: calendar)
                : TeachingCalendarLogic.movedDate(
                    from: selectedDate,
                    unit: unit,
                    direction: direction,
                    calendar: calendar
                )
            if let moved {
                if unit == .month {
                    commitMonthNavigation(to: moved)
                } else {
                    selectedDate = moved
                }
            }
        case .today:
            prepareTransition(direction: TeachingCalendarNavigationMotion.direction(
                from: selectedDate,
                to: now
            ))
            selectedDate = now
        case .dismissOverlay:
            dismissOverlayGeneration &+= 1
        }
    }

    func prepareTransition(direction: Int) {
        transitionDirection = direction < 0 ? -1 : 1
    }

    func setMode(_ rawValue: String) {
        guard let generation = prepareModeTransition(to: rawValue) else { return }
        commitModeTransition(to: rawValue, generation: generation)
    }

    @discardableResult
    func prepareModeTransition(to rawValue: String) -> UInt? {
        guard rawValue != modeRawValue else { return nil }
        modeTransitionGeneration &+= 1
        let generation = modeTransitionGeneration
        pendingModeTransition = PendingModeTransition(
            generation: generation,
            source: modeRawValue,
            destination: rawValue
        )
        prepareTransition(direction: TeachingCalendarNavigationMotion.modeDirection(
            from: modeRawValue,
            to: rawValue
        ))
        return generation
    }

    @discardableResult
    func commitModeTransition(to rawValue: String, generation: UInt) -> Bool {
        guard let pendingModeTransition,
              pendingModeTransition.generation == generation,
              pendingModeTransition.source == modeRawValue,
              pendingModeTransition.destination == rawValue
        else { return false }
        self.pendingModeTransition = nil
        modeRawValue = rawValue
        return true
    }

    @MainActor
    @discardableResult
    func requestModeChange(to rawValue: String, selecting date: Date? = nil) async -> Bool {
        guard let generation = prepareModeTransition(to: rawValue) else {
            if let date { selectedDate = date }
            return false
        }

        // AnyTransition stores the removal edge on the outgoing view. A render
        // pass must install the prepared direction before the mode changes its
        // identity; otherwise a reversal can reuse the preceding insertion edge.
        await Task.yield()
        guard !Task.isCancelled else { return false }
        return withAnimation(TeachingCalendarNavigationMotion.pageAnimation) {
            guard commitModeTransition(to: rawValue, generation: generation) else { return false }
            if let date { selectedDate = date }
            return true
        }
    }
}

enum AppKeyboardAction: String, Equatable, Sendable {
    case dayView
    case weekView
    case monthView
    case yearView
    case previousPeriod
    case nextPeriod
    case today
    case dismissOverlay

    var targetCalendarModeRawValue: String? {
        switch self {
        case .dayView: "日"
        case .weekView: "周"
        case .monthView: "月"
        case .yearView: "年"
        default: nil
        }
    }
}

enum AppKeyboardCommandNotification {
    static let name = Notification.Name("WhereToStudy.AppKeyboardCommand")
    static let actionKey = "action"

    static func post(_ action: AppKeyboardAction) {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: [actionKey: action.rawValue]
        )
    }

    static func action(from notification: Notification) -> AppKeyboardAction? {
        (notification.userInfo?[actionKey] as? String).flatMap(AppKeyboardAction.init(rawValue:))
    }
}

private enum CalendarMode: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"

    var id: String { rawValue }
}

private struct CalendarDailyDetailsLoadID: Hashable {
    let dates: [String]
    let almanacDate: String?
    let sampleMode: Bool
    let loadsAlmanac: Bool
    let loadsPublicDeadlines: Bool
    let customSourceURL: String?
}

private struct CalendarAgendaSelection: Identifiable {
    let id = UUID()
    let date: Date
    let events: [CalendarAgendaDisplayItem]
}

private enum CalendarAgendaItemKind {
    case course
    case holiday
    case workday
    case assignment
    case schoolNotice
    case competition
    case conference
    case summerCamp
    case hackathon
    case customDeadline
}

private struct CalendarAgendaDisplayItem: Identifiable {
    let id: String
    let title: String
    let time: String?
    let categoryKey: String
    let kind: CalendarAgendaItemKind
    let destinationURL: URL?
    let deadlineItem: PublicDeadlineItem?

    init(
        id: String,
        title: String,
        time: String? = nil,
        categoryKey: String,
        kind: CalendarAgendaItemKind,
        destinationURL: URL? = nil,
        deadlineItem: PublicDeadlineItem? = nil
    ) {
        self.id = id
        self.title = title
        self.time = time
        self.categoryKey = categoryKey
        self.kind = kind
        self.destinationURL = destinationURL
        self.deadlineItem = deadlineItem
    }
}

private struct CalendarMonthDeadlineEvent: Identifiable {
    let id: String
    let title: String
    let categoryKey: String
    let agendaKind: CalendarAgendaItemKind
    let tint: Color
    let deadlineItem: PublicDeadlineItem?

    init(
        id: String,
        title: String,
        categoryKey: String,
        agendaKind: CalendarAgendaItemKind,
        tint: Color,
        deadlineItem: PublicDeadlineItem? = nil
    ) {
        self.id = id
        self.title = title
        self.categoryKey = categoryKey
        self.agendaKind = agendaKind
        self.tint = tint
        self.deadlineItem = deadlineItem
    }
}

fileprivate struct CalendarMonthDaySnapshot: Identifiable {
    let date: Date
    let dateKey: String
    let dayNumber: Int
    let weekday: Int
    let month: Int
    let accessibilityLabel: String
    let courses: [Course]
    let holidays: [HolidayItem]
    let assignments: [AssignmentDeadlineItem]
    let schoolNotices: [PublicDeadlineItem]
    let publicDeadlines: [PublicDeadlineItem]
    let allDayEvents: [CalendarAllDayEvent]
    let deadlineKinds: [CalendarAllDayEventKind]
    let deadlineAccessibilityValue: String

    var id: Date { date }
}

fileprivate struct CalendarDaySnapshotCollection {
    let days: [CalendarMonthDaySnapshot]
    let byDate: [String: CalendarMonthDaySnapshot]
    let byMonth: [Int: [CalendarMonthDaySnapshot]]

    init(days: [CalendarMonthDaySnapshot]) {
        self.days = days
        byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.dateKey, $0) })
        byMonth = Dictionary(grouping: days, by: \CalendarMonthDaySnapshot.month)
    }
}

final class CalendarBoundedCache<Key: Hashable, Value>: ObservableObject {
    private let capacity: Int
    private var valuesByKey = [Key: Value]()
    private var accessOrder = [Key]()

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { valuesByKey.count }
    var isEmpty: Bool { valuesByKey.isEmpty }
    var keys: [Key] { accessOrder }

    func value(for key: Key, build: () -> Value) -> Value {
        if let cached = valuesByKey[key] {
            markRecentlyUsed(key)
            return cached
        }
        let values = build()
        if valuesByKey.count >= capacity, let leastRecentlyUsed = accessOrder.first {
            valuesByKey.removeValue(forKey: leastRecentlyUsed)
            accessOrder.removeFirst()
        }
        valuesByKey[key] = values
        accessOrder.append(key)
        return values
    }

    func removeAll() {
        guard !valuesByKey.isEmpty else { return }
        objectWillChange.send()
        valuesByKey.removeAll(keepingCapacity: true)
        accessOrder.removeAll(keepingCapacity: true)
    }

    private func markRecentlyUsed(_ key: Key) {
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)
    }
}

final class CalendarDateFormatterCache: ObservableObject {
    private let storage = CalendarBoundedCache<String, DateFormatter>(capacity: 8)

    func formatter(format: String, locale: Locale) -> DateFormatter {
        let key = "\(locale.identifier)|\(format)"
        return storage.value(for: key) {
            let formatter = DateFormatter()
            formatter.calendar = .shanghai
            formatter.locale = locale
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = format
            return formatter
        }
    }
}

@MainActor
final class CalendarSnapshotInvalidationObserver: ObservableObject {
    private var cancellable: AnyCancellable?
    private var boundModelID: ObjectIdentifier?
    private var boundDeadlineStoreID: ObjectIdentifier?

    func bind(
        model: AppModel,
        deadlineStore: CalendarDeadlineStore,
        invalidate: @escaping @MainActor () -> Void
    ) {
        let modelID = ObjectIdentifier(model)
        let deadlineStoreID = ObjectIdentifier(deadlineStore)
        guard boundModelID != modelID || boundDeadlineStoreID != deadlineStoreID else { return }
        // The first body can populate a projection before this task subscribes.
        // Data published in that interval must not leave an empty cache behind.
        invalidate()
        boundModelID = modelID
        boundDeadlineStoreID = deadlineStoreID

        let scheduleChanges: [AnyPublisher<Void, Never>] = [
            model.$schedule.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$termID.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$termStartDate.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$automaticTermDetectionEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$runtimeMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        let presentationChanges: [AnyPublisher<Void, Never>] = [
            model.$holidaysByYear.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$favoriteDeadlines.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$appLanguage.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        let sourceChanges: [AnyPublisher<Void, Never>] = [
            model.$competitionDeadlinesEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$schoolContestNoticesEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$conferenceDeadlinesEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$summerCampDeadlinesEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$hackathonDeadlinesEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$customDeadlinesEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        let deadlineChanges: [AnyPublisher<Void, Never>] = [
            deadlineStore.$publicByDate.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            deadlineStore.$customByDate.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            deadlineStore.$assignmentsByDate.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        cancellable = Publishers.MergeMany(scheduleChanges + presentationChanges + sourceChanges + deadlineChanges)
        // Published values arrive in willSet. Invalidate after the batch has
        // committed, once per run loop, so a render never caches an old value.
        .debounce(for: .zero, scheduler: RunLoop.main)
        .sink { _ in
            Task { @MainActor in invalidate() }
        }
    }
}

@MainActor
final class TeachingCalendarRenderingCache {
    fileprivate let monthSnapshots = CalendarBoundedCache<String, CalendarDaySnapshotCollection>(capacity: 4)
    let timelineSnapshots = CalendarBoundedCache<String, [CalendarTimelineDay]>(capacity: 6)
    let dateFormatters = CalendarDateFormatterCache()
    private let invalidation = CalendarSnapshotInvalidationObserver()

    func bind(model: AppModel, deadlineStore: CalendarDeadlineStore) {
        invalidation.bind(model: model, deadlineStore: deadlineStore) { [weak self] in
            self?.monthSnapshots.removeAll()
            self?.timelineSnapshots.removeAll()
        }
    }
}

#if os(macOS)
private struct DesktopMonthEvent: Identifiable {
    enum Kind: Equatable {
        case course
        case holiday
        case workday
        case assignment
        case schoolNotice
        case competition
        case conference
        case summerCamp
        case hackathon
        case customDeadline
    }

    let id: String
    let title: String
    let time: String?
    let kind: Kind
    let deadlineItem: PublicDeadlineItem?

    init(
        id: String,
        title: String,
        time: String?,
        kind: Kind,
        deadlineItem: PublicDeadlineItem? = nil
    ) {
        self.id = id
        self.title = title
        self.time = time
        self.kind = kind
        self.deadlineItem = deadlineItem
    }
}
#endif

enum TeachingCalendarLogic {
    enum GestureAxis: Equatable {
        case horizontal
        case vertical
    }

    enum MonthExpansionAction: Equatable {
        case expand
        case collapse
    }

    enum NavigationUnit {
        case day
        case week
        case month
        case year
    }

    struct MonthEventLayout: Equatable {
        let visibleEventCount: Int
        let hiddenEventCount: Int
    }

    struct MonthGridLayout: Equatable {
        let collapsedCellHeight: CGFloat
        let expandedCellHeight: CGFloat
        let collapsedGridWidth: CGFloat
        let expandedGridWidth: CGFloat

        func cellHeight(at progress: CGFloat) -> CGFloat {
            interpolate(from: collapsedCellHeight, to: expandedCellHeight, at: progress)
        }

        func gridWidth(at progress: CGFloat) -> CGFloat {
            interpolate(from: collapsedGridWidth, to: expandedGridWidth, at: progress)
        }

        private func interpolate(from start: CGFloat, to end: CGFloat, at progress: CGFloat) -> CGFloat {
            let clampedProgress = min(max(progress, 0), 1)
            return start + (end - start) * clampedProgress
        }
    }

    struct MonthGridPosition: Equatable {
        let row: Int
        let column: Int
    }

    static func monthGridPosition(dayNumber: Int, firstWeekday: Int) -> MonthGridPosition {
        let leadingDays = (firstWeekday + 5) % 7
        let index = leadingDays + max(dayNumber - 1, 0)
        return MonthGridPosition(row: index / 7, column: index % 7)
    }

    struct YearPopoverPlacement: Equatable {
        let origin: CGPoint
        let appearsBelowAnchor: Bool
    }

    static func yearPopoverPlacement(
        anchor: CGPoint,
        panelSize: CGSize,
        containerSize: CGSize,
        margin: CGFloat = 16,
        gap: CGFloat = 12
    ) -> YearPopoverPlacement {
        let maximumX = max(margin, containerSize.width - panelSize.width - margin)
        let originX = min(max(margin, anchor.x - panelSize.width / 2), maximumX)
        let maximumY = max(margin, containerSize.height - panelSize.height - margin)
        let belowY = anchor.y + gap
        if belowY <= maximumY {
            return YearPopoverPlacement(
                origin: CGPoint(x: originX, y: belowY),
                appearsBelowAnchor: true
            )
        }
        let aboveY = min(maximumY, max(margin, anchor.y - panelSize.height - gap))
        return YearPopoverPlacement(
            origin: CGPoint(x: originX, y: aboveY),
            appearsBelowAnchor: false
        )
    }

    #if os(macOS)
    struct DesktopYearLayout: Equatable {
        let rowSpacing: CGFloat
        let columnSpacing: CGFloat
        let monthHeight: CGFloat
        let monthTitleFontSize: CGFloat
        let monthTitleHeight: CGFloat
        let monthContentSpacing: CGFloat
        let weekdayFontSize: CGFloat
        let weekdayHeight: CGFloat
        let gridSpacing: CGFloat
        let dayCellHeight: CGFloat
        let dayFontSize: CGFloat
        let holidayFontSize: CGFloat
        let selectionDiameter: CGFloat

        var totalHeight: CGFloat {
            monthHeight * 3 + rowSpacing * 2
        }
    }
    #endif

    enum MonthPosition: Int, CaseIterable {
        case detailRaised = 0
        case collapsed = 1
        case expanded = 2
    }

    static func routesMonthDragToDetails(
        position: MonthPosition,
        verticalTranslation: CGFloat,
        detailsCanScrollBackward: Bool = false
    ) -> Bool {
        guard position == .detailRaised else { return false }
        return verticalTranslation < 0 || detailsCanScrollBackward
    }

    static func yearCourseOpacity(courseCount: Int) -> Double {
        guard courseCount > 0 else { return 0 }
        let count = Double(courseCount)
        return 0.12 + 0.72 * count / (count + 3)
    }

    static func dayAccessibilityLabel(
        todayText: String? = nil,
        formattedDate: String,
        holidayNames: [String],
        courseDescriptions: [String]
    ) -> String {
        let courses = courseDescriptions.joined(separator: "，")
        return [
            todayText ?? "",
            formattedDate,
            holidayNames.joined(separator: "，"),
            courses.isEmpty ? "无课" : courses,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "，")
    }

    #if os(macOS)
    static func desktopYearLayout(availableHeight: CGFloat) -> DesktopYearLayout {
        let height = max(availableHeight, 0)
        let rowSpacing = min(max(height * 0.025, 8), 28)
        let monthHeight = max((height - rowSpacing * 2) / 3, 0)
        let monthTitleFontSize = min(max(monthHeight * 0.095, 13), 22)
        let monthTitleHeight = monthTitleFontSize * 1.25
        let monthContentSpacing = min(max(monthHeight * 0.025, 2), 10)
        let weekdayFontSize = min(max(monthHeight * 0.052, 8), 12)
        let weekdayHeight = min(max(monthHeight * 0.075, 10), 20)
        let gridSpacing = min(max(monthHeight * 0.014, 1), 4)
        let reservedHeight = monthTitleHeight
            + monthContentSpacing
            + weekdayHeight
            + gridSpacing * 6
        let dayCellHeight = max((monthHeight - reservedHeight) / 6, 1)
        let dayFontSize = min(max(dayCellHeight * 0.4, 7), 14)
        let holidayFontSize = min(max(dayCellHeight * 0.28, 6), 10)
        let selectionDiameter = min(dayCellHeight, min(max(dayCellHeight * 0.82, 10), 40))

        return DesktopYearLayout(
            rowSpacing: rowSpacing,
            columnSpacing: min(max(monthHeight * 0.07, 12), 28),
            monthHeight: monthHeight,
            monthTitleFontSize: monthTitleFontSize,
            monthTitleHeight: monthTitleHeight,
            monthContentSpacing: monthContentSpacing,
            weekdayFontSize: weekdayFontSize,
            weekdayHeight: weekdayHeight,
            gridSpacing: gridSpacing,
            dayCellHeight: dayCellHeight,
            dayFontSize: dayFontSize,
            holidayFontSize: holidayFontSize,
            selectionDiameter: selectionDiameter
        )
    }
    #endif

    static func periodTitle(
        for date: Date,
        modeRawValue: String,
        teachingWeekNumber: Int? = nil,
        language: AppLanguage = .simplifiedChinese,
        calendar: Calendar = .shanghai
    ) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        if language.resolvedResourceName == "en" {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en")
            formatter.timeZone = calendar.timeZone
            switch modeRawValue {
            case CalendarMode.day.rawValue:
                formatter.dateFormat = "MMMM d, yyyy"
                return formatter.string(from: date)
            case CalendarMode.week.rawValue:
                formatter.dateFormat = "MMMM yyyy"
                let context = weekContext(
                    for: date,
                    teachingWeekNumber: teachingWeekNumber,
                    language: language,
                    calendar: calendar
                )
                return "\(formatter.string(from: date)) · \(context)"
            case CalendarMode.year.rawValue:
                return "\(year)"
            default:
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: date)
            }
        }
        switch modeRawValue {
        case CalendarMode.day.rawValue:
            return "\(year)年\(month)月\(calendar.component(.day, from: date))日"
        case CalendarMode.week.rawValue:
            let context = weekContext(
                for: date,
                teachingWeekNumber: teachingWeekNumber,
                language: language,
                calendar: calendar
            )
            return "\(year)年\(month)月 · \(context)"
        case CalendarMode.year.rawValue:
            return "\(year)年"
        default:
            return "\(year)年\(month)月"
        }
    }

    static func civilWeekNumber(
        on date: Date,
        calendar: Calendar = .shanghai
    ) -> Int {
        ScheduleLogic.civilWeekNumber(on: date, calendar: calendar)
    }

    static func weekContext(
        for date: Date,
        teachingWeekNumber: Int?,
        language: AppLanguage = .simplifiedChinese,
        calendar: Calendar = .shanghai,
        compact: Bool = false
    ) -> String {
        let civilWeek = civilWeekNumber(on: date, calendar: calendar)
        if language.resolvedResourceName == "en" {
            if compact {
                return teachingWeekNumber.map { "C\(civilWeek) · T\($0)" }
                    ?? "C\(civilWeek) · Outside term"
            }
            return teachingWeekNumber.map {
                "Calendar Week \(civilWeek) · Teaching Week \($0)"
            } ?? "Calendar Week \(civilWeek) · Outside teaching weeks"
        }
        if compact {
            return teachingWeekNumber.map { "公\(civilWeek) · 教\($0)" }
                ?? "公\(civilWeek) · 非教学周"
        }
        return teachingWeekNumber.map { "公历第 \(civilWeek) 周 · 第 \($0) 教学周" }
            ?? "公历第 \(civilWeek) 周 · 非教学周"
    }

    static func movedDate(
        from date: Date,
        unit: NavigationUnit,
        direction: Int,
        preferredDayOfMonth: Int? = nil,
        calendar: Calendar = .shanghai
    ) -> Date? {
        let component: Calendar.Component
        let amount: Int
        switch unit {
        case .day:
            component = .day
            amount = direction
        case .week:
            component = .day
            amount = direction * 7
        case .month:
            if let preferredDayOfMonth,
               let currentMonth = calendar.dateInterval(of: .month, for: date)?.start,
               let destinationMonth = calendar.date(
                   byAdding: .month,
                   value: direction,
                   to: currentMonth
               ),
               let validDays = calendar.range(of: .day, in: .month, for: destinationMonth)
            {
                var components = calendar.dateComponents(
                    [.hour, .minute, .second, .nanosecond],
                    from: date
                )
                let destinationComponents = calendar.dateComponents(
                    [.year, .month],
                    from: destinationMonth
                )
                components.timeZone = calendar.timeZone
                components.year = destinationComponents.year
                components.month = destinationComponents.month
                components.day = min(
                    max(preferredDayOfMonth, validDays.lowerBound),
                    validDays.upperBound - 1
                )
                return calendar.date(from: components)
            }
            component = .month
            amount = direction
        case .year:
            component = .year
            amount = direction
        }
        return calendar.date(byAdding: component, value: amount, to: date)
    }

    static func monthPageDirection(
        from currentDate: Date,
        to destinationDate: Date,
        calendar: Calendar = .shanghai
    ) -> Int? {
        let currentMonth = calendar.dateInterval(of: .month, for: currentDate)?.start
            ?? currentDate
        let destinationMonth = calendar.dateInterval(of: .month, for: destinationDate)?.start
            ?? destinationDate
        guard currentMonth != destinationMonth else { return nil }
        return destinationMonth > currentMonth ? 1 : -1
    }

    static func datesInYear(
        containing date: Date,
        calendar: Calendar = .shanghai
    ) -> [Date] {
        guard let interval = calendar.dateInterval(of: .year, for: date) else { return [] }
        var dates = [Date]()
        var day = interval.start
        while day < interval.end {
            dates.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates
    }

    static func visibleDates(
        containing date: Date,
        modeRawValue: String,
        calendar: Calendar = .shanghai
    ) -> [Date] {
        switch modeRawValue {
        case CalendarMode.day.rawValue:
            return [date]
        case CalendarMode.week.rawValue:
            let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            return (0 ..< 7).compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
        case CalendarMode.month.rawValue:
            let first = calendar.dateInterval(of: .month, for: date)?.start ?? date
            let leading = (calendar.component(.weekday, from: first) + 5) % 7
            guard let start = calendar.date(byAdding: .day, value: -leading, to: first)
            else { return [] }
            return (0 ..< 42).compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
        case CalendarMode.year.rawValue:
            return datesInYear(containing: date, calendar: calendar)
        default:
            return [date]
        }
    }

    static func swipeDirection(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        predictedHorizontalTranslation: CGFloat
    ) -> Int? {
        let projected = abs(predictedHorizontalTranslation) > abs(horizontalTranslation)
            ? predictedHorizontalTranslation
            : horizontalTranslation
        guard abs(horizontalTranslation) >= 36,
              abs(projected) >= 80,
              abs(horizontalTranslation) >= abs(verticalTranslation) * 1.35
        else { return nil }
        return projected < 0 ? 1 : -1
    }

    static func monthExpansionAction(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat
    ) -> MonthExpansionAction? {
        guard abs(verticalTranslation) >= 44,
              abs(verticalTranslation) >= abs(horizontalTranslation) * 1.25
        else { return nil }
        return verticalTranslation > 0 ? .expand : .collapse
    }

    static func gestureAxis(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        activationDistance: CGFloat = 8
    ) -> GestureAxis? {
        let horizontal = abs(horizontalTranslation)
        let vertical = abs(verticalTranslation)
        guard max(horizontal, vertical) >= activationDistance else { return nil }
        return horizontal > vertical ? .horizontal : .vertical
    }

    static func monthExpansionProgress(
        isExpanded: Bool,
        verticalTranslation: CGFloat,
        travelDistance: CGFloat
    ) -> CGFloat {
        let distance = max(travelDistance, 1)
        let base: CGFloat = isExpanded ? 1 : 0
        return min(max(base + verticalTranslation / distance, 0), 1)
    }

    static func monthPosition(
        isExpanded: Bool,
        isDetailRaised: Bool,
        verticalTranslation: CGFloat,
        travelDistance: CGFloat
    ) -> CGFloat {
        let distance = max(travelDistance, 1)
        let base = isExpanded
            ? CGFloat(MonthPosition.expanded.rawValue)
            : CGFloat(isDetailRaised ? MonthPosition.detailRaised.rawValue : MonthPosition.collapsed.rawValue)
        return min(max(base + verticalTranslation / distance, 0), 2)
    }

    static func monthGridExpansionProgress(position: CGFloat) -> CGFloat {
        min(max(position - CGFloat(MonthPosition.collapsed.rawValue), 0), 1)
    }

    static func monthDetailLiftProgress(position: CGFloat) -> CGFloat {
        min(max(CGFloat(MonthPosition.collapsed.rawValue) - position, 0), 1)
    }

    static func settledMonthPosition(
        position: CGFloat,
        verticalTranslation: CGFloat,
        predictedVerticalTranslation: CGFloat,
        allowsIntermediatePosition: Bool = true
    ) -> MonthPosition {
        let clamped = min(max(position, 0), 2)
        let projectedDelta = predictedVerticalTranslation - verticalTranslation
        if !allowsIntermediatePosition {
            if projectedDelta <= -42 { return .detailRaised }
            if projectedDelta >= 42 { return .expanded }
            return clamped < CGFloat(MonthPosition.collapsed.rawValue)
                ? .detailRaised
                : .expanded
        }
        let target: Int
        if abs(projectedDelta) >= 42 {
            target = projectedDelta > 0 ? Int(ceil(clamped)) : Int(floor(clamped))
        } else if abs(verticalTranslation) >= 24 {
            // A deliberate low-velocity drag must still cross one detent. XCTest
            // and accessibility-driven drags often have little projected
            // momentum even though the finger travelled far enough to express
            // intent; rounding here would otherwise snap the sheet backwards.
            target = verticalTranslation > 0 ? Int(ceil(clamped)) : Int(floor(clamped))
        } else {
            target = Int(clamped.rounded())
        }
        return MonthPosition(rawValue: min(max(target, 0), 2)) ?? .collapsed
    }

    static func normalizedMonthPosition(
        _ position: MonthPosition,
        allowsIntermediatePosition: Bool
    ) -> MonthPosition {
        guard !allowsIntermediatePosition, position == .collapsed else { return position }
        return .detailRaised
    }

    static func requiresMonthPositionUpdate(
        current: MonthPosition,
        target: MonthPosition,
        verticalTranslation: CGFloat,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        current != target || abs(verticalTranslation) > tolerance
    }

    static func expandedMonthCellHeight(availableHeight: CGFloat) -> CGFloat {
        let weekdayHeight: CGFloat = 18
        let weekdayBottomSpacing: CGFloat = 8
        let gridSpacing: CGFloat = 4 * 5
        let handleHeight: CGFloat = 28
        let verticalPadding: CGFloat = 8 * 2
        let availableGridHeight = availableHeight
            - weekdayHeight
            - weekdayBottomSpacing
            - gridSpacing
            - handleHeight
            - verticalPadding
        return max(30, floor(availableGridHeight / 6))
    }

    static func monthGridLayout(
        contentWidth: CGFloat,
        availableHeight: CGFloat,
        columnSpacing: CGFloat = 4
    ) -> MonthGridLayout {
        let width = max(contentWidth, 0)
        let totalColumnSpacing = columnSpacing * 6
        let squareCellHeight = max(24, floor((width - totalColumnSpacing) / 7))
        let expandedCellHeight = expandedMonthCellHeight(availableHeight: availableHeight)
        let collapsedCellHeight = min(squareCellHeight, expandedCellHeight)
        return MonthGridLayout(
            collapsedCellHeight: collapsedCellHeight,
            expandedCellHeight: expandedCellHeight,
            collapsedGridWidth: width,
            expandedGridWidth: width
        )
    }

    static func monthDayTopInset(collapsedCellHeight: CGFloat) -> CGFloat {
        let compactContentHeight: CGFloat = 31
        return max(4, floor((collapsedCellHeight - compactContentHeight) / 2))
    }

    static func monthEventRowCapacity(
        cellHeight: CGFloat,
        dayTopInset: CGFloat,
        dayLabelHeight: CGFloat = 20,
        rowHeight: CGFloat = 16
    ) -> Int {
        let available = cellHeight - dayTopInset - dayLabelHeight - 5
        return max(1, Int(floor(available / max(rowHeight, 1))))
    }

    static func monthEventLayout(totalCount: Int, maximumRows: Int) -> MonthEventLayout {
        let total = max(totalCount, 0)
        let rows = max(maximumRows, 0)
        guard total > rows else {
            return MonthEventLayout(visibleEventCount: total, hiddenEventCount: 0)
        }
        guard rows > 0 else {
            return MonthEventLayout(visibleEventCount: 0, hiddenEventCount: total)
        }
        return MonthEventLayout(
            visibleEventCount: rows - 1,
            hiddenEventCount: total - rows + 1
        )
    }
}

struct TeachingCalendarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var dailyInfo: DailyInfoStore
    @EnvironmentObject private var calendarDeadlines: CalendarDeadlineStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var session: TeachingCalendarSessionState
    private let renderingCache: TeachingCalendarRenderingCache
    @StateObject private var dateFormatterCache: CalendarDateFormatterCache
    @StateObject private var timelineSnapshotCache: CalendarBoundedCache<String, [CalendarTimelineDay]>
    @StateObject private var monthSnapshotCache: CalendarBoundedCache<
        String,
        CalendarDaySnapshotCollection
    >
    @State private var yearPopoverDate: Date?
    @State private var yearPopoverLocation: CGPoint?
    @State private var showingDatePicker = false
    @State private var presentedTimelineAgenda: CalendarAgendaSelection?
    @State private var monthPagingGeneration = 0
    @State private var yearPopoverScrollTarget = TeachingCalendarView.yearPopoverTopID

    private let calendar = Calendar.shanghai

    init(session: TeachingCalendarSessionState) {
        self.session = session
        let cache = session.renderingCache
        renderingCache = cache
        _dateFormatterCache = StateObject(wrappedValue: cache.dateFormatters)
        _timelineSnapshotCache = StateObject(wrappedValue: cache.timelineSnapshots)
        _monthSnapshotCache = StateObject(wrappedValue: cache.monthSnapshots)
    }

    private var selectedDate: Date {
        get { session.selectedDate }
        nonmutating set { session.selectedDate = newValue }
    }

    private var mode: CalendarMode {
        get { CalendarMode(rawValue: session.modeRawValue) ?? .week }
        nonmutating set { session.modeRawValue = newValue.rawValue }
    }

    private var isMonthExpanded: Bool {
        get { session.isMonthExpanded }
        nonmutating set { session.isMonthExpanded = newValue }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 16) {
                titleBar
                    .accessibilityIdentifier("layout.calendar.expanded")
                calendarPanelContent
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #else
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBar
                        .accessibilityIdentifier("layout.calendar.expanded")

                    Surface {
                        calendarPanelContent
                    }
                }
                .padding(20)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
            #endif

            #if !os(macOS)
            yearPopoverOverlay
            #endif
            if let selection = presentedTimelineAgenda {
                calendarAgendaDialog(
                    selection,
                    titleKey: mode == .week ? "周视图全天日程" : "全天日程",
                    accessibilityIdentifier: "calendar.regular.week-agenda-dialog",
                    dismiss: { presentedTimelineAgenda = nil }
                )
            }
        }
        .background(AppTheme.background)
        .accessibilityIdentifier("screen.calendar")
        .coordinateSpace(name: Self.calendarCoordinateSpace)
        .onChange(of: mode) { _ in
            dismissYearPopover()
            presentedTimelineAgenda = nil
        }
        .onChange(of: session.dismissOverlayGeneration) { _ in
            dismissYearPopover()
            showingDatePicker = false
            presentedTimelineAgenda = nil
        }
        .task(id: [ObjectIdentifier(model), ObjectIdentifier(calendarDeadlines)]) {
            renderingCache.bind(model: model, deadlineStore: calendarDeadlines)
        }
        .task(id: dailyDetailsLoadID) {
            await loadVisibleDailyDetails()
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var calendarPanelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            dateControls
            if let status = holidayStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if !model.statusMessage.isEmpty {
                Text(model.localized(model.statusMessage))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if !model.calendarImportStatusMessage.isEmpty {
                Text(model.localized(model.calendarImportStatusMessage))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Divider()
            #if os(macOS)
            ZStack(alignment: .topLeading) {
                calendarContent
                    .id(calendarContentIdentity)
                    .transition(TeachingCalendarNavigationMotion.transition(
                        direction: session.transitionDirection,
                        includesOpacity: true
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .animation(TeachingCalendarNavigationMotion.pageAnimation, value: calendarContentIdentity)
            #else
            calendarContent
                .id(calendarContentIdentity)
                .transition(TeachingCalendarNavigationMotion.transition(
                    direction: session.transitionDirection,
                    includesOpacity: true
                ))
            #endif
        }
        #if os(macOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #else
        .frame(maxWidth: .infinity, alignment: .topLeading)
        #endif
    }

    @ViewBuilder
    private var titleBar: some View {
        #if os(macOS)
        HStack(alignment: .bottom) {
            animatedPageTitle
            modePicker.frame(maxWidth: 280)
        }
        #else
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) {
                animatedPageTitle
                modePicker.frame(width: 300)
            }
            VStack(alignment: .leading, spacing: 12) {
                animatedPageTitle
                modePicker
            }
        }
        #endif
    }

    private var animatedPageTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BUPT CLASSROOM PLANNER")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.secondaryText)
            ZStack(alignment: .leading) {
                Text(periodTitle)
                    .id(periodTitle)
                    .transition(TeachingCalendarNavigationMotion.transition(
                        direction: session.transitionDirection,
                        includesOpacity: true
                    ))
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .clipped()
            .animation(TeachingCalendarNavigationMotion.pageAnimation, value: periodTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modePicker: some View {
        Picker("视图", selection: modeSelection) {
            ForEach(CalendarMode.allCases) { item in
                Text(model.localized(item.rawValue)).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var dateControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                dateNavigation
                Spacer(minLength: 12)
                calendarActions
            }
            VStack(alignment: .leading, spacing: 10) {
                dateNavigation
                calendarActions
            }
        }
    }

    private var dateNavigation: some View {
        HStack(spacing: 8) {
            dateStepButton(systemName: "chevron.left", help: "上一时间段") { moveDate(-1) }
            Button {
                showingDatePicker.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text(controlDateFormatter.string(from: selectedDate))
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.text)
                .frame(width: 148, height: 32)
                .background(AppTheme.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDatePicker, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("选择日期")
                        .font(.headline)
                    DatePicker("日期", selection: datePickerSelection, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.graphical)
                        .environment(\.locale, model.appLanguage.locale)
                        .environment(\.timeZone, Calendar.shanghai.timeZone)
                }
                .padding(14)
                .frame(width: 310)
            }
            Button("今天") {
                if mode == .month {
                    selectMonthDay(.now)
                } else {
                    session.prepareTransition(direction: TeachingCalendarNavigationMotion.direction(
                        from: selectedDate,
                        to: .now
                    ))
                    withAnimation(Self.viewAnimation) { selectedDate = .now }
                }
            }
            .frame(minWidth: 48)
            dateStepButton(systemName: "chevron.right", help: "下一时间段") { moveDate(1) }
        }
        .controlSize(.regular)
    }

    private func dateStepButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 16, height: 18)
        }
        .buttonStyle(.bordered)
        .help(help)
    }

    private var calendarActions: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    model.refreshSchedule()
                } label: {
                    Label(
                        model.isRefreshingSchedule ? "正在获取…" : "获取/刷新个人课表",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(model.isRefreshingSchedule || model.isImportingCalendar)
                Button {
                    model.importScheduleToCalendar()
                } label: {
                    Label(
                        model.isImportingCalendar ? "正在导入…" : "导入系统日历",
                        systemImage: "calendar.badge.plus"
                    )
                }
                .disabled(model.schedule == nil || model.isRefreshingSchedule || model.isImportingCalendar)
            }
            Button {
                model.importFavoriteDeadlinesToCalendar()
            } label: {
                Label(
                    model.isImportingCalendar ? "正在导入…" : "导入已收藏日程",
                    systemImage: "star.square.on.square"
                )
            }
            .disabled(model.favoriteDeadlines.isEmpty || model.isImportingCalendar)
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        switch mode {
        case .day: dayView
        case .week: weekView
        case .month: monthView
        case .year: yearView
        }
    }

    private var dayView: some View {
        return VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(monthWeekContextText(date: selectedDate))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: "graduationcap")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryText)
            .accessibilityIdentifier("calendar.regular.day-week-context")
            CalendarTimelineView(
                days: cachedTimelineDays(for: [selectedDate]),
                selectedDate: selectedDate,
                onSelectAllDayEvent: { date, _ in
                    presentedTimelineAgenda = CalendarAgendaSelection(
                        date: date,
                        events: allDayEvents(on: date).map(calendarAgendaDisplayItem)
                    )
                }
            )
        }
        .contentShape(Rectangle())
        .simultaneousGesture(periodSwipeGesture)
    }

    private var weekView: some View {
        let days = weekDates()
        return VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(weekContextText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("calendar.regular.teaching-week")
            } icon: {
                Image(systemName: "graduationcap")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryText)
            CalendarTimelineView(
                days: cachedTimelineDays(for: days),
                selectedDate: selectedDate,
                onSelectDay: { date in
                    session.prepareTransition(direction: TeachingCalendarNavigationMotion.direction(
                        from: selectedDate,
                        to: date
                    ))
                    withAnimation(TeachingCalendarNavigationMotion.pageAnimation) {
                        selectedDate = date
                    }
                },
                onSelectAllDayEvent: { date, _ in
                    selectedDate = date
                    presentedTimelineAgenda = CalendarAgendaSelection(
                        date: date,
                        events: allDayEvents(on: date).map(calendarAgendaDisplayItem)
                    )
                }
            )
        }
    }

    private var monthView: some View {
        #if os(macOS)
        return desktopMonthView
        #else
        let first = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        let monthNumber = calendar.component(.month, from: first)
        let days = monthGridDates(containing: first)
        let daySnapshots = cachedDaySnapshots(for: days, scope: "month").days
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7)
        return VStack(alignment: .leading, spacing: 12) {
            #if !os(macOS)
            HStack {
                Spacer()
                Button {
                    withAnimation(Self.monthExpansionAnimation) {
                        isMonthExpanded.toggle()
                    }
                } label: {
                    Label(
                        isMonthExpanded ? "折叠月历" : "展开日程",
                        systemImage: isMonthExpanded ? "chevron.up" : "chevron.down"
                    )
                }
                .buttonStyle(.bordered)
            }
            #endif
            ZStack {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Self.weekdayLabels, id: \.self) { label in
                        Text(model.localized(label))
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(daySnapshots) { snapshot in
                        monthDayButton(snapshot, monthNumber: monthNumber)
                    }
                }
                .id(monthGridIdentity)
                .transition(monthPageTransition)
            }
            .animation(Self.pageAnimation, value: monthGridIdentity)
            selectedDaySummary(selectedDate)
            assignmentSummary
            Divider()
            if model.almanacEnabled {
                almanacSummary
            }
            if model.hasCalendarDeadlinesToDisplay {
                deadlineSummary
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(periodSwipeGesture)
        #endif
    }

    #if os(macOS)
    private var desktopMonthView: some View {
        let first = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        let monthNumber = calendar.component(.month, from: first)
        let days = monthGridDates(containing: first)
        let daySnapshots = cachedDaySnapshots(for: days, scope: "month").days
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7)

        return GeometryReader { proxy in
            let weekdayHeight: CGFloat = 30
            let availableGridHeight = max(proxy.size.height - weekdayHeight, 0)
            let cellHeight = max(floor(availableGridHeight / 6), 70)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack(alignment: .top) {
                            LazyVGrid(columns: columns, spacing: 0) {
                                ForEach(Self.weekdayLabels, id: \.self) { label in
                                    Text(model.localized("周") + model.localized(label))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .frame(maxWidth: .infinity, minHeight: weekdayHeight)
                                        .overlay(alignment: .bottom) {
                                            Rectangle()
                                                .fill(AppTheme.border)
                                                .frame(height: 0.5)
                                        }
                                }

                                ForEach(daySnapshots) { snapshot in
                                    desktopMonthDay(
                                        snapshot,
                                        monthNumber: monthNumber,
                                        cellHeight: cellHeight
                                    )
                                }
                            }
                            .id(monthGridIdentity)
                            .transition(monthPageTransition)
                        }
                        .animation(Self.pageAnimation, value: monthGridIdentity)
                        .overlay {
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: 0.5)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: max(proxy.size.height, 520), alignment: .top)

                    Surface { selectedDaySummary(selectedDate) }
                    Surface { assignmentSummary }
                    if model.almanacEnabled {
                        Surface { almanacSummary }
                    }
                    if model.hasCalendarDeadlinesToDisplay {
                        Surface { deadlineSummary }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(periodSwipeGesture)
        .accessibilityIdentifier("calendar.desktop.month-grid")
    }

    private func desktopMonthDay(
        _ snapshot: CalendarMonthDaySnapshot,
        monthNumber: Int,
        cellHeight: CGFloat
    ) -> some View {
        let day = snapshot.date
        let events = desktopMonthEvents(snapshot)
        let maximumRows = cellHeight >= 100 ? 4 : (cellHeight >= 80 ? 3 : 2)
        let layout = TeachingCalendarLogic.monthEventLayout(
            totalCount: events.count,
            maximumRows: maximumRows
        )
        let isSelected = sameDay(day, selectedDate)
        let isToday = sameDay(day, .now)
        let deadlineKinds = snapshot.deadlineKinds
        let inMonth = snapshot.month == monthNumber

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 5) {
                if snapshot.weekday == 2 {
                    Text(monthWeekContextText(date: day))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .accessibilityIdentifier("calendar.desktop.month-week-context.\(snapshot.dateKey)")
                }
                Spacer(minLength: 4)
                desktopMonthDayBadge(
                    dayNumber: snapshot.dayNumber,
                    isSelected: isSelected,
                    isToday: isToday,
                    inMonth: inMonth
                )
            }
            .frame(height: 22)

            ForEach(Array(events.prefix(layout.visibleEventCount))) { event in
                desktopMonthEventRow(event)
            }

            if layout.hiddenEventCount > 0 {
                Button {
                    selectMonthDay(day)
                } label: {
                    Text("+\(layout.hiddenEventCount) 项")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .frame(height: 15)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    model.localizedFormat("查看其余 %lld 项全天日程", layout.hiddenEventCount)
                )
                .accessibilityIdentifier(
                    "calendar.regular.month-overflow.\(snapshot.dateKey)"
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(
            maxWidth: .infinity,
            minHeight: cellHeight,
            maxHeight: cellHeight,
            alignment: .topLeading
        )
        .background(
            isSelected
                ? AppTheme.selectedDate.opacity(0.14)
                : (inMonth ? Color.clear : AppTheme.surface.opacity(0.28))
        )
        .overlay {
            ZStack {
                Rectangle()
                    .stroke(AppTheme.border, lineWidth: 0.5)
                if let outerKind = deadlineKinds.first {
                    Rectangle()
                        .stroke(allDayEventTint(outerKind), lineWidth: 1.5)
                        .padding(1)
                }
                if deadlineKinds.count > 1 {
                    Rectangle()
                        .stroke(allDayEventTint(deadlineKinds[1]), lineWidth: 1)
                        .padding(4)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectMonthDay(day) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dayAccessibilityLabel(snapshot, isToday: isToday))
        .accessibilityValue(snapshot.deadlineAccessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendar.regular.month-day-cell.\(snapshot.dateKey)")
        .accessibilityAction { selectMonthDay(day) }
    }

    private func desktopMonthDayBadge(
        dayNumber: Int,
        isSelected: Bool,
        isToday: Bool,
        inMonth: Bool
    ) -> some View {
        Text("\(dayNumber)")
            .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .medium))
            .monospacedDigit()
            .foregroundStyle(
                isSelected || isToday
                    ? AppTheme.onPrimary
                    : (inMonth ? AppTheme.text : AppTheme.secondaryText.opacity(0.55))
            )
            .frame(minWidth: 22, minHeight: 22)
            .background {
                ZStack {
                    if isSelected {
                        Circle().fill(AppTheme.selectedDate)
                    } else if isToday {
                        Circle().fill(Self.nowRed)
                    }
                    if isSelected, isToday {
                        Circle().stroke(Self.nowRed, lineWidth: 2)
                    }
                }
            }
    }

    private func desktopMonthEventRow(_ event: DesktopMonthEvent) -> some View {
        let tint = desktopMonthEventTint(event.kind)
        return HStack(spacing: 4) {
            if event.kind != .course {
                Image(systemName: desktopMonthEventSystemImage(event.kind))
                    .font(.system(size: 7, weight: .semibold))
            }
            Text(event.title)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let time = event.time {
                Text(time)
                    .font(.system(size: 8, weight: .medium))
                    .monospacedDigit()
                    .opacity(0.82)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 15, maxHeight: 15, alignment: .leading)
        .background(tint.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityIdentifier("calendar.desktop.month-event.\(event.id)")
    }

    private func desktopMonthEvents(_ snapshot: CalendarMonthDaySnapshot) -> [DesktopMonthEvent] {
        let dateKey = snapshot.dateKey
        let holidayEvents = snapshot.holidays.map { holiday in
            DesktopMonthEvent(
                id: "\(dateKey)|holiday|\(holiday.id)",
                title: "\(model.localized(holiday.type == "holiday" ? "休" : "班")) \(holiday.name)",
                time: nil,
                kind: holiday.type == "holiday" ? .holiday : .workday
            )
        }
        let assignmentEvents = snapshot.assignments.map { assignment in
            DesktopMonthEvent(
                id: "\(dateKey)|assignment|\(assignment.id)",
                title: assignment.title,
                time: deadlineTime(assignment.deadline),
                kind: .assignment
            )
        }
        let schoolNoticeEvents = snapshot.schoolNotices.map { notice in
            DesktopMonthEvent(
                id: "\(dateKey)|school|\(notice.id)",
                title: notice.name,
                time: deadlineTime(notice.deadline),
                kind: .schoolNotice,
                deadlineItem: notice
            )
        }
        let publicDeadlineEvents = snapshot.publicDeadlines.map { item in
            DesktopMonthEvent(
                id: "\(dateKey)|public|\(item.id)",
                title: item.name,
                time: deadlineTime(item.deadline),
                kind: desktopMonthEventKind(for: item),
                deadlineItem: item
            )
        }
        let courseEvents = snapshot.courses.map { course in
            DesktopMonthEvent(
                id: "\(dateKey)|course|\(course.id)",
                title: course.name,
                time: course.timeRange.split(separator: "-").first.map(String.init),
                kind: .course
            )
        }
        return holidayEvents
            + assignmentEvents
            + schoolNoticeEvents
            + publicDeadlineEvents
            + courseEvents
    }

    private func desktopMonthEventTint(_ kind: DesktopMonthEvent.Kind) -> Color {
        switch kind {
        case .course:
            return AppTheme.primary
        case .holiday:
            return Self.holidayRed
        case .workday:
            return AppTheme.accent
        case .assignment:
            return AppTheme.assignment
        case .schoolNotice:
            return AppTheme.schoolNotice
        case .competition:
            return AppTheme.competitionDeadline
        case .conference:
            return AppTheme.conferenceDeadline
        case .summerCamp:
            return AppTheme.summerCampDeadline
        case .hackathon:
            return AppTheme.hackathonDeadline
        case .customDeadline:
            return AppTheme.customDeadline
        }
    }

    private func desktopMonthEventSystemImage(_ kind: DesktopMonthEvent.Kind) -> String {
        switch kind {
        case .course: "book.closed.fill"
        case .holiday: "star.fill"
        case .workday: "briefcase.fill"
        case .assignment: "doc.text.fill"
        case .schoolNotice: "building.columns.fill"
        case .competition, .conference, .summerCamp, .hackathon, .customDeadline:
            "flag.checkered"
        }
    }

    private func desktopMonthEventKind(for item: PublicDeadlineItem) -> DesktopMonthEvent.Kind {
        if item.source == .schoolNotice { return .schoolNotice }
        if item.source == .custom { return .customDeadline }
        switch item.kind {
        case .competition: return .competition
        case .conference, .journalSpecialIssue: return .conference
        case .summerCamp, .preAdmission: return .summerCamp
        case .hackathon: return .hackathon
        case .custom: return .customDeadline
        }
    }
    #endif

    private func monthDayButton(
        _ snapshot: CalendarMonthDaySnapshot,
        monthNumber: Int
    ) -> some View {
        let day = snapshot.date
        let dayCourses = snapshot.courses
        let holidays = snapshot.holidays
        let assignments = snapshot.assignments
        let schoolNotices = snapshot.schoolNotices
        let publicDeadlines = snapshot.publicDeadlines
        let deadlineEvents: [CalendarMonthDeadlineEvent] = assignments.map { item in
            CalendarMonthDeadlineEvent(
                id: "assignment-\(item.id)",
                title: item.title,
                categoryKey: "课程作业 DDL",
                agendaKind: .assignment,
                tint: AppTheme.assignment
            )
        } + schoolNotices.map { item in
            CalendarMonthDeadlineEvent(
                id: "school-\(item.id)",
                title: item.name,
                categoryKey: "校内竞赛通知",
                agendaKind: .schoolNotice,
                tint: AppTheme.schoolNotice,
                deadlineItem: item
            )
        } + publicDeadlines.map { item in
            CalendarMonthDeadlineEvent(
                id: "public-\(item.id)",
                title: item.name,
                categoryKey: item.kind.title,
                agendaKind: calendarAgendaKind(for: item),
                tint: CalendarDeadlinePresentation.tint(for: item),
                deadlineItem: item
            )
        }
        let isSelected = sameDay(day, selectedDate)
        let isToday = sameDay(day, .now)
        let deadlineKinds = snapshot.deadlineKinds
        let inMonth = snapshot.month == monthNumber
        #if os(macOS)
        let showsDetails = true
        #else
        let showsDetails = isMonthExpanded
        #endif
        let detail: String
        let detailTint: Color
        if let holiday = holidays.first {
            detail = "\(model.localized(holiday.type == "holiday" ? "休" : "班")) \(holiday.name)"
            detailTint = Self.holidayColor(holiday)
        } else {
            detail = dayCourses.isEmpty ? "无课" : "\(dayCourses.count) 门课"
            detailTint = monthTextColor(
                selected: isSelected,
                inMonth: inMonth,
                holidays: holidays
            )
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(isToday ? "今天 \(snapshot.dayNumber)" : "\(snapshot.dayNumber)")
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if showsDetails {
                if deadlineEvents.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, weight: holidays.isEmpty ? .regular : .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .foregroundStyle(isSelected ? AppTheme.onPrimary : detailTint)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(deadlineEvents.prefix(3))) { event in
                            Text(event.title)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? AppTheme.onPrimary : event.tint)
                                .frame(maxWidth: .infinity, minHeight: 13, alignment: .leading)
                        }
                        if deadlineEvents.count > 3 {
                            Button {
                                selectMonthDay(day)
                            } label: {
                                Text("+\(deadlineEvents.count - 3)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(
                                        isSelected ? AppTheme.onPrimary : AppTheme.secondaryText
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                model.localizedFormat(
                                    "查看其余 %lld 项全天日程",
                                    deadlineEvents.count - 3
                                )
                            )
                        }
                    }
                }
            } else {
                HStack(spacing: 3) {
                    if !holidays.isEmpty {
                        Circle().frame(width: 4, height: 4)
                    }
                    ForEach(Array(deadlineEvents.prefix(3))) { event in
                        Circle()
                            .fill(isSelected ? AppTheme.onPrimary : event.tint)
                            .frame(width: 4, height: 4)
                    }
                    ForEach(0 ..< min(dayCourses.count, 3), id: \.self) { _ in
                        Circle().frame(width: 4, height: 4)
                    }
                }
                .frame(height: 8)
                .transition(.opacity)
            }
        }
        .foregroundStyle(monthTextColor(selected: isSelected, inMonth: inMonth, holidays: holidays))
        .padding(6)
        .frame(
            maxWidth: .infinity,
            minHeight: showsDetails ? 94 : 46,
            alignment: .topLeading
        )
        .background(monthCellColor(selected: isSelected, inMonth: inMonth, courseCount: dayCourses.count))
        .overlay {
            ZStack {
                if let outerKind = deadlineKinds.first {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(allDayEventTint(outerKind), lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                if deadlineKinds.count > 1 {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(allDayEventTint(deadlineKinds[1]), lineWidth: 1)
                        .padding(3)
                }
                if isToday {
                    Circle()
                        .fill(Self.nowRed)
                        .frame(width: 6, height: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { selectMonthDay(day) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dayAccessibilityLabel(snapshot, isToday: isToday))
        .accessibilityValue(snapshot.deadlineAccessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendar.regular.month-day-cell.\(snapshot.dateKey)")
        .accessibilityAction { selectMonthDay(day) }
    }

    private var yearView: some View {
        let yearDays = TeachingCalendarLogic.datesInYear(
            containing: selectedDate,
            calendar: calendar
        )
        let snapshots = cachedDaySnapshots(for: yearDays, scope: "year")
        #if os(macOS)
        return desktopYearView(snapshotsByMonth: snapshots.byMonth)
        #else
        let snapshotsByDate = snapshots.byDate
        let year = calendar.component(.year, from: selectedDate)
        let months = (1 ... 12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }
        let monthTitleFormatter = monthFormatter
        let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 14)]
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(months, id: \.self) { month in
                    miniMonth(
                        month,
                        title: monthTitleFormatter.string(from: month),
                        snapshotsByDate: snapshotsByDate
                    )
                }
            }
        }
        #endif
    }

    #if os(macOS)
    private func desktopYearView(
        snapshotsByMonth: [Int: [CalendarMonthDaySnapshot]]
    ) -> some View {
        let year = calendar.component(.year, from: selectedDate)
        let months = (1 ... 12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }
        let monthTitleFormatter = monthFormatter
        let todayKey = StrictContractDateParser.string(from: .now)
        let selectedKey = StrictContractDateParser.string(from: selectedDate)

        return GeometryReader { proxy in
            let layout = TeachingCalendarLogic.desktopYearLayout(availableHeight: proxy.size.height)
            let columns = Array(
                repeating: GridItem(.flexible(minimum: 120), spacing: layout.columnSpacing),
                count: 4
            )

            LazyVGrid(columns: columns, alignment: .leading, spacing: layout.rowSpacing) {
                ForEach(months, id: \.self) { month in
                    let monthNumber = calendar.component(.month, from: month)
                    desktopMiniMonth(
                        title: monthTitleFormatter.string(from: month),
                        layout: layout,
                        snapshots: snapshotsByMonth[monthNumber] ?? [],
                        todayKey: todayKey,
                        selectedKey: selectedKey
                    )
                }
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("calendar.desktop.year-grid")
    }

    private func desktopMiniMonth(
        title: String,
        layout: TeachingCalendarLogic.DesktopYearLayout,
        snapshots: [CalendarMonthDaySnapshot],
        todayKey: String,
        selectedKey: String
    ) -> some View {
        return VStack(alignment: .leading, spacing: layout.monthContentSpacing) {
            Text(title)
                .font(.system(size: layout.monthTitleFontSize, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(height: layout.monthTitleHeight, alignment: .leading)

            VStack(spacing: layout.gridSpacing) {
                HStack(spacing: layout.gridSpacing) {
                    ForEach(Self.weekdayLabels, id: \.self) { label in
                        Text(model.localized(label))
                            .font(.system(size: layout.weekdayFontSize, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: layout.weekdayHeight,
                                maxHeight: layout.weekdayHeight
                            )
                    }
                }

                GeometryReader { proxy in
                    let cellWidth = max(
                        (proxy.size.width - layout.gridSpacing * 6) / 7,
                        0
                    )
                    let firstWeekday = snapshots.first?.weekday ?? 2

                    ZStack(alignment: .topLeading) {
                        ForEach(snapshots) { snapshot in
                            let position = TeachingCalendarLogic.monthGridPosition(
                                dayNumber: snapshot.dayNumber,
                                firstWeekday: firstWeekday
                            )
                            desktopYearDay(
                                snapshot,
                                layout: layout,
                                isToday: snapshot.dateKey == todayKey,
                                isSelected: snapshot.dateKey == selectedKey
                            )
                                .frame(width: cellWidth, height: layout.dayCellHeight)
                                .offset(
                                    x: CGFloat(position.column) * (cellWidth + layout.gridSpacing),
                                    y: CGFloat(position.row) * (layout.dayCellHeight + layout.gridSpacing)
                                )
                        }
                    }
                    .frame(
                        width: proxy.size.width,
                        height: layout.dayCellHeight * 6 + layout.gridSpacing * 5,
                        alignment: .topLeading
                    )
                }
                .frame(height: layout.dayCellHeight * 6 + layout.gridSpacing * 5)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: layout.monthHeight,
            maxHeight: layout.monthHeight,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private func desktopYearDay(
        _ snapshot: CalendarMonthDaySnapshot,
        layout: TeachingCalendarLogic.DesktopYearLayout,
        isToday: Bool,
        isSelected: Bool
    ) -> some View {
        let day = snapshot.date
        let dayCourses = snapshot.courses
        let holidays = snapshot.holidays
        let deadlineKinds = snapshot.deadlineKinds
        let baseColor = dayCourses.isEmpty
            ? Color.clear
            : AppTheme.primary.opacity(
                TeachingCalendarLogic.yearCourseOpacity(courseCount: dayCourses.count)
            )

        let cell = VStack(spacing: 0) {
            Text("\(snapshot.dayNumber)")
                .monospacedDigit()
            if let item = holidays.first {
                Text(model.localized(item.type == "holiday" ? "休" : "班"))
                    .font(.system(size: layout.holidayFontSize, weight: .semibold))
                    .foregroundStyle(
                        isSelected || isToday ? AppTheme.onPrimary : Self.holidayColor(item)
                    )
            }
        }
        .font(.system(size: layout.dayFontSize, weight: .medium))
        .foregroundStyle(
            isSelected || isToday
                ? AppTheme.onPrimary
                : (dayCourses.isEmpty ? AppTheme.text : AppTheme.onPrimary)
        )
        .frame(
            maxWidth: .infinity,
            minHeight: layout.dayCellHeight,
            maxHeight: layout.dayCellHeight
        )
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(baseColor)
                if isSelected {
                    Circle()
                        .fill(AppTheme.selectedDate)
                        .frame(
                            width: layout.selectionDiameter,
                            height: layout.selectionDiameter
                        )
                } else if isToday {
                    Circle()
                        .fill(Self.nowRed)
                        .frame(
                            width: layout.selectionDiameter,
                            height: layout.selectionDiameter
                        )
                }
            }
        }
        .overlay {
            ZStack {
                if let outerKind = deadlineKinds.first {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(allDayEventTint(outerKind), lineWidth: 1.5)
                }
                if deadlineKinds.count > 1 {
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(allDayEventTint(deadlineKinds[1]), lineWidth: 1)
                        .padding(2.5)
                }
                if isSelected, isToday {
                    Circle()
                        .stroke(Self.nowRed, lineWidth: 1)
                        .frame(
                            width: layout.selectionDiameter - 3,
                            height: layout.selectionDiameter - 3
                        )
                }
            }
        }
        .contentShape(Rectangle())

        let interactiveCell = cell
            .gesture(
                SpatialTapGesture(
                    count: 2,
                    coordinateSpace: .named(Self.calendarCoordinateSpace)
                )
                .exclusively(
                    before: SpatialTapGesture(
                        count: 1,
                        coordinateSpace: .named(Self.calendarCoordinateSpace)
                    )
                )
                .onEnded { value in
                    switch value {
                    case .first:
                        changeMode(to: .month, selecting: day)
                    case let .second(tap):
                        selectedDate = day
                        yearPopoverDate = day
                        yearPopoverLocation = tap.location
                    }
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dayAccessibilityLabel(snapshot, isToday: isToday))
            .accessibilityValue(snapshot.deadlineAccessibilityValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("calendar.desktop.year-day.\(snapshot.dateKey)")
            .accessibilityAction {
                selectedDate = day
                yearPopoverDate = day
                yearPopoverLocation = nil
            }
            .accessibilityAction(named: Text("查看月份")) {
                changeMode(to: .month, selecting: day)
            }

        if isSelected {
            interactiveCell
                .popover(
                    isPresented: yearPopoverBinding(for: day),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: nil
                ) {
                    desktopYearPopoverPanel(day, width: 320, height: 360)
                }
        } else {
            interactiveCell
        }
    }
    #endif

    private func miniMonth(
        _ month: Date,
        title: String,
        snapshotsByDate: [String: CalendarMonthDaySnapshot]
    ) -> some View {
        let days = monthGridDates(containing: month)
        let monthNumber = calendar.component(.month, from: month)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: 7)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Self.weekdayLabels, id: \.self) { label in
                    Text(model.localized(label))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                ForEach(days, id: \.self) { day in
                    yearDayButton(
                        day,
                        monthNumber: monthNumber,
                        snapshot: snapshotsByDate[StrictContractDateParser.string(from: day)]
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func yearDayButton(
        _ day: Date,
        monthNumber: Int,
        snapshot: CalendarMonthDaySnapshot?
    ) -> some View {
        if let snapshot, snapshot.month == monthNumber {
            let dayCourses = snapshot.courses
            let holidays = snapshot.holidays
            let isToday = sameDay(day, .now)
            let deadlineKinds = snapshot.deadlineKinds
            let isSelected = sameDay(selectedDate, day)
            let cell = VStack(spacing: 0) {
                Text("\(snapshot.dayNumber)")
                if let item = holidays.first {
                    Text(model.localized(item.type == "holiday" ? "休" : "班"))
                        .foregroundStyle(isSelected ? AppTheme.onPrimary : Self.holidayColor(item))
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.text)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(yearCellColor(selected: isSelected, courseCount: dayCourses.count))
            .overlay {
                ZStack {
                    if let outerKind = deadlineKinds.first {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(allDayEventTint(outerKind), lineWidth: 1.5)
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                    if deadlineKinds.count > 1 {
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(allDayEventTint(deadlineKinds[1]), lineWidth: 1)
                            .padding(2.5)
                    }
                    if isToday {
                        Circle()
                            .fill(Self.nowRed)
                            .frame(width: 5, height: 5)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .topTrailing
                            )
                            .padding(2.5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dayAccessibilityLabel(snapshot, isToday: isToday))
            .accessibilityValue(snapshot.deadlineAccessibilityValue)
            .accessibilityAddTraits(.isButton)
            #if os(macOS)
            cell
                .accessibilityAction {
                    selectedDate = day
                    yearPopoverDate = day
                    yearPopoverLocation = nil
                }
                .accessibilityAction(named: Text("查看月份")) {
                    changeMode(to: .month, selecting: day)
                }
                .gesture(
                    SpatialTapGesture(
                        count: 2,
                        coordinateSpace: .named(Self.calendarCoordinateSpace)
                    )
                    .exclusively(
                        before: SpatialTapGesture(
                            count: 1,
                            coordinateSpace: .named(Self.calendarCoordinateSpace)
                        )
                    )
                    .onEnded { value in
                        switch value {
                        case .first:
                            changeMode(to: .month, selecting: day)
                        case let .second(tap):
                            selectedDate = day
                            yearPopoverDate = day
                            yearPopoverLocation = tap.location
                        }
                    }
                )
            #else
            cell
            .accessibilityAction {
                yearPopoverDate = day
                yearPopoverLocation = nil
            }
            .gesture(
                SpatialTapGesture(coordinateSpace: .named(Self.calendarCoordinateSpace))
                    .onEnded { value in
                        yearPopoverDate = day
                        yearPopoverLocation = value.location
                    }
            )
            #endif
        } else {
            Color.clear.frame(height: 30)
        }
    }

    @ViewBuilder
    private var yearPopoverOverlay: some View {
        if let day = yearPopoverDate {
            GeometryReader { proxy in
                let panelWidth = min(300, max(220, proxy.size.width - 32))
                let panelHeight = estimatedYearPopoverHeight(day, availableHeight: proxy.size.height)
                let fallback = CGPoint(x: proxy.size.width / 2, y: min(220, proxy.size.height / 2))
                let location = yearPopoverLocation ?? fallback
                let placement = TeachingCalendarLogic.yearPopoverPlacement(
                    anchor: location,
                    panelSize: CGSize(width: panelWidth, height: panelHeight),
                    containerSize: proxy.size
                )

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismissYearPopover)

                    ScrollView(.vertical) {
                        selectedDayPopover(day)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.visible)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("年视图日期详情滚动区")
                    .accessibilityIdentifier("calendar.desktop.year-popover-scroll")
                    .frame(
                        width: panelWidth - 32,
                        height: panelHeight - 32,
                        alignment: .topLeading
                    )
                    .padding(16)
                    .background(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color.black.opacity(0.18), radius: 12, y: 5)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("年视图日期详情")
                    .accessibilityIdentifier("calendar.desktop.year-popover")
                    .offset(x: placement.origin.x, y: placement.origin.y)
                }
            }
            .zIndex(20)
        }
    }

    #if os(macOS)
    private func desktopYearPopoverPanel(
        _ day: Date,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("日期详情")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer(minLength: 8)
                    Text(
                        yearPopoverScrollTarget == Self.yearPopoverBottomID
                            ? "底部"
                            : "顶部"
                    )
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("calendar.desktop.year-popover-position")
                    Button {
                        yearPopoverScrollTarget = Self.yearPopoverTopID
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                    }
                    .buttonStyle(.bordered)
                    .help("滚动到顶部")
                    .accessibilityIdentifier("calendar.desktop.year-popover-top")
                    Button {
                        yearPopoverScrollTarget = Self.yearPopoverBottomID
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .buttonStyle(.bordered)
                    .help("滚动到底部")
                    .accessibilityIdentifier("calendar.desktop.year-popover-bottom")
                    Button {
                        dismissYearPopover()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .help("关闭日期详情")
                    .accessibilityIdentifier("calendar.desktop.year-popover-close")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 1)
                            .id(Self.yearPopoverTopID)
                        selectedDayPopover(day)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                        Color.clear
                            .frame(height: 1)
                            .id(Self.yearPopoverBottomID)
                    }
                }
                .scrollIndicators(.visible)
                .accessibilityLabel("年视图日期详情滚动区")
                .accessibilityIdentifier("calendar.desktop.year-popover-scroll")
            }
            .onChange(of: yearPopoverScrollTarget) { target in
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(
                        target,
                        anchor: target == Self.yearPopoverBottomID ? .bottom : .top
                    )
                }
            }
        }
        .frame(width: width, height: height)
        .background(AppTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("年视图日期详情")
        .accessibilityIdentifier("calendar.desktop.year-popover")
    }
    #endif

    private func selectedDayPopover(_ day: Date) -> some View {
        let dayCourses = courses(on: day)
        let holidays = holidayItems(on: day)
        let assignments = assignmentItems(on: day)
        let schoolNotices = schoolNoticeItems(on: day)
        let publicDeadlines = otherPublicDeadlineItems(on: day)
        return VStack(alignment: .leading, spacing: 10) {
            Text(fullDateFormatter.string(from: day)).font(.headline)
            ForEach(holidays) { item in
                Text("\(model.localized(item.type == "holiday" ? "休" : "班")) \(item.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Self.holidayColor(item))
            }
            if dayCourses.isEmpty {
                Text("暂无课程").foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(dayCourses) { course in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name).font(.subheadline.weight(.semibold))
                        Text(
                            [course.timeRange, CalendarTimelineLogic.courseMetadata(course)]
                                .filter { !$0.isEmpty }
                                .joined(separator: "  ·  ")
                        )
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            if !assignments.isEmpty {
                compactAssignmentRows(assignments)
            }
            if !schoolNotices.isEmpty {
                compactSchoolNoticeRows(schoolNotices)
            }
            if !publicDeadlines.isEmpty {
                compactPublicDeadlineRows(publicDeadlines)
            }
            Divider()
            HStack(spacing: 8) {
                yearPopoverNavigationButton("日", mode: .day, day: day)
                yearPopoverNavigationButton("周", mode: .week, day: day)
                yearPopoverNavigationButton("月", mode: .month, day: day)
            }
        }
    }

    private func yearPopoverNavigationButton(
        _ title: String,
        mode targetMode: CalendarMode,
        day: Date
    ) -> some View {
        Button(model.localized("\(title)视图")) {
            changeMode(to: targetMode, selecting: day)
            dismissYearPopover()
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private func selectedDaySummary(_ day: Date) -> some View {
        let dayCourses = courses(on: day)
        return VStack(alignment: .leading, spacing: 8) {
            Text(fullDateFormatter.string(from: day)).font(.headline)
            if dayCourses.isEmpty {
                Text("暂无课程").foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(dayCourses) { course in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(course.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(course.timeRange).font(.caption.monospacedDigit())
                        }
                        let metadata = CalendarTimelineLogic.courseMetadata(course)
                        if !metadata.isEmpty {
                            Text(metadata)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
        .accessibilityIdentifier("calendar.regular.selected-day-courses")
    }

    private func compactAssignmentRows(_ items: [AssignmentDeadlineItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("课程作业 DDL", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.assignment)
            ForEach(items) { item in
                Link(destination: CalendarDeadlineSources.assignments) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(deadlineTime(item.deadline))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(AppTheme.assignment.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityIdentifier("calendar.regular.day-detail.assignments")
    }

    private func compactSchoolNoticeRows(_ items: [PublicDeadlineItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("校内竞赛通知", systemImage: "building.columns")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.schoolNotice)
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    if let destination = item.officialURL {
                        Link(destination: destination) {
                            compactDeadlineContent(item)
                        }
                        .buttonStyle(.plain)
                    } else {
                        compactDeadlineContent(item)
                    }
                    Text(deadlineTime(item.deadline))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                    favoriteButton(item)
                }
            }
        }
        .padding(9)
        .background(AppTheme.schoolNotice.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityIdentifier("calendar.regular.day-detail.school-notices")
    }

    private func compactPublicDeadlineRows(_ items: [PublicDeadlineItem]) -> some View {
        let kinds = CalendarDeadlinePresentation.topTwoDeadlineKinds(
            in: items.map { item in
                CalendarAllDayEvent(
                    id: item.favoriteID,
                    title: item.name,
                    kind: CalendarDeadlinePresentation.eventKind(for: item)
                )
            }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Label("公开活动 DDL", systemImage: "flag.checkered")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    if let destination = item.officialURL {
                        Link(destination: destination) {
                            compactDeadlineContent(item)
                        }
                        .buttonStyle(.plain)
                    } else {
                        compactDeadlineContent(item)
                    }
                    Text(deadlineTime(item.deadline))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                    favoriteButton(item)
                }
            }
        }
        .padding(9)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            ZStack {
                if let first = kinds.first {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(allDayEventTint(first).opacity(0.65), lineWidth: 1.5)
                }
                if kinds.count > 1 {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(allDayEventTint(kinds[1]).opacity(0.65), lineWidth: 1)
                        .padding(3)
                }
            }
        }
        .accessibilityIdentifier("calendar.regular.day-detail.public-deadlines")
    }

    private func compactDeadlineContent(_ item: PublicDeadlineItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .font(.subheadline.weight(.semibold))
            Text(deadlineCategoryTitle(item))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var almanacSummary: some View {
        let date = StrictContractDateParser.string(from: selectedDate)
        VStack(alignment: .leading, spacing: 10) {
            Label("黄历信息", systemImage: "calendar.badge.clock")
                .font(.headline)
            if dailyInfo.loadingAlmanacDates.contains(date), dailyInfo.almanacByDate[date] == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在查询…")
                }
                .foregroundStyle(AppTheme.secondaryText)
            } else if let error = dailyInfo.almanacErrors[date], dailyInfo.almanacByDate[date] == nil {
                Button {
                    Task {
                        await dailyInfo.loadAlmanac(date: date, sampleMode: model.isSampleMode, force: true)
                    }
                } label: {
                    Label("\(error)，点击重试", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.bordered)
            } else if let info = dailyInfo.almanacByDate[date] {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        almanacDateBlock(info)
                        almanacPill("岁次", value: "\(info.ganzhiYear)年 · 肖\(info.zodiac)")
                        almanacPill("月柱", value: "\(info.ganzhiMonth)月")
                        almanacPill("日柱", value: "\(info.ganzhiDay)日")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        almanacDateBlock(info)
                        HStack(spacing: 8) {
                            almanacPill("岁次", value: "\(info.ganzhiYear)年 · 肖\(info.zodiac)")
                            almanacPill("月柱", value: "\(info.ganzhiMonth)月")
                            almanacPill("日柱", value: "\(info.ganzhiDay)日")
                        }
                    }
                }
                if let yi = info.yi {
                    almanacAdvice("宜", value: yi, color: AppTheme.primary)
                }
                if let ji = info.ji {
                    almanacAdvice("忌", value: ji, color: AppTheme.danger)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("民俗信息仅供参考")
                    Spacer()
                    Link("农历：UAPI", destination: URL(string: "https://uapis.cn/docs/api-reference/get-misc-lunartime")!)
                    Link("宜忌：Timeless", destination: URL(string: "https://api.timelessq.com/docs/api-15277838")!)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("民俗信息仅供参考")
                    HStack {
                        Link("农历：UAPI", destination: URL(string: "https://uapis.cn/docs/api-reference/get-misc-lunartime")!)
                        Link("宜忌：Timeless", destination: URL(string: "https://api.timelessq.com/docs/api-15277838")!)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
            Text("校内竞赛通知由脚本从学校内部网站公开通知页提取整理，仅供参考。")
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func almanacAdvice(_ title: String, value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            Text(value)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var assignmentSummary: some View {
        let date = StrictContractDateParser.string(from: selectedDate)
        let items = calendarDeadlines.assignmentsByDate[date] ?? []
        VStack(alignment: .leading, spacing: 10) {
            Label("课程作业 DDL", systemImage: "checklist")
                .font(.headline)
            if items.isEmpty {
                if let reason = calendarDeadlines.assignmentUnavailableByDate[date] {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text("当天没有课程作业截止事项")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(
                                [item.courseName, item.status]
                                    .compactMap { $0 }
                                    .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Text(deadlineTime(item.deadline))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(10)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack {
                Text("第三方来源：北京邮电大学云课堂")
                Spacer()
                Link("打开作业列表", destination: CalendarDeadlineSources.assignments)
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    @ViewBuilder
    private var deadlineSummary: some View {
        let date = StrictContractDateParser.string(from: selectedDate)
        let builtInSnapshot = calendarDeadlines.publicByDate[date]
        let customSnapshot = calendarDeadlines.customByDate[date]
        let items = model.visibleDeadlineItems(
            liveItems: calendarDeadlines.publicItems(for: date),
            on: date
        )
        let isLoading = calendarDeadlines.loadingPublicDates.contains(date)
            || calendarDeadlines.loadingCustomDates.contains(date)
        let error = calendarDeadlines.publicErrors[date] ?? calendarDeadlines.customErrors[date]
        VStack(alignment: .leading, spacing: 10) {
            Label("活动 DDL", systemImage: "flag.checkered")
                .font(.headline)
            if isLoading, builtInSnapshot == nil, customSnapshot == nil, items.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在同步竞赛、夏令营与黑客松…")
                }
                .foregroundStyle(AppTheme.secondaryText)
            } else if let error, builtInSnapshot == nil, customSnapshot == nil, items.isEmpty {
                Button {
                    Task {
                        if model.hasEnabledBuiltInPublicDeadlines {
                            await calendarDeadlines.loadPublic(
                                date: date,
                                sampleMode: model.isSampleMode,
                                force: true
                            )
                        }
                        if let sourceURL = model.customDeadlineSourceURL {
                            await calendarDeadlines.loadCustom(
                                dates: [date],
                                sourceURL: sourceURL,
                                force: true
                            )
                        }
                    }
                } label: {
                    Label("\(error)，点击重试", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.bordered)
            } else if items.isEmpty {
                Text("当天没有已收录的活动截止事项")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(items) { item in
                    publicDeadlineRow(item)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("第三方来源")
                    Spacer()
                    Link("主数据：Contest DDL", destination: CalendarDeadlineSources.primaryPage)
                    Link("备用 API", destination: CalendarDeadlineSources.backup)
                    Link("校内竞赛通知", destination: CalendarDeadlineSources.schoolNotices)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("第三方来源")
                    HStack {
                        Link("主数据：Contest DDL", destination: CalendarDeadlineSources.primaryPage)
                        Link("备用 API", destination: CalendarDeadlineSources.backup)
                        Link("校内竞赛通知", destination: CalendarDeadlineSources.schoolNotices)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
            if let customItem = items.first(where: { $0.source == .custom }) {
                if let homepage = customItem.sourceHomepage {
                    Link(
                        "自定义来源：\(customItem.sourceName ?? customItem.source.title)",
                        destination: homepage
                    )
                } else {
                    Text("自定义来源：\(customItem.sourceName ?? customItem.source.title)")
                }
            }
        }
    }

    @ViewBuilder
    private func publicDeadlineRow(_ item: PublicDeadlineItem) -> some View {
        HStack(alignment: .center, spacing: 6) {
            if let url = item.officialURL {
                Link(destination: url) {
                    publicDeadlineRowContent(item)
                }
                .buttonStyle(.plain)
            } else {
                publicDeadlineRowContent(item)
            }
            favoriteButton(item)
        }
    }

    private func publicDeadlineRowContent(_ item: PublicDeadlineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(CalendarDeadlinePresentation.tint(for: item))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text([deadlineCategoryTitle(item), item.organizer].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 8)
            Text(deadlineTime(item.deadline))
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }

    private func favoriteButton(_ item: PublicDeadlineItem) -> some View {
        let isFavorite = model.isFavorite(item)
        return Button {
            AppHaptics.selection()
            model.setFavorite(item, isFavorite: !isFavorite)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFavorite ? AppTheme.accent : AppTheme.secondaryText)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "取消收藏" : "收藏日程")
        .accessibilityIdentifier("calendar.favorite.\(item.source.rawValue).\(item.id)")
    }

    private func deadlineCategoryTitle(_ item: PublicDeadlineItem) -> String {
        if item.source == .custom, let sourceName = item.sourceName {
            return "\(model.localized(item.kind.title)) · \(sourceName)"
        }
        return model.localized(item.source == .schoolNotice ? item.source.title : item.kind.title)
    }

    private func deadlineTime(_ value: String) -> String {
        guard value.count >= 16 else { return value }
        let start = value.index(value.startIndex, offsetBy: 11)
        return String(value[start...].prefix(5))
    }

    private func almanacDateBlock(_ info: AlmanacInfo) -> some View {
        let festival = [info.solarTerm, info.lunarFestival, info.solarFestival]
            .compactMap { $0 }
            .joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            Text(info.weekday).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text("农历 \(info.lunarDate)").font(.subheadline.weight(.semibold))
            if !festival.isEmpty {
                Text(festival).font(.caption2).foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
    }

    private func almanacPill(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }

    private func calendarAgendaKind(for item: PublicDeadlineItem) -> CalendarAgendaItemKind {
        if item.source == .schoolNotice { return .schoolNotice }
        if item.source == .custom { return .customDeadline }
        switch item.kind {
        case .competition: return .competition
        case .conference, .journalSpecialIssue: return .conference
        case .summerCamp, .preAdmission: return .summerCamp
        case .hackathon: return .hackathon
        case .custom: return .customDeadline
        }
    }

    private func calendarAgendaDisplayItem(
        _ event: CalendarAllDayEvent
    ) -> CalendarAgendaDisplayItem {
        let kind: CalendarAgendaItemKind = switch event.kind {
        case .holiday: .holiday
        case .workday: .workday
        case .assignment: .assignment
        case .schoolNotice: .schoolNotice
        case .competition: .competition
        case .conference: .conference
        case .summerCamp: .summerCamp
        case .hackathon: .hackathon
        case .customDeadline: .customDeadline
        }
        return CalendarAgendaDisplayItem(
            id: event.id,
            title: event.title,
            time: event.time,
            categoryKey: allDayEventCategoryKey(event.kind),
            kind: kind,
            destinationURL: event.destinationURL,
            deadlineItem: event.deadlineItem
        )
    }

    private func calendarAgendaDisplayItem(
        _ event: CalendarMonthDeadlineEvent
    ) -> CalendarAgendaDisplayItem {
        CalendarAgendaDisplayItem(
            id: event.id,
            title: event.title,
            categoryKey: event.categoryKey,
            kind: event.agendaKind,
            deadlineItem: event.deadlineItem
        )
    }

    #if os(macOS)
    private func calendarAgendaDisplayItem(
        _ event: DesktopMonthEvent
    ) -> CalendarAgendaDisplayItem {
        let kind: CalendarAgendaItemKind
        let categoryKey: String
        switch event.kind {
        case .course:
            kind = .course
            categoryKey = "课程详情"
        case .holiday:
            kind = .holiday
            categoryKey = "法定节假日"
        case .workday:
            kind = .workday
            categoryKey = "调休工作日"
        case .assignment:
            kind = .assignment
            categoryKey = "课程作业 DDL"
        case .schoolNotice:
            kind = .schoolNotice
            categoryKey = "校内竞赛通知"
        case .competition:
            kind = .competition
            categoryKey = event.deadlineItem?.kind.title ?? "学科竞赛 DDL"
        case .conference:
            kind = .conference
            categoryKey = event.deadlineItem?.kind.title ?? "学术会议/期刊专题 DDL"
        case .summerCamp:
            kind = .summerCamp
            categoryKey = event.deadlineItem?.kind.title ?? "夏令营/预推免 DDL"
        case .hackathon:
            kind = .hackathon
            categoryKey = event.deadlineItem?.kind.title ?? "黑客松 DDL"
        case .customDeadline:
            kind = .customDeadline
            categoryKey = event.deadlineItem?.kind.title ?? "自定义日程"
        }
        return CalendarAgendaDisplayItem(
            id: event.id,
            title: event.title,
            time: event.time,
            categoryKey: categoryKey,
            kind: kind,
            deadlineItem: event.deadlineItem
        )
    }
    #endif

    private func calendarAgendaTint(_ kind: CalendarAgendaItemKind) -> Color {
        switch kind {
        case .course: AppTheme.primary
        case .holiday: Self.holidayRed
        case .workday: AppTheme.primary
        case .assignment: AppTheme.assignment
        case .schoolNotice: AppTheme.schoolNotice
        case .competition: AppTheme.competitionDeadline
        case .conference: AppTheme.conferenceDeadline
        case .summerCamp: AppTheme.summerCampDeadline
        case .hackathon: AppTheme.hackathonDeadline
        case .customDeadline: AppTheme.customDeadline
        }
    }

    private func calendarAgendaDialog(
        _ selection: CalendarAgendaSelection,
        titleKey: String,
        accessibilityIdentifier: String,
        dismiss: @escaping () -> Void
    ) -> some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.localized(titleKey))
                                .font(.headline)
                            Text(fullDateFormatter.string(from: selection.date))
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.localized("关闭全天日程"))
                    }

                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(selection.events) { event in
                                let tint = calendarAgendaTint(event.kind)
                                HStack(alignment: .top, spacing: 9) {
                                    Circle()
                                        .fill(tint)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 5)
                                    if let destination = event.destinationURL
                                        ?? event.deadlineItem?.officialURL {
                                        Link(destination: destination) {
                                            calendarAgendaRowContent(event)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        calendarAgendaRowContent(event)
                                    }
                                    if let deadlineItem = event.deadlineItem {
                                        favoriteButton(deadlineItem)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    tint.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: min(360, max(proxy.size.height - 180, 140)))
                }
                .padding(16)
                .frame(maxWidth: 400)
                .background(AppTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.22), radius: 20, y: 8)
                .padding(20)
                .contentShape(Rectangle())
                .onTapGesture { }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(accessibilityIdentifier)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .zIndex(40)
    }

    private func calendarAgendaRowContent(_ event: CalendarAgendaDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if let time = event.time {
                    Text(time).monospacedDigit()
                }
                Text(model.localized(event.categoryKey))
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func allDayEventCategoryKey(_ kind: CalendarAllDayEventKind) -> String {
        CalendarDeadlinePresentation.categoryKey(for: kind)
    }

    private func allDayEventTint(_ kind: CalendarAllDayEventKind) -> Color {
        CalendarDeadlinePresentation.tint(for: kind)
    }

    private var periodTitle: String {
        TeachingCalendarLogic.periodTitle(
            for: selectedDate,
            modeRawValue: mode.rawValue,
            teachingWeekNumber: teachingWeekNumber(on: selectedDate),
            language: model.appLanguage,
            calendar: calendar
        )
    }

    private func cachedTimelineDays(for days: [Date]) -> [CalendarTimelineDay] {
        let firstDate = days.first.map { StrictContractDateParser.string(from: $0) } ?? "empty"
        let key = "\(firstDate)|\(days.count)"
        return timelineSnapshotCache.value(for: key) { days.map(timelineDay) }
    }

    private func timelineDay(_ date: Date) -> CalendarTimelineDay {
        CalendarTimelineDay(
            date: date,
            courses: courses(on: date),
            holidays: holidayItems(on: date),
            allDayEvents: allDayEvents(on: date)
        )
    }

    private func courses(on date: Date) -> [Course] {
        guard
            let schedule = model.schedule,
            let start = StrictContractDateParser.date(from: schedule.termStartDate)
        else { return [] }
        return ScheduleLogic.courses(on: date, termStart: start, courses: schedule.courses)
    }

    private func holidayItems(on date: Date) -> [HolidayItem] {
        let year = calendar.component(.year, from: date)
        let target = StrictContractDateParser.string(from: date)
        return model.holidayItems(for: year).filter { $0.date == target }
    }

    private func assignmentItems(on date: Date) -> [AssignmentDeadlineItem] {
        calendarDeadlines.assignmentsByDate[StrictContractDateParser.string(from: date)] ?? []
    }

    private func schoolNoticeItems(on date: Date) -> [PublicDeadlineItem] {
        let dateKey = StrictContractDateParser.string(from: date)
        return model.visibleDeadlineItems(
            liveItems: calendarDeadlines.publicItems(for: dateKey),
            on: dateKey
        ).filter { $0.source == .schoolNotice }
    }

    private func otherPublicDeadlineItems(on date: Date) -> [PublicDeadlineItem] {
        let dateKey = StrictContractDateParser.string(from: date)
        return model.visibleDeadlineItems(
            liveItems: calendarDeadlines.publicItems(for: dateKey),
            on: dateKey
        ).filter { $0.source != .schoolNotice }
    }

    private func allDayEvents(on date: Date) -> [CalendarAllDayEvent] {
        let dateKey = StrictContractDateParser.string(from: date)
        return calendarAllDayEvents(
            dateKey: dateKey,
            holidays: holidayItems(on: date),
            assignments: assignmentItems(on: date),
            schoolNotices: schoolNoticeItems(on: date),
            publicDeadlines: otherPublicDeadlineItems(on: date)
        )
    }

    private func calendarAllDayEvents(
        dateKey: String,
        holidays: [HolidayItem],
        assignments: [AssignmentDeadlineItem],
        schoolNotices: [PublicDeadlineItem],
        publicDeadlines: [PublicDeadlineItem]
    ) -> [CalendarAllDayEvent] {
        let holidayEvents = holidays.map { holiday in
            CalendarAllDayEvent(
                id: "\(dateKey)-holiday-\(holiday.id)",
                title: "\(model.localized(holiday.type == "holiday" ? "休" : "班")) \(holiday.name)",
                kind: holiday.type == "holiday" ? .holiday : .workday
            )
        }
        let assignmentEvents = assignments.map { assignment in
            CalendarAllDayEvent(
                id: "\(dateKey)-assignment-\(assignment.id)",
                title: assignment.title,
                time: deadlineTime(assignment.deadline),
                kind: .assignment,
                destinationURL: CalendarDeadlineSources.assignments
            )
        }
        let schoolNoticeEvents = schoolNotices.map { notice in
            CalendarAllDayEvent(
                id: "\(dateKey)-school-\(notice.id)",
                title: notice.name,
                time: deadlineTime(notice.deadline),
                kind: .schoolNotice,
                deadlineItem: notice
            )
        }
        let publicDeadlineEvents = publicDeadlines.map { item in
            CalendarAllDayEvent(
                id: "\(dateKey)-public-\(item.id)",
                title: item.name,
                time: deadlineTime(item.deadline),
                kind: CalendarDeadlinePresentation.eventKind(for: item),
                deadlineItem: item
            )
        }
        return holidayEvents + assignmentEvents + schoolNoticeEvents + publicDeadlineEvents
    }

    private func monthDaySnapshots(for days: [Date]) -> [CalendarMonthDaySnapshot] {
        let accessibilityDateFormatter = fullDateFormatter
        let coursesByDate: [String: [Course]]
        if let schedule = model.schedule,
           let termStart = StrictContractDateParser.date(from: schedule.termStartDate) {
            coursesByDate = ScheduleLogic.coursesByDate(
                for: days,
                termStart: termStart,
                courses: schedule.courses,
                calendar: calendar
            )
        } else {
            coursesByDate = [:]
        }
        let years = Set(days.map { calendar.component(.year, from: $0) })
        let holidaysByDate = Dictionary(
            grouping: years.flatMap { model.holidayItems(for: $0) },
            by: \.date
        )
        let favoritesByDate = Dictionary(
            grouping: model.favoriteDeadlines,
            by: { String($0.deadline.prefix(10)) }
        )

        return days.map { day in
            let dateKey = StrictContractDateParser.string(from: day)
            let holidays = holidaysByDate[dateKey] ?? []
            let assignments = calendarDeadlines.assignmentsByDate[dateKey] ?? []
            let publicItems = model.visibleDeadlineItems(
                liveItems: calendarDeadlines.publicItems(for: dateKey),
                favoriteItems: favoritesByDate[dateKey] ?? []
            )
            let schoolNotices = publicItems.filter { $0.source == .schoolNotice }
            let publicDeadlines = publicItems.filter { $0.source != .schoolNotice }
            let courses = coursesByDate[dateKey] ?? []
            let allDayEvents = calendarAllDayEvents(
                dateKey: dateKey,
                holidays: holidays,
                assignments: assignments,
                schoolNotices: schoolNotices,
                publicDeadlines: publicDeadlines
            )
            let deadlineKinds = CalendarDeadlinePresentation.topTwoDeadlineKinds(
                in: allDayEvents
            )
            return CalendarMonthDaySnapshot(
                date: day,
                dateKey: dateKey,
                dayNumber: calendar.component(.day, from: day),
                weekday: calendar.component(.weekday, from: day),
                month: calendar.component(.month, from: day),
                accessibilityLabel: TeachingCalendarLogic.dayAccessibilityLabel(
                    formattedDate: accessibilityDateFormatter.string(from: day),
                    holidayNames: holidays.map(\.name),
                    courseDescriptions: courses.map { "\($0.timeRange)\($0.name)" }
                ),
                courses: courses,
                holidays: holidays,
                assignments: assignments,
                schoolNotices: schoolNotices,
                publicDeadlines: publicDeadlines,
                allDayEvents: allDayEvents,
                deadlineKinds: deadlineKinds,
                deadlineAccessibilityValue: deadlineKinds
                    .map(\.rawValue)
                    .joined(separator: ",")
            )
        }
    }

    private func cachedDaySnapshots(
        for days: [Date],
        scope: String
    ) -> CalendarDaySnapshotCollection {
        let firstDate = days.first.map { StrictContractDateParser.string(from: $0) } ?? "empty"
        let key = "\(scope)|\(firstDate)|\(days.count)"
        return monthSnapshotCache.value(for: key) {
            CalendarDaySnapshotCollection(days: monthDaySnapshots(for: days))
        }
    }

    private func weekDates() -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func monthGridDates(containing date: Date) -> [Date] {
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: first) else { return [] }
        return (0 ..< 42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var visibleHolidayYears: Set<Int> {
        switch mode {
        case .day:
            return [calendar.component(.year, from: selectedDate)]
        case .week:
            return Set(weekDates().map { calendar.component(.year, from: $0) })
        case .month:
            return Set(monthGridDates(containing: selectedDate).map { calendar.component(.year, from: $0) })
        case .year:
            return [calendar.component(.year, from: selectedDate)]
        }
    }

    private var holidayStatus: String? {
        visibleHolidayYears.compactMap { model.holidayStatusByYear[$0] }.first
    }

    private func ensureVisibleHolidays() {
        visibleHolidayYears.forEach { model.ensureHolidays(for: $0) }
    }

    private var visibleDailyDetailDates: [Date] {
        switch mode {
        case .day: [selectedDate]
        case .week: weekDates()
        case .month: monthGridDates(containing: selectedDate)
        case .year: TeachingCalendarLogic.datesInYear(containing: selectedDate, calendar: calendar)
        }
    }

    private var dailyDetailsLoadID: CalendarDailyDetailsLoadID {
        CalendarDailyDetailsLoadID(
            dates: visibleDailyDetailDates.map { StrictContractDateParser.string(from: $0) },
            almanacDate: mode == .month ? StrictContractDateParser.string(from: selectedDate) : nil,
            sampleMode: model.isSampleMode,
            loadsAlmanac: model.almanacEnabled,
            loadsPublicDeadlines: model.hasEnabledBuiltInPublicDeadlines,
            customSourceURL: model.customDeadlineSourceURL?.absoluteString
        )
    }

    @MainActor
    private func loadVisibleDailyDetails() async {
        let request = dailyDetailsLoadID
        await loadSampleCalendarEvents(request)
    }

    @MainActor
    private func loadSampleCalendarEvents(_ request: CalendarDailyDetailsLoadID) async {
        guard request.sampleMode else { return }
        await calendarDeadlines.loadCalendarEvents(
            dates: request.dates,
            sampleMode: true,
            includesPublicDeadlines: request.loadsPublicDeadlines,
            customSourceURL: nil
        )
    }

    private func moveDate(_ direction: Int) {
        let moved = mode == .month
            ? session.monthNavigationDestination(direction: direction, calendar: calendar)
            : TeachingCalendarLogic.movedDate(
                from: selectedDate,
                unit: navigationUnit,
                direction: direction,
                calendar: calendar
            )
        if let moved {
            session.prepareTransition(direction: direction)
            if mode == .month {
                prepareMonthPageChange(
                    to: moved,
                    direction: direction,
                    preservesMonthNavigationAnchor: true
                )
            } else {
                withAnimation(Self.viewAnimation) { selectedDate = moved }
            }
        }
    }

    private func selectMonthDay(_ day: Date) {
        guard !sameDay(day, selectedDate) else { return }
        if let direction = TeachingCalendarLogic.monthPageDirection(
            from: selectedDate,
            to: day,
            calendar: calendar
        ) {
            prepareMonthPageChange(to: day, direction: direction)
        } else {
            selectedDate = day
        }
    }

    private func prepareMonthPageChange(
        to date: Date,
        direction: Int,
        preservesMonthNavigationAnchor: Bool = false
    ) {
        monthPagingGeneration += 1
        let generation = monthPagingGeneration
        session.prepareTransition(direction: direction)
        Task { @MainActor in
            await Task.yield()
            guard mode == .month, monthPagingGeneration == generation else { return }
            if preservesMonthNavigationAnchor {
                session.commitMonthNavigation(to: date)
            } else {
                selectedDate = date
            }
        }
    }

    private var navigationUnit: TeachingCalendarLogic.NavigationUnit {
        switch mode {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        }
    }

    private var periodSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                guard mode != .year,
                      let direction = TeachingCalendarLogic.swipeDirection(
                          horizontalTranslation: value.translation.width,
                          verticalTranslation: value.translation.height,
                          predictedHorizontalTranslation: value.predictedEndTranslation.width
                      )
                else { return }
                moveDate(direction)
            }
    }

    private var modeSelection: Binding<CalendarMode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode else { return }
                changeMode(to: newMode)
            }
        )
    }

    private func changeMode(to newMode: CalendarMode, selecting date: Date? = nil) {
        Task { @MainActor in
            await session.requestModeChange(to: newMode.rawValue, selecting: date)
        }
    }

    private var datePickerSelection: Binding<Date> {
        Binding(
            get: { selectedDate },
            set: { newDate in
                if mode == .month {
                    selectMonthDay(newDate)
                } else {
                    session.prepareTransition(direction: TeachingCalendarNavigationMotion.direction(
                        from: selectedDate,
                        to: newDate
                    ))
                    withAnimation(Self.viewAnimation) { selectedDate = newDate }
                }
                showingDatePicker = false
            }
        )
    }

    private func dismissYearPopover() {
        yearPopoverDate = nil
        yearPopoverLocation = nil
        yearPopoverScrollTarget = Self.yearPopoverTopID
    }

    #if os(macOS)
    private func yearPopoverBinding(for day: Date) -> Binding<Bool> {
        Binding(
            get: {
                guard let popoverDay = yearPopoverDate else { return false }
                return sameDay(popoverDay, day)
            },
            set: { isPresented in
                if !isPresented,
                   let popoverDay = yearPopoverDate,
                   sameDay(popoverDay, day) {
                    dismissYearPopover()
                }
            }
        )
    }
    #endif

    private var monthGridIdentity: String {
        let month = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        return "regular-month-\(month.timeIntervalSinceReferenceDate)"
    }

    private var monthPageTransition: AnyTransition {
        TeachingCalendarNavigationMotion.transition(
            direction: session.transitionDirection,
            includesOpacity: true
        )
    }

    private var calendarContentIdentity: String {
        let referenceDate: Date
        switch mode {
        case .day:
            referenceDate = calendar.startOfDay(for: selectedDate)
        case .week:
            referenceDate = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
                ?? selectedDate
        case .month:
            return mode.rawValue
        case .year:
            // A year grid contains hundreds of cells. Update it in place so
            // page navigation never renders the old and new years together.
            return mode.rawValue
        }
        return "\(mode.rawValue)-\(referenceDate.timeIntervalSinceReferenceDate)"
    }

    private var weekContextText: String {
        monthWeekContextText(date: selectedDate)
    }

    private func monthWeekContextText(date: Date) -> String {
        TeachingCalendarLogic.weekContext(
            for: date,
            teachingWeekNumber: teachingWeekNumber(on: date),
            language: model.appLanguage,
            calendar: calendar,
            compact: mode == .month
        )
    }

    private func teachingWeekNumber(on date: Date) -> Int? {
        guard let schedule = model.schedule,
              let termStart = StrictContractDateParser.date(from: schedule.termStartDate)
        else { return nil }
        return ScheduleLogic.activeTeachingWeekNumber(
            on: date,
            termStart: termStart,
            courses: schedule.courses,
            calendar: calendar
        )
    }

    private func estimatedYearPopoverHeight(_ day: Date, availableHeight: CGFloat) -> CGFloat {
        let rows = max(
            1,
            holidayItems(on: day).count
                + courses(on: day).count
                + assignmentItems(on: day).count
                + schoolNoticeItems(on: day).count
                + otherPublicDeadlineItems(on: day).count
        )
        return min(max(160, CGFloat(rows * 48 + 124)), min(380, max(160, availableHeight - 32)))
    }

    private func monthCellColor(selected: Bool, inMonth: Bool, courseCount: Int) -> Color {
        if selected { return AppTheme.selectedDate }
        if !inMonth { return AppTheme.surface }
        guard courseCount > 0 else { return AppTheme.background }
        return AppTheme.primary.opacity(min(0.08 + Double(courseCount) * 0.10, 0.48))
    }

    private func monthTextColor(selected: Bool, inMonth: Bool, holidays: [HolidayItem]) -> Color {
        if selected { return AppTheme.onPrimary }
        if !inMonth { return AppTheme.secondaryText.opacity(0.55) }
        if let holiday = holidays.first { return Self.holidayColor(holiday) }
        return AppTheme.text
    }

    private func yearCellColor(selected: Bool, courseCount: Int) -> Color {
        if selected { return AppTheme.selectedDate }
        guard courseCount > 0 else { return AppTheme.background }
        return AppTheme.primary.opacity(TeachingCalendarLogic.yearCourseOpacity(courseCount: courseCount))
    }

    private func dayAccessibilityLabel(
        _ snapshot: CalendarMonthDaySnapshot,
        isToday: Bool
    ) -> String {
        guard isToday else { return snapshot.accessibilityLabel }
        return "\(model.localized("今天"))，\(snapshot.accessibilityLabel)"
    }

    private func sameDay(_ left: Date, _ right: Date) -> Bool {
        calendar.isDate(left, inSameDayAs: right)
    }

    private static func holidayColor(_ item: HolidayItem) -> Color {
        item.type == "holiday" ? holidayRed : AppTheme.primary
    }

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
    private static let nowRed = AppTheme.danger
    private static let holidayRed = AppTheme.danger
    private static let calendarCoordinateSpace = "teaching-calendar"
    private static let yearPopoverTopID = "year-popover-top"
    private static let yearPopoverBottomID = "year-popover-bottom"
    private static let viewAnimation = TeachingCalendarNavigationMotion.pageAnimation
    private static let pageAnimation = TeachingCalendarNavigationMotion.pageAnimation
    private static let monthExpansionAnimation = Animation.easeInOut(duration: 0.28)
    private var fullDateFormatter: DateFormatter {
        localizedDateFormatter(chineseFormat: "yyyy年M月d日 EEEE", englishFormat: "EEEE, MMMM d, yyyy")
    }

    private var controlDateFormatter: DateFormatter {
        localizedDateFormatter(chineseFormat: "yyyy-MM-dd", englishFormat: "yyyy-MM-dd")
    }

    private var monthDayCompactFormatter: DateFormatter {
        localizedDateFormatter(chineseFormat: "M月d日", englishFormat: "MMM d")
    }

    private var monthFormatter: DateFormatter {
        localizedDateFormatter(chineseFormat: "M月", englishFormat: "MMM")
    }

    private func localizedDateFormatter(
        chineseFormat: String,
        englishFormat: String
    ) -> DateFormatter {
        let format = model.appLanguage.resolvedResourceName == "en"
            ? englishFormat
            : chineseFormat
        return dateFormatterCache.formatter(format: format, locale: model.appLanguage.locale)
    }
}
