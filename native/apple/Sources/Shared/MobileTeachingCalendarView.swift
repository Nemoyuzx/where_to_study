import Combine
import Foundation

#if os(iOS)
import SwiftUI
import UIKit

private enum MobileCalendarMode: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"

    var id: String { rawValue }
}

private struct MobileCalendarDetailSelection: Identifiable {
    enum Content {
        case day
        case course(Course)
        case holiday(HolidayItem)
    }

    let id = UUID()
    let date: Date
    let content: Content
}

struct MobileMonthEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let categoryKey: String
    let tint: Color
    let deadlineItem: PublicDeadlineItem?

    init(
        id: String,
        title: String,
        categoryKey: String,
        tint: Color,
        deadlineItem: PublicDeadlineItem? = nil
    ) {
        self.id = id
        self.title = title
        self.categoryKey = categoryKey
        self.tint = tint
        self.deadlineItem = deadlineItem
    }
}

struct MobileMonthDaySnapshot: Identifiable, Equatable {
    let date: Date
    let dateKey: String
    let dayNumberText: String
    let accessibilityLabel: String
    let courses: [Course]
    let holiday: HolidayItem?
    let events: [MobileMonthEvent]
    let allDayEvents: [CalendarAllDayEvent]
    let deadlineKinds: [CalendarAllDayEventKind]

    var id: Date { date }
}

private struct MobileYearSnapshotCollection {
    let byDate: [String: MobileMonthDaySnapshot]

    init(days: [MobileMonthDaySnapshot]) {
        byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.dateKey, $0) })
    }
}

@MainActor
private final class MobileCalendarSnapshotCache: ObservableObject {
    private var monthStorage = CalendarBoundedCache<String, [MobileMonthDaySnapshot]>(capacity: 6)
    private var yearStorage = CalendarBoundedCache<String, MobileYearSnapshotCollection>(capacity: 24)
    private let timelineStorage = CalendarBoundedCache<String, [CalendarTimelineDay]>(capacity: 6)
    private let invalidation = CalendarSnapshotInvalidationObserver()
    private let monthWorker = MobileMonthProjectionWorker()
    private(set) var generation: UInt64 = 0
    private let monthDates = CalendarBoundedCache<Date, [Date]>(capacity: 8)

    func dates(inMonthContaining date: Date) -> [Date] {
        let calendar = Calendar.shanghai
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? date
        return monthDates.value(for: first) {
            let leading = (calendar.component(.weekday, from: first) + 5) % 7
            guard let start = calendar.date(byAdding: .day, value: -leading, to: first) else { return [] }
            return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        }
    }

    func preparedMonth(for key: String) -> [MobileMonthDaySnapshot]? {
        monthStorage.cachedValue(for: key)
    }

    func prepareMonth(for key: String, input: MobileMonthProjectionInput) async -> Bool {
        if preparedMonth(for: key) != nil { return true }
        let requestedGeneration = generation
        do {
            let days = try await monthWorker.build(input: input)
            guard !Task.isCancelled, generation == requestedGeneration else { return false }
            let mapped = days.map { day in
                MobileMonthDaySnapshot(
                    date: day.date, dateKey: day.dateKey, dayNumberText: day.dayNumberText,
                    accessibilityLabel: day.accessibilityLabel, courses: day.courses,
                    holiday: day.holiday,
                    events: day.events.map { event in
                        MobileMonthEvent(
                            id: event.id, title: event.title, categoryKey: event.categoryKey,
                            tint: event.kind.map(CalendarDeadlinePresentation.tint) ?? AppTheme.primary,
                            deadlineItem: event.deadlineItem
                        )
                    },
                    allDayEvents: day.allDayEvents, deadlineKinds: day.deadlineKinds
                )
            }
            if preparedMonth(for: key) == nil {
                objectWillChange.send()
                _ = monthStorage.value(for: key) { mapped }
            }
            return true
        } catch { return false }
    }

    func timelineValues(for key: String, build: () -> [CalendarTimelineDay]) -> [CalendarTimelineDay] {
        timelineStorage.value(for: key, build: build)
    }

    func yearValues(
        for key: String,
        build: () -> [MobileMonthDaySnapshot]
    ) -> MobileYearSnapshotCollection {
        yearStorage.value(for: key) {
            MobileYearSnapshotCollection(days: build())
        }
    }

    func invalidate() {
        generation &+= 1
        objectWillChange.send()
        monthStorage.removeAll()
        yearStorage.removeAll()
        timelineStorage.removeAll()
    }

    func bind(model: AppModel, deadlineStore: CalendarDeadlineStore) {
        invalidation.bind(model: model, deadlineStore: deadlineStore) { [weak self] in
            self?.invalidate()
        }
    }

}

typealias MobileCalendarDateFormatterCache = CalendarDateFormatterCache

private struct MobileWeekAgendaSelection: Identifiable {
    let id = UUID()
    let date: Date
    let events: [CalendarAllDayEvent]
}

private final class MobileMonthDragRoutingSession {
    var detailsCanScrollBackwardAtStart: Bool?
    var isRoutedToDetails = false

    func reset() {
        detailsCanScrollBackwardAtStart = nil
        isRoutedToDetails = false
    }
}

enum MobileCalendarAnimationPartition {
    static func contentIdentity(
        modeRawValue: String,
        selectedDate: Date,
        calendar: Calendar = .shanghai
    ) -> String {
        let referenceDate: Date
        switch modeRawValue {
        case "日":
            referenceDate = calendar.startOfDay(for: selectedDate)
        case "周":
            referenceDate = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
                ?? selectedDate
        case "月":
            // Month-to-month paging is scoped to the grid. Keeping the outer
            // identity stable prevents the details viewport from joining the
            // horizontal page transition.
            return "月"
        case "年":
            // Reusing the year shell avoids keeping two 12-month/365-day
            // grids alive during an animated year change.
            return "年"
        default:
            referenceDate = calendar.startOfDay(for: selectedDate)
        }
        return "\(modeRawValue)-\(referenceDate.timeIntervalSinceReferenceDate)"
    }

    static func monthGridIdentity(
        selectedDate: Date,
        calendar: Calendar = .shanghai
    ) -> String {
        let month = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        return "月格-\(month.timeIntervalSinceReferenceDate)"
    }
}

struct MobileMonthPagingState: Equatable {
    private(set) var preparedDirection = 1
    private(set) var generation = 0

    mutating func prepare(direction: Int) -> Int {
        preparedDirection = direction < 0 ? -1 : 1
        generation += 1
        return generation
    }

    func accepts(_ generation: Int) -> Bool {
        self.generation == generation
    }
}

@MainActor
final class MobileMonthDetailsScrollState {
    private weak var scrollView: UIScrollView?
    private var panGestureIsActive = false
    private var canScrollBackwardAtPanStart = false

    func attach(_ scrollView: UIScrollView) {
        self.scrollView = scrollView
        panGestureIsActive = false
        canScrollBackwardAtPanStart = Self.canScrollBackward(scrollView)
    }

    func detach(_ scrollView: UIScrollView?) {
        guard self.scrollView === scrollView else { return }
        self.scrollView = nil
        panGestureIsActive = false
        canScrollBackwardAtPanStart = false
    }

    func recordPan(_ recognizer: UIPanGestureRecognizer) {
        guard let scrollView = recognizer.view as? UIScrollView else { return }
        switch recognizer.state {
        case .began:
            panGestureIsActive = true
            canScrollBackwardAtPanStart = Self.canScrollBackward(scrollView)
        case .ended, .cancelled, .failed:
            panGestureIsActive = false
        default:
            break
        }
    }

    func routingSnapshot(fallback: Bool) -> Bool {
        guard let scrollView else { return fallback }
        if panGestureIsActive { return canScrollBackwardAtPanStart }
        return Self.canScrollBackward(scrollView)
    }

    func reset() {
        scrollView = nil
        panGestureIsActive = false
        canScrollBackwardAtPanStart = false
    }

    private static func canScrollBackward(_ scrollView: UIScrollView) -> Bool {
        let topOffset = -scrollView.adjustedContentInset.top
        return scrollView.contentOffset.y > topOffset + 1
    }
}

struct MobileTeachingCalendarView: View {
    @EnvironmentObject private var model: AppModel
    let calendarDeadlines: CalendarDeadlineStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var session: TeachingCalendarSessionState
    @StateObject private var snapshotCache = MobileCalendarSnapshotCache()
    @StateObject private var dateFormatterCache = MobileCalendarDateFormatterCache()
    @State private var presentedDetail: MobileCalendarDetailSelection?
    @State private var presentedWeekAgenda: MobileWeekAgendaSelection?
    @State private var isHorizontalPaging = false
    @State private var suppressesEventSelection = false
    @State private var monthDragTranslation: CGFloat = 0
    @State private var monthDragAxis: TeachingCalendarLogic.GestureAxis?
    @State private var eventSelectionSuppressionID = UUID()
    @State private var monthDetailsCanScrollBackward = false
    @State private var monthDetailsScrollResetID = UUID()
    @State private var monthDetailsScrollState = MobileMonthDetailsScrollState()
    @State private var monthDragRoutingSession = MobileMonthDragRoutingSession()
    @State private var monthPageWindow: MobileMonthPageWindow?
    @State private var monthPagingProgress: CGFloat = 0
    @State private var monthPageTask: Task<Void, Never>?
    @State private var monthPageReadiness: [Date: String] = [:]
    @State private var monthLayoutEpoch: UInt64 = 0
    @State private var frozenMonthPages: [Date: [MobileMonthDaySnapshot]] = [:]
    @State private var frozenMonthGeneration: UInt64 = 0
    @State private var frozenMonthDetailsDate: Date?
    @State private var pendingMonthPosition: TeachingCalendarLogic.MonthPosition?
    @State private var areTimelineCoursesExpanded = true

    private let calendar = Calendar.shanghai

    private var selectedDate: Date {
        get { session.selectedDate }
        nonmutating set { session.selectedDate = newValue }
    }

    private var mode: MobileCalendarMode {
        get { MobileCalendarMode(rawValue: session.modeRawValue) ?? .week }
        nonmutating set { session.modeRawValue = newValue.rawValue }
    }

    private var isMonthExpanded: Bool {
        get { session.isMonthExpanded }
        nonmutating set { session.isMonthExpanded = newValue }
    }

    private var isMonthDetailRaised: Bool {
        get { session.isMonthDetailRaised }
        nonmutating set { session.isMonthDetailRaised = newValue }
    }

    private var usesLandscapeMonthStops: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                compactHeader
                    .accessibilityIdentifier("layout.calendar.compact")
                statusArea
                ZStack {
                    content
                        .id(contentIdentity)
                        .transition(pageTransition)
                }
                .clipped()
            }
            .background(AppTheme.background)
            .ignoresSafeArea(.container, edges: .bottom)
            .accessibilityIdentifier("screen.calendar")
            .navigationBarHidden(true)
        }
        .sheet(item: $presentedDetail) { selection in
            detailSheet(selection)
                .presentationDetents([.medium, .large])
        }
        .overlay {
            if let selection = presentedWeekAgenda {
                weekAgendaDialog(selection)
            }
        }
        .onAppear {
            normalizeMonthPositionForLayout()
        }
        .task(id: [ObjectIdentifier(model), ObjectIdentifier(calendarDeadlines)]) {
            rebaseMonthPages()
            snapshotCache.bind(model: model, deadlineStore: calendarDeadlines)
        }
        .onChange(of: model.calendarDataOwnerRevision) { _ in
            rebaseMonthPages()
            snapshotCache.invalidate()
        }
        .onChange(of: selectedDate) { _ in
            if monthPageWindow?.transition == nil || monthPageWindow?.selectedDate != selectedDate {
                resetMonthDetailsScroll()
                if mode == .month, monthPageWindow?.selectedDate != selectedDate { rebaseMonthPages() }
            }
        }
        .onChange(of: mode) { _ in rebaseMonthPages() }
        .onDisappear { rebaseMonthPages() }
        .onChange(of: verticalSizeClass) { _ in
            rebaseMonthPages()
            normalizeMonthPositionForLayout()
        }
        .onChange(of: reduceMotion) { _ in rebaseMonthPages() }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var compactHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .leading) {
                        Text(periodTitle)
                            .id(periodTitle)
                            .transition(pageTransition)
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .clipped()
                    .animation(TeachingCalendarNavigationMotion.pageAnimation, value: periodTitle)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(periodTitle)
                .accessibilityIdentifier("calendar.mobile.period-label")

                Spacer(minLength: 8)

                Button("今天") {
                    navigate(to: .now)
                }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .accessibilityIdentifier("calendar.mobile.today")

                Button { moveDate(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 36)
                }
                .accessibilityLabel("上一时间段")

                Button { moveDate(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 30, height: 36)
                }
                .accessibilityLabel("下一时间段")

                actionMenu
            }

            Picker("日历视图", selection: modeSelection) {
                ForEach(MobileCalendarMode.allCases) { item in
                    Text(model.localized(item.rawValue)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .animation(TeachingCalendarNavigationMotion.pageAnimation, value: mode)
            .accessibilityIdentifier("calendar.mobile.mode")

            if mode == .day || mode == .week {
                Label {
                    Text(weekContextText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                } icon: {
                    Image(systemName: "graduationcap")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("calendar.mobile.teaching-week")
            }

            if mode == .day || mode == .week {
                weekDateStrip
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, mode == .day || mode == .week ? 8 : 6)
        .background(AppTheme.surface)
    }

    private var actionMenu: some View {
        Menu {
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

            Button {
                model.importFavoriteDeadlinesToCalendar()
            } label: {
                Label(
                    model.isImportingCalendar ? "正在导入…" : "导入已收藏日程",
                    systemImage: "star.square.on.square"
                )
            }
            .disabled(model.favoriteDeadlines.isEmpty || model.isImportingCalendar)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("课表操作")
    }

    private var weekDateStrip: some View {
        let days = weekDates()
        return HStack(spacing: 0) {
            if mode == .week {
                VStack(spacing: 0) {
                    Text(
                        "\(TeachingCalendarLogic.civilWeekNumber(on: selectedDate, calendar: calendar)) / "
                        + (teachingWeekNumber(on: selectedDate).map(String.init) ?? "—")
                    )
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Text(model.localized("公历 / 教学"))
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: MobileCalendarTimelineLayout.axisWidth, height: 56)
                .accessibilityLabel(weekContextText)
            }
            ForEach(days, id: \.self) { day in
                dateStripButton(day)
            }
        }
        .padding(.horizontal, -16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.mobile.date-strip")
        .contentShape(Rectangle())
        .simultaneousGesture(periodSwipeGesture)
    }

    private func dateStripButton(_ day: Date) -> some View {
        let selected = sameDay(day, selectedDate)
        let today = sameDay(day, .now)
        let dayCourses = courses(on: day)
        let holiday = holidayItems(on: day).first

        return Button {
            guard !suppressesEventSelection else { return }
            navigate(to: day)
        } label: {
            VStack(spacing: 3) {
                Text(weekdayFormatter.string(from: day))
                    .font(.caption2.weight(.semibold))
                Text("\(calendar.component(.day, from: day))")
                    .font(.headline.monospacedDigit())
                HStack(spacing: 2) {
                    if holiday != nil {
                        Text(model.localized(holiday?.type == "holiday" ? "休" : "班"))
                            .font(.system(size: 8, weight: .bold))
                    }
                    if !dayCourses.isEmpty {
                        Circle().frame(width: 4, height: 4)
                    }
                }
                .frame(height: 8)
            }
            .foregroundStyle(selected ? AppTheme.onPrimary : dateStripForeground(holiday: holiday))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(selected ? AppTheme.selectedDate : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(today ? AppTheme.danger : Color.clear, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(day))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var statusArea: some View {
        let messages = [holidayStatus, model.statusMessage, model.calendarImportStatusMessage]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages, id: \.self) { message in
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.primary.opacity(0.08))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .day:
            timelineContent(days: [selectedDate])
        case .week:
            timelineContent(days: weekDates())
        case .month:
            monthView
        case .year:
            yearView
        }
    }

    private func timelineContent(days: [Date]) -> some View {
        let key = snapshotCacheKey(for: days, scope: "timeline")
        let timelineDays = snapshotCache.timelineValues(for: key) { days.map(timelineDay) }
        return VStack(spacing: 0) {
            selectedDateSummary
                .contentShape(Rectangle())
                .simultaneousGesture(periodSwipeGesture)
            allDayItems(days: timelineDays)
            MobileCalendarTimelineView(
                days: timelineDays,
                selectedDate: selectedDate,
                showsWeekColumns: mode == .week,
                isScrollEnabled: !isHorizontalPaging,
                bottomContentInset: MobileCalendarTimelineLayout.contentBottomInset(
                    isLandscape: usesLandscapeMonthStops
                ),
                onSelectDay: { date in
                    guard !suppressesEventSelection else { return }
                    navigate(to: date)
                },
                onSelectCourse: { date, course in
                    presentCourse(course, on: date)
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.mobile.timeline")
            .contentShape(Rectangle())
            .simultaneousGesture(periodSwipeGesture)
        }
    }

    private var selectedDateSummary: some View {
        let dayCourses = courses(on: selectedDate)
        return VStack(alignment: .leading, spacing: 7) {
            Button {
                AppHaptics.selection()
                withAnimation(Self.viewAnimation) {
                    areTimelineCoursesExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fullDateFormatter.string(from: selectedDate))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(dayCourses.isEmpty ? "暂无课程" : "\(dayCourses.count) 门课")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .rotationEffect(.degrees(areTimelineCoursesExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("calendar.mobile.course-summary-toggle")
            .accessibilityValue(areTimelineCoursesExpanded ? "已展开" : "已折叠")

            if areTimelineCoursesExpanded {
                ForEach(dayCourses) { course in
                    Button {
                        presentCourse(course, on: selectedDate)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(
                                [course.timeRange, CalendarTimelineLogic.courseMetadata(course)]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · ")
                            )
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.surface)
    }

    @ViewBuilder
    private func allDayItems(days: [CalendarTimelineDay]) -> some View {
        let hasAllDayItems = days.contains { !$0.allDayEvents.isEmpty }
        if hasAllDayItems, days.count > 1 {
            weekAllDayItems(days: days)
        } else if hasAllDayItems, let day = days.first {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("全天")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    ForEach(Array(day.allDayEvents.prefix(3))) { item in
                        Button {
                            present(.day, on: day.date)
                        } label: {
                            Text("\(monthDayCompactFormatter.string(from: day.date)) · \(item.title)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(allDayEventTint(item.kind))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(allDayEventTint(item.kind).opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if day.allDayEvents.count > 3 {
                        Button("+\(day.allDayEvents.count - 3)") {
                            present(.day, on: day.date)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("查看其余 \(day.allDayEvents.count - 3) 项全天日程")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(AppTheme.surface)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func weekAllDayItems(days: [CalendarTimelineDay]) -> some View {
        let labels = MobileCalendarAllDayLayout.labels(for: days)
        return GeometryReader { proxy in
            let dayWidth = MobileCalendarAllDayLayout.dayWidth(
                availableWidth: proxy.size.width,
                dayCount: days.count
            )
            HStack(spacing: 0) {
                Text("全天")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(
                        width: MobileCalendarTimelineLayout.axisWidth,
                        height: MobileCalendarAllDayLayout.height
                    )
                    .overlay(alignment: .trailing) { Divider() }

                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        if day.allDayEvents.isEmpty {
                            Color.clear
                                .frame(width: dayWidth, height: MobileCalendarAllDayLayout.height)
                                .accessibilityHidden(true)
                        } else {
                            Button {
                                AppHaptics.selection()
                                presentedWeekAgenda = MobileWeekAgendaSelection(
                                    date: day.date,
                                    events: day.allDayEvents
                                )
                            } label: {
                                Text(labels[index])
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(allDayEventTint(day.allDayEvents[0].kind))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .padding(.horizontal, 3)
                                    .frame(
                                        width: max(dayWidth - 4, 1),
                                        height: MobileCalendarAllDayLayout.height - 4
                                    )
                                    .background(
                                        allDayEventTint(day.allDayEvents[0].kind).opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                                    .padding(2)
                            }
                            .buttonStyle(.plain)
                            .frame(width: dayWidth, height: MobileCalendarAllDayLayout.height)
                            .accessibilityLabel(
                                "\(monthDayCompactFormatter.string(from: day.date))，全天，\(labels[index])"
                            )
                            .accessibilityIdentifier(
                                "calendar.mobile.all-day.day.\(StrictContractDateParser.string(from: day.date))"
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(width: proxy.size.width, height: MobileCalendarAllDayLayout.height)
        }
        .frame(height: MobileCalendarAllDayLayout.height)
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("calendar.mobile.all-day.week")
    }

    private func allDayEventTint(_ kind: CalendarAllDayEventKind) -> Color {
        CalendarDeadlinePresentation.tint(for: kind)
    }

    private var monthView: some View {
        let window = monthPageWindow ?? MobileMonthPageWindow(selectedDate: selectedDate, calendar: calendar)
        let todayKey = StrictContractDateParser.string(from: .now)

        return GeometryReader { proxy in
            let bottomInset = MobileCalendarTimelineLayout.contentBottomInset(
                isLandscape: usesLandscapeMonthStops
            )
            let usableHeight = max(
                proxy.size.height - bottomInset,
                0
            )
            let travelDistance = max(min(usableHeight * 0.34, 220), 120)
            let position = TeachingCalendarLogic.monthPosition(
                isExpanded: effectiveMonthPosition == .expanded,
                isDetailRaised: effectiveMonthPosition == .detailRaised,
                verticalTranslation: monthDragTranslation * (usesLandscapeMonthStops ? 2 : 1),
                travelDistance: travelDistance
            )
            let expansionProgress = TeachingCalendarLogic.monthGridExpansionProgress(position: position)
            let detailLiftProgress = TeachingCalendarLogic.monthDetailLiftProgress(position: position)
            let gridLayout = TeachingCalendarLogic.monthGridLayout(
                contentWidth: max(proxy.size.width - 24, 0),
                availableHeight: usableHeight
            )
            let cellHeight = gridLayout.cellHeight(at: expansionProgress)
            let gridWidth = gridLayout.gridWidth(at: expansionProgress)
            let rowSpacing: CGFloat = 4
            let fullGridHeight = cellHeight * 6 + rowSpacing * 5
            let visibleGridHeight = fullGridHeight
                - (fullGridHeight - cellHeight) * detailLiftProgress
            let dayTopInset = TeachingCalendarLogic.monthDayTopInset(
                collapsedCellHeight: gridLayout.collapsedCellHeight
            )
            let maximumEventRows = TeachingCalendarLogic.monthEventRowCapacity(
                cellHeight: cellHeight,
                dayTopInset: dayTopInset
            )
            let summaryHeight = max(usableHeight - 18 - 8 - visibleGridHeight - 28 - 16, 0)

            let calendarContent = VStack(spacing: 0) {
                VStack(spacing: 0) {
                    monthWeekdayHeader
                        .frame(width: gridWidth)
                        .padding(.bottom, 8)
                    ZStack(alignment: .top) {
                        ForEach(window.pages) { page in
                            let days = monthGridDates(containing: page.monthStart)
                            let key = snapshotCacheKey(for: days, scope: "month")
                            let active = page.monthStart == (window.transition?.targetMonth ?? window.centerMonth)
                            let snapshots = frozenMonthPages[page.monthStart]
                                ?? snapshotCache.preparedMonth(for: key)
                                ?? monthSkeleton(for: days)
                            let pageDate = preparedSelectionDate(for: page.monthStart, window: window)
                            let selectedKey = StrictContractDateParser.string(from: pageDate)
                            let weekIndex = monthWeekIndex(selectedDateKey: selectedKey, in: snapshots)
                            let offset = -CGFloat(weekIndex) * (cellHeight + rowSpacing) * detailLiftProgress
                            MobileMonthNativeGrid(
                                days: snapshots,
                                monthKey: String(StrictContractDateParser.string(from: page.monthStart).prefix(7)),
                                selectedDateKey: selectedKey, todayKey: todayKey,
                                expansionProgress: expansionProgress,
                                cellHeight: cellHeight, dayTopInset: dayTopInset,
                                maximumEventRows: maximumEventRows,
                                active: active, language: model.appLanguage,
                                onSelect: requestMonthDaySelection
                            )
                            .frame(width: gridWidth, height: fullGridHeight, alignment: .top)
                            .offset(y: offset)
                            .frame(width: gridWidth, height: visibleGridHeight, alignment: .top)
                            .clipped()
                            .background {
                                if frozenMonthPages[page.monthStart] != nil || snapshotCache.preparedMonth(for: key) != nil {
                                    MobileMonthPageLayout(
                                        month: page.monthStart,
                                        generation: "\(monthLayoutEpoch)|\(frozenMonthPages[page.monthStart] == nil ? snapshotCache.generation : frozenMonthGeneration)|\(selectedKey)|\(active)"
                                    ) { month, generation in
                                        if monthPageReadiness[month] != generation {
                                            monthPageReadiness[month] = generation
                                        }
                                    }
                                }
                            }
                            .offset(x: (CGFloat(page.offset) + monthPagingProgress) * gridWidth)
                            .allowsHitTesting(window.transition == nil && page.monthStart == window.centerMonth)
                            .accessibilityElement(children: active ? .contain : .ignore)
                            .accessibilityHidden(!active)
                        }
                    }
                    .frame(width: gridWidth, height: visibleGridHeight, alignment: .top)
                    .clipped()
                    monthExpansionHandle(
                        expansionProgress: expansionProgress,
                        detailLiftProgress: detailLiftProgress
                    )
                }
                .frame(maxWidth: .infinity)

                monthDetailsViewport(
                    day: frozenMonthDetailsDate ?? selectedDate,
                    height: summaryHeight,
                    expansionProgress: expansionProgress
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: usableHeight, maxHeight: usableHeight, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .contentShape(Rectangle())

            monthGestureContainer(
                calendarContent,
                travelDistance: travelDistance,
                detailsCanScrollBackward: monthDetailsCanScrollBackward
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.mobile.month")
            .accessibilityValue(monthAccessibilityValue)
            #if DEBUG
            .overlay(alignment: .topLeading) {
                if ProcessInfo.processInfo.arguments.contains("--ui-test-month-performance") {
                    MobileMonthFrameProbe(pageID: monthGridIdentity).frame(width: 32, height: 10)
                        .accessibilityIdentifier("calendar.mobile.month-frame-probe")
                }
            }
            #endif
            .accessibilityAction(named: Text(isMonthExpanded ? "收起月历" : "展开月历")) {
                settleMonthPosition(to: isMonthExpanded ? .collapsed : .expanded)
            }
            #if DEBUG
            .task {
                guard ProcessInfo.processInfo.arguments.contains("--ui-test-month-autoplay") else { return }
                do {
                    try await Task.sleep(for: .seconds(1))
                    for direction in [1, -1, 1, 1, -1, -1] {
                        guard !Task.isCancelled else { return }
                        moveDate(direction)
                        try await Task.sleep(for: .seconds(1))
                    }
                } catch {}
            }
            #endif
            .task(id: monthPreparationID) {
                guard monthPageWindow?.transition == nil else { return }
                let currentWindow = monthPageWindow ?? MobileMonthPageWindow(selectedDate: selectedDate, calendar: calendar)
                if monthPageWindow == nil { monthPageWindow = currentWindow }
                for page in currentWindow.pages.sorted(by: { abs($0.offset) < abs($1.offset) }) {
                    guard !Task.isCancelled else { return }
                    if await prepareMonthData(page.monthStart) {
                        frozenMonthPages.removeValue(forKey: page.monthStart)
                    }
                    await Task.yield()
                }
                // Data-only lookahead: the next recycled slot should receive
                // its final snapshot, not lay out a skeleton and then all text
                // again in the same animation-completion frame. Views stay at 3.
                for offset in [-2, 2] {
                    guard !Task.isCancelled,
                          let month = calendar.date(byAdding: .month, value: offset, to: currentWindow.centerMonth)
                    else { return }
                    _ = await prepareMonthData(month)
                    await Task.yield()
                }
            }
            .onChange(of: proxy.size) { _ in rebaseMonthPages() }
        }
    }

    @ViewBuilder
    private func monthDetailsViewport(
        day: Date,
        height: CGFloat,
        expansionProgress: CGFloat
    ) -> some View {
        if expansionProgress < 0.999, height > 1 {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    daySummaryCard(day)
                    MobileDeadlineStoreContent { deadlineStore in
                        mobileAssignmentCard(day, deadlineStore: deadlineStore)
                    }
                    if model.almanacEnabled {
                        MobileAlmanacCard(day: day)
                    }
                    if model.hasCalendarDeadlinesToDisplay {
                        MobileDeadlineStoreContent { deadlineStore in
                            mobileDeadlineCard(day, deadlineStore: deadlineStore)
                        }
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
                .background(MobileMonthDetailsScrollConfiguration(
                    canScrollBackward: $monthDetailsCanScrollBackward,
                    resetID: monthDetailsScrollResetID,
                    scrollState: monthDetailsScrollState
                ))
            }
            .frame(height: height)
            .opacity(1 - expansionProgress)
            .clipped()
            .allowsHitTesting(true)
            .scrollDisabled(effectiveMonthPosition != .detailRaised)
            .accessibilityHidden(expansionProgress >= 0.25)
            .accessibilityIdentifier("calendar.mobile.month-day-summary")
            .accessibilityValue(monthDetailsCanScrollBackward ? "已滚动" : "顶部")
            .background(Color.clear)
        } else {
            // Keep the viewport identity and geometry stable for UI semantics,
            // but do not construct the hidden course/almanac/deadline tree
            // while an expanded month page is entering or leaving.
            ScrollView(.vertical, showsIndicators: false) {
                Color.clear.frame(height: 0)
            }
                .frame(height: height)
                .scrollDisabled(true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .accessibilityIdentifier("calendar.mobile.month-day-summary")
                .accessibilityValue("顶部")
        }
    }

    @ViewBuilder
    private func monthGestureContainer<Content: View>(
        _ content: Content,
        travelDistance: CGFloat,
        detailsCanScrollBackward: Bool
    ) -> some View {
        content.simultaneousGesture(
            monthNavigationGesture(
                travelDistance: travelDistance,
                detailsCanScrollBackward: detailsCanScrollBackward
            )
        )
    }

    private var monthWeekdayHeader: some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Self.weekdayLabels, id: \.self) { label in
                Text(model.localized(label))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .accessibilityIdentifier("calendar.mobile.month-weekday.\(label)")
            }
        }
    }

    private func monthExpansionHandle(
        expansionProgress: CGFloat,
        detailLiftProgress: CGFloat
    ) -> some View {
        Button {
            settleMonthPosition(to: isMonthExpanded ? .collapsed : .expanded)
        } label: {
            ZStack {
                Capsule()
                    .fill(AppTheme.secondaryText.opacity(0.55))
                    .frame(width: 21, height: 4)
                    .rotationEffect(.degrees(-24 * expansionProgress))
                    .offset(x: -9, y: 2 * expansionProgress - detailLiftProgress)
                Capsule()
                    .fill(AppTheme.secondaryText.opacity(0.55))
                    .frame(width: 21, height: 4)
                    .rotationEffect(.degrees(24 * expansionProgress))
                    .offset(x: 9, y: 2 * expansionProgress - detailLiftProgress)
            }
                .frame(width: 42, height: 12)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMonthExpanded ? "收起月历" : "展开月历")
        .accessibilityValue(monthAccessibilityValue)
        .accessibilityIdentifier("calendar.mobile.month-state")
    }

    private func monthDaySnapshots(for days: [Date]) -> [MobileMonthDaySnapshot] {
        let accessibilityDateFormatter = fullDateFormatter
        let todayKey = StrictContractDateParser.string(from: .now)
        let localizedToday = model.localized("今天")
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
            let courses = coursesByDate[dateKey] ?? []
            let holidays = holidaysByDate[dateKey] ?? []
            let assignments = calendarDeadlines.assignmentsByDate[dateKey] ?? []
            let publicItems = model.visibleDeadlineItems(
                liveItems: calendarDeadlines.publicItems(for: dateKey),
                favoriteItems: favoritesByDate[dateKey] ?? []
            )
            let schoolNotices = publicItems.filter { $0.source == .schoolNotice }
            let publicDeadlines = publicItems.filter { $0.source != .schoolNotice }
            let allDayEvents = calendarAllDayEvents(
                dateKey: dateKey,
                holidays: holidays,
                assignments: assignments,
                schoolNotices: schoolNotices,
                publicDeadlines: publicDeadlines
            )
            return MobileMonthDaySnapshot(
                date: day,
                dateKey: dateKey,
                dayNumberText: String(calendar.component(.day, from: day)),
                accessibilityLabel: TeachingCalendarLogic.dayAccessibilityLabel(
                    todayText: dateKey == todayKey ? localizedToday : "",
                    formattedDate: accessibilityDateFormatter.string(from: day),
                    holidayNames: holidays.map(\.name),
                    courseDescriptions: courses.map { "\($0.timeRange)\($0.name)" }
                ),
                courses: courses,
                holiday: holidays.first,
                events: monthEvents(
                    dateKey: dateKey,
                    holidays: holidays,
                    assignments: assignments,
                    schoolNotices: schoolNotices,
                    publicDeadlines: publicDeadlines,
                    courses: courses
                ),
                allDayEvents: allDayEvents,
                deadlineKinds: CalendarDeadlinePresentation.topTwoDeadlineKinds(
                    in: allDayEvents
                )
            )
        }
    }

    private func cachedYearMonthSnapshots(for days: [Date]) -> MobileYearSnapshotCollection {
        let key = snapshotCacheKey(for: days, scope: "year-month")
        return snapshotCache.yearValues(for: key) {
            monthDaySnapshots(for: days)
        }
    }

    private func snapshotCacheKey(for days: [Date], scope: String) -> String {
        let firstDate = days.first.map { StrictContractDateParser.string(from: $0) } ?? "empty"
        let todayKey = StrictContractDateParser.string(from: .now)
        return "\(monthDataOwnerKey)|\(scope)|\(firstDate)|\(days.count)|" +
            "\(model.appLanguage.resolvedResourceName)|\(model.appLanguage.locale.identifier)|" +
            todayKey
    }

    private func monthEvents(
        dateKey: String,
        holidays: [HolidayItem],
        assignments: [AssignmentDeadlineItem],
        schoolNotices: [PublicDeadlineItem],
        publicDeadlines: [PublicDeadlineItem],
        courses: [Course]
    ) -> [MobileMonthEvent] {
        let holidayEvents = holidays.map { item in
            MobileMonthEvent(
                id: "holiday-\(item.id)",
                title: "\(model.localized(item.type == "holiday" ? "休" : "班")) \(item.name)",
                categoryKey: item.type == "holiday" ? "法定节假日" : "调休工作日",
                tint: item.type == "holiday" ? AppTheme.danger : AppTheme.primary
            )
        }
        let assignmentEvents = assignments.map { item in
            MobileMonthEvent(
                id: "\(dateKey)-assignment-\(item.id)",
                title: item.title,
                categoryKey: "课程作业 DDL",
                tint: AppTheme.assignment
            )
        }
        let schoolNoticeEvents = schoolNotices.map { item in
            MobileMonthEvent(
                id: "\(dateKey)-school-\(item.id)",
                title: item.name,
                categoryKey: "校内竞赛通知",
                tint: AppTheme.schoolNotice,
                deadlineItem: item
            )
        }
        let publicDeadlineEvents = publicDeadlines.map { item in
            MobileMonthEvent(
                id: "\(dateKey)-public-\(item.id)",
                title: item.name,
                categoryKey: item.kind.title,
                tint: CalendarDeadlinePresentation.tint(for: item),
                deadlineItem: item
            )
        }
        let courseEvents = courses.map { course in
            MobileMonthEvent(
                id: "course-\(course.id)",
                title: course.name,
                categoryKey: "课程详情",
                tint: AppTheme.primary
            )
        }
        return holidayEvents + assignmentEvents + schoolNoticeEvents
            + publicDeadlineEvents + courseEvents
    }

    private var yearView: some View {
        let year = calendar.component(.year, from: selectedDate)
        let months = (1 ... 12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }
        let columns = [GridItem(.adaptive(minimum: 152, maximum: 220), spacing: 16)]

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("颜色越深表示当天课程越多")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(months, id: \.self) { month in
                        yearMonth(month)
                    }
                }
            }
            .padding(16)
            .padding(
                .bottom,
                MobileCalendarYearLayout.contentBottomInset(
                    isLandscape: usesLandscapeMonthStops
                )
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.mobile.year")
    }

    private func yearMonth(_ month: Date) -> some View {
        let days = monthGridDates(containing: month)
        let snapshotsByDate = cachedYearMonthSnapshots(for: days).byDate
        return miniMonth(month, snapshotsByDate: snapshotsByDate)
    }

    private func miniMonth(
        _ month: Date,
        snapshotsByDate: [String: MobileMonthDaySnapshot]
    ) -> some View {
        let days = monthGridDates(containing: month)
        let monthTitle = monthFormatter.string(from: month)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 1), count: 7)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                jumpToMonth(month)
            } label: {
                HStack {
                    Text(monthTitle)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(monthTitle)")
            .accessibilityIdentifier(
                "calendar.mobile.year-month.\(Self.yearMonthKeyFormatter.string(from: month))"
            )
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Self.weekdayLabels, id: \.self) { label in
                    Text(model.localized(label))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                ForEach(days, id: \.self) { day in
                    yearDayButton(
                        day,
                        month: month,
                        snapshot: snapshotsByDate[StrictContractDateParser.string(from: day)]
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func yearDayButton(
        _ day: Date,
        month: Date,
        snapshot: MobileMonthDaySnapshot?
    ) -> some View {
        if calendar.isDate(day, equalTo: month, toGranularity: .month) {
            let count = snapshot?.courses.count ?? 0
            let today = sameDay(day, .now)
            let selected = sameDay(day, selectedDate)
            let deadlineKinds = snapshot?.deadlineKinds ?? []
            Button {
                AppHaptics.selection()
                selectedDate = day
                presentedDetail = MobileCalendarDetailSelection(date: day, content: .day)
            } label: {
                Text(snapshot?.dayNumberText ?? String(calendar.component(.day, from: day)))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(selected ? AppTheme.onPrimary : AppTheme.text)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(
                        selected
                            ? AppTheme.selectedDate
                            : AppTheme.primary.opacity(
                                TeachingCalendarLogic.yearCourseOpacity(courseCount: count)
                            )
                    )
                    .overlay {
                        ZStack {
                            if let outerKind = deadlineKinds.first {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(allDayEventTint(outerKind), lineWidth: 1.5)
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(AppTheme.border, lineWidth: 0.5)
                            }
                            if deadlineKinds.count > 1 {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(allDayEventTint(deadlineKinds[1]), lineWidth: 1)
                                    .padding(2)
                            }
                            if today {
                                Circle()
                                    .fill(AppTheme.danger)
                                    .frame(width: 4, height: 4)
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity,
                                        alignment: .topTrailing
                                    )
                                    .padding(2)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(snapshot?.accessibilityLabel ?? dayAccessibilityLabel(day))
            .accessibilityIdentifier(
                "calendar.mobile.year-day.\(StrictContractDateParser.string(from: day))"
            )
            .accessibilityValue(deadlineKinds.map(\.rawValue).joined(separator: ","))
        } else {
            Color.clear.frame(height: 24)
        }
    }

    private func daySummaryCard(_ day: Date) -> some View {
        let dayCourses = courses(on: day)
        let holidays = holidayItems(on: day)
        let dateKey = StrictContractDateParser.string(from: day)
        return VStack(alignment: .leading, spacing: 10) {
            Text("当日日程")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            ZStack(alignment: .leading) {
                Text(fullDateFormatter.string(from: day))
                    .id(dateKey)
                    .transition(.opacity)
                    .font(.headline)
            }
            .animation(Self.detailsContentAnimation, value: dateKey)
            ForEach(holidays) { item in
                Label(item.name, systemImage: item.type == "holiday" ? "calendar.badge.exclamationmark" : "briefcase")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.type == "holiday" ? AppTheme.danger : AppTheme.primary)
            }
            if dayCourses.isEmpty {
                Text("暂无课程")
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(dayCourses) { course in
                    Button {
                        presentCourse(course, on: day)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppTheme.primary)
                                .frame(width: 4, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name).font(.subheadline.weight(.semibold))
                                Text(
                                    [course.timeRange, CalendarTimelineLogic.courseMetadata(course)]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " · ")
                                )
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("calendar.mobile.month-day-summary-card")
        .accessibilityValue(StrictContractDateParser.string(from: day))
    }

    private func mobileAssignmentCard(
        _ day: Date,
        deadlineStore: CalendarDeadlineStore
    ) -> some View {
        let date = StrictContractDateParser.string(from: day)
        let items = deadlineStore.assignmentsByDate[date] ?? []
        return VStack(alignment: .leading, spacing: 10) {
            Label("课程作业 DDL", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            if items.isEmpty {
                Text(
                    deadlineStore.assignmentUnavailableByDate[date]
                        ?? "当天没有课程作业截止事项"
                )
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(AppTheme.primary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text([item.courseName, item.status].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Text(deadlineTime(item.deadline))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            HStack {
                Text("第三方来源：北邮云课堂")
                Spacer()
                Link("打开作业列表", destination: CalendarDeadlineSources.assignments)
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("calendar.mobile.assignments")
    }

    private func mobileDeadlineCard(
        _ day: Date,
        deadlineStore: CalendarDeadlineStore
    ) -> some View {
        let date = StrictContractDateParser.string(from: day)
        let builtInSnapshot = deadlineStore.publicByDate[date]
        let customSnapshot = deadlineStore.customByDate[date]
        let items = model.visibleDeadlineItems(
            liveItems: deadlineStore.publicItems(for: date),
            on: date
        )
        let isLoading = deadlineStore.loadingPublicDates.contains(date)
            || deadlineStore.loadingCustomDates.contains(date)
        let error = deadlineStore.publicErrors[date] ?? deadlineStore.customErrors[date]
        return VStack(alignment: .leading, spacing: 10) {
            Label("活动 DDL", systemImage: "flag.checkered")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityIdentifier("calendar.mobile.deadlines.header")
            if isLoading, builtInSnapshot == nil, customSnapshot == nil, items.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在同步活动截止信息…")
                }
                .foregroundStyle(AppTheme.secondaryText)
            } else if let error, builtInSnapshot == nil, customSnapshot == nil, items.isEmpty {
                Button {
                    Task {
                        if model.hasEnabledBuiltInPublicDeadlines {
                            await deadlineStore.loadPublic(
                                date: date,
                                sampleMode: model.isSampleMode,
                                force: true
                            )
                        }
                        if let sourceURL = model.customDeadlineSourceURL {
                            await deadlineStore.loadCustom(
                                dates: [date],
                                sourceURL: sourceURL,
                                force: true
                            )
                        }
                    }
                } label: {
                    Label("\(error)，点击重试", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
            } else if items.isEmpty {
                Text("当天没有已收录的活动截止事项")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(items) { item in
                    mobileDeadlineRow(item)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("第三方来源")
                Text("校内竞赛通知由脚本从学校内部网站公开通知页提取整理，仅供参考。")
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Link("Contest DDL", destination: CalendarDeadlineSources.primaryPage)
                        Link("备用 API", destination: CalendarDeadlineSources.backup)
                        Link("校内竞赛通知", destination: CalendarDeadlineSources.schoolNotices)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Link("Contest DDL", destination: CalendarDeadlineSources.primaryPage)
                        Link("备用 API", destination: CalendarDeadlineSources.backup)
                        Link("校内竞赛通知", destination: CalendarDeadlineSources.schoolNotices)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
            Group {
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
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.mobile.deadlines")
    }

    @ViewBuilder
    private func mobileDeadlineRow(_ item: PublicDeadlineItem) -> some View {
        HStack(alignment: .center, spacing: 6) {
            if let url = item.officialURL {
                Link(destination: url) { mobileDeadlineRowContent(item) }
                    .buttonStyle(.plain)
            } else {
                mobileDeadlineRowContent(item)
            }
            favoriteButton(item)
        }
    }

    private func mobileDeadlineRowContent(_ item: PublicDeadlineItem) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(CalendarDeadlinePresentation.tint(for: item))
                .frame(width: 20)
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
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
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

    private func weekAgendaDialog(_ selection: MobileWeekAgendaSelection) -> some View {
        centeredAgendaDialog(
            titleKey: "周视图全天日程",
            date: selection.date,
            accessibilityIdentifier: "calendar.mobile.week-agenda-dialog",
            dismiss: { presentedWeekAgenda = nil }
        ) {
            ForEach(selection.events) { event in
                agendaRow(
                    title: event.title,
                    categoryKey: allDayEventCategoryKey(event.kind),
                    tint: allDayEventTint(event.kind),
                    deadlineItem: event.deadlineItem
                )
            }
        }
    }

    private func centeredAgendaDialog<Rows: View>(
        titleKey: String,
        date: Date,
        accessibilityIdentifier: String,
        dismiss: @escaping () -> Void,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.localized(titleKey))
                            .font(.headline)
                        Text(fullDateFormatter.string(from: date))
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
                        rows()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
            }
            .padding(16)
            .frame(maxWidth: 380)
            .background(AppTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.black.opacity(0.24), radius: 20, y: 8)
            .padding(20)
            .contentShape(Rectangle())
            .onTapGesture { }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .zIndex(40)
    }

    private func agendaRow(
        title: String,
        categoryKey: String,
        tint: Color,
        deadlineItem: PublicDeadlineItem? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.localized(categoryKey))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if let deadlineItem {
                favoriteButton(deadlineItem)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func allDayEventCategoryKey(_ kind: CalendarAllDayEventKind) -> String {
        CalendarDeadlinePresentation.categoryKey(for: kind)
    }

    private func detailSheet(_ selection: MobileCalendarDetailSelection) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    switch selection.content {
                    case .day:
                        yearNavigationCommands(selection.date)
                        fullDayDetail(selection.date)
                    case let .course(course):
                        courseDetailCard(course, on: selection.date)
                    case let .holiday(holiday):
                        holidayDetailCard(holiday, on: selection.date)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle(detailTitle(selection))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { presentedDetail = nil }
                }
            }
        }
    }

    private func fullDayDetail(_ day: Date) -> some View {
        let holidays = holidayItems(on: day)
        let dayCourses = courses(on: day)
        let assignments = assignmentItems(on: day)
        let schoolNotices = schoolNoticeItems(on: day)
        let publicDeadlines = otherPublicDeadlineItems(on: day)
        return VStack(alignment: .leading, spacing: 12) {
            Text(fullDateFormatter.string(from: day))
                .font(.headline)
            ForEach(holidays) { holiday in
                holidayDetailCard(holiday, on: day)
            }
            ForEach(dayCourses) { course in
                courseDetailCard(course, on: day)
            }
            if !assignments.isEmpty {
                compactAssignmentDetail(assignments)
            }
            if !schoolNotices.isEmpty {
                compactSchoolNoticeDetail(schoolNotices)
            }
            if !publicDeadlines.isEmpty {
                compactPublicDeadlineDetail(publicDeadlines)
            }
            if holidays.isEmpty,
               dayCourses.isEmpty,
               assignments.isEmpty,
               schoolNotices.isEmpty,
               publicDeadlines.isEmpty {
                Text("暂无日程")
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactAssignmentDetail(_ items: [AssignmentDeadlineItem]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("课程作业 DDL", systemImage: "checklist")
                .font(.headline)
                .foregroundStyle(AppTheme.assignment)
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        if let courseName = item.courseName {
                            Text(courseName)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(deadlineTime(item.deadline))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.assignment.opacity(0.5)) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("calendar.mobile.day-detail.assignments")
    }

    private func compactSchoolNoticeDetail(_ items: [PublicDeadlineItem]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("校内竞赛通知", systemImage: "building.columns")
                .font(.headline)
                .foregroundStyle(AppTheme.schoolNotice)
            ForEach(items) { item in
                mobileDeadlineRow(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.schoolNotice.opacity(0.5)) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("calendar.mobile.day-detail.school-notices")
    }

    private func compactPublicDeadlineDetail(_ items: [PublicDeadlineItem]) -> some View {
        let kinds = CalendarDeadlinePresentation.topTwoDeadlineKinds(
            in: items.map { item in
                CalendarAllDayEvent(
                    id: item.favoriteID,
                    title: item.name,
                    kind: CalendarDeadlinePresentation.eventKind(for: item)
                )
            }
        )
        return VStack(alignment: .leading, spacing: 9) {
            Label("公开活动 DDL", systemImage: "flag.checkered")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            ForEach(items) { item in
                mobileDeadlineRow(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .overlay {
            ZStack {
                if let first = kinds.first {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(allDayEventTint(first).opacity(0.65), lineWidth: 1.5)
                }
                if kinds.count > 1 {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(allDayEventTint(kinds[1]).opacity(0.65), lineWidth: 1)
                        .padding(3)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("calendar.mobile.day-detail.public-deadlines")
    }

    private func courseDetailCard(_ course: Course, on day: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(course.name, systemImage: "book.closed")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            detailRow("日期", fullDateFormatter.string(from: day))
            detailRow("时间", course.timeRange)
            detailRow("节次", course.sectionText)
            detailRow("地点", course.room.isEmpty ? "未标注" : course.room)
            detailRow("教师", course.teacher.isEmpty ? "未标注" : course.teacher)
            detailRow("教学周", course.weekText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func holidayDetailCard(_ holiday: HolidayItem, on day: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                holiday.name,
                systemImage: holiday.type == "holiday" ? "calendar.badge.exclamationmark" : "briefcase"
            )
            .font(.headline)
            .foregroundStyle(holiday.type == "holiday" ? AppTheme.danger : AppTheme.primary)
            detailRow("日期", fullDateFormatter.string(from: day))
            detailRow("类型", holiday.type == "holiday" ? "法定节假日" : "调休工作日")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(model.localized(label))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 52, alignment: .leading)
            Text(value.isEmpty ? "未标注" : value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailTitle(_ selection: MobileCalendarDetailSelection) -> String {
        switch selection.content {
        case .day:
            monthDayCompactFormatter.string(from: selection.date)
        case .course:
            "课程详情"
        case .holiday:
            "日程详情"
        }
    }

    private func yearNavigationCommands(_ day: Date) -> some View {
        HStack(spacing: 8) {
            yearNavigationButton("日", mode: .day, day: day)
            yearNavigationButton("周", mode: .week, day: day)
            yearNavigationButton("月", mode: .month, day: day)
        }
        .frame(maxWidth: .infinity)
    }

    private func yearNavigationButton(
        _ title: String,
        mode targetMode: MobileCalendarMode,
        day: Date
    ) -> some View {
        Button(model.localized("\(title)视图")) {
            AppHaptics.selection()
            changeMode(to: targetMode, selecting: day)
            presentedDetail = nil
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("calendar.mobile.year-jump.\(targetMode.rawValue)")
    }

    private func jumpToMonth(_ month: Date) {
        AppHaptics.selection()
        changeMode(to: .month, selecting: month)
    }

    private func presentCourse(_ course: Course, on day: Date) {
        guard !suppressesEventSelection else { return }
        present(.course(course), on: day)
    }

    private func presentHoliday(_ holiday: HolidayItem, on day: Date) {
        guard !suppressesEventSelection else { return }
        present(.holiday(holiday), on: day)
    }

    private func present(_ content: MobileCalendarDetailSelection.Content, on day: Date) {
        AppHaptics.selection()
        presentedDetail = MobileCalendarDetailSelection(date: day, content: content)
    }

    private var periodTitle: String {
        TeachingCalendarLogic.periodTitle(
            for: selectedDate,
            // The compact header keeps the date readable beside its action
            // buttons; both week numbers live together in the dedicated row.
            modeRawValue: mode == .week ? MobileCalendarMode.month.rawValue : mode.rawValue,
            teachingWeekNumber: mode == .week ? nil : teachingWeekNumber(on: selectedDate),
            language: model.appLanguage,
            calendar: calendar
        )
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

    private func weekDates() -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func monthGridDates(containing date: Date) -> [Date] {
        snapshotCache.dates(inMonthContaining: date)
    }

    private func monthWeekIndex(
        selectedDateKey: String,
        in snapshots: [MobileMonthDaySnapshot]
    ) -> Int {
        guard let index = snapshots.firstIndex(where: { $0.dateKey == selectedDateKey }) else {
            return 0
        }
        return min(max(index / 7, 0), 5)
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

    private func moveDate(_ direction: Int) {
        let date = mode == .month
            ? session.monthNavigationDestination(direction: direction, calendar: calendar)
            : TeachingCalendarLogic.movedDate(
                from: selectedDate,
                unit: navigationUnit,
                direction: direction,
                calendar: calendar
            )
        if let date {
            AppHaptics.selection()
            if mode == .month {
                prepareMonthPageChange(
                    to: date,
                    direction: direction,
                    preservesMonthNavigationAnchor: true
                )
            } else {
                session.prepareTransition(direction: direction)
                withAnimation(TeachingCalendarNavigationMotion.pageAnimation) {
                    selectedDate = date
                }
            }
        }
    }

    private func navigate(to date: Date) {
        guard !sameDay(date, selectedDate) else { return }
        AppHaptics.selection()
        let direction = date > selectedDate ? 1 : -1
        if mode == .month {
            if let monthDirection = TeachingCalendarLogic.monthPageDirection(
                from: selectedDate,
                to: date,
                calendar: calendar
            ) {
                prepareMonthPageChange(to: date, direction: monthDirection)
            } else {
                session.prepareTransition(direction: direction)
                selectedDate = date
            }
        } else {
            session.prepareTransition(direction: direction)
            withAnimation(TeachingCalendarNavigationMotion.pageAnimation) {
                selectedDate = date
            }
        }
    }

    private func prepareMonthPageChange(
        to date: Date,
        direction: Int,
        preservesMonthNavigationAnchor: Bool = false
    ) {
        var window = monthPageWindow ?? MobileMonthPageWindow(selectedDate: selectedDate, calendar: calendar)
        let transition = preservesMonthNavigationAnchor
            ? window.request(direction: direction, animated: !reduceMotion)
            : window.request(to: date, animated: !reduceMotion)
        monthPageWindow = window
        if let transition {
            beginPreparedMonthTransition(transition)
        } else if window.transition == nil {
            session.commitMonthNavigation(to: window.selectedDate, preferredDay: window.preferredDayOfMonth)
        }
    }

    private var monthPreparationID: String {
        let window = monthPageWindow ?? MobileMonthPageWindow(selectedDate: selectedDate, calendar: calendar)
        return "\(monthDataOwnerKey)|\(window.centerMonth.timeIntervalSinceReferenceDate)|\(snapshotCache.generation)|\(StrictContractDateParser.string(from: .now))|\(window.transition?.generation.description ?? "idle")"
    }

    private var monthDataOwnerKey: String {
        "\(ObjectIdentifier(model))|\(ObjectIdentifier(calendarDeadlines))|\(model.calendarDataOwnerRevision)"
    }

    private func preparedSelectionDate(for month: Date, window: MobileMonthPageWindow) -> Date {
        if let transition = window.transition {
            if month == transition.sourceMonth { return frozenMonthDetailsDate ?? selectedDate }
            if month == transition.targetMonth { return transition.targetDate }
        }
        let lastDay = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        return calendar.date(byAdding: .day, value: min(window.preferredDayOfMonth, lastDay) - 1, to: month) ?? month
    }

    private func monthSkeleton(for days: [Date]) -> [MobileMonthDaySnapshot] {
        days.map { day in
            let key = StrictContractDateParser.string(from: day)
            return MobileMonthDaySnapshot(
                date: day, dateKey: key, dayNumberText: String(calendar.component(.day, from: day)),
                accessibilityLabel: key, courses: [], holiday: nil, events: [], allDayEvents: [], deadlineKinds: []
            )
        }
    }

    private func prepareMonthData(_ month: Date) async -> Bool {
        let days = monthGridDates(containing: month)
        let key = snapshotCacheKey(for: days, scope: "month")
        if snapshotCache.preparedMonth(for: key) != nil { return true }
        let years = Set(days.map { calendar.component(.year, from: $0) })
        let input = MobileMonthProjectionInput(
            days: days, schedule: model.schedule,
            holidays: years.flatMap { model.holidayItems(for: $0) },
            favorites: model.favoriteDeadlines,
            publicByDate: calendarDeadlines.publicByDate, customByDate: calendarDeadlines.customByDate,
            assignmentsByDate: calendarDeadlines.assignmentsByDate,
            visibility: MobileMonthSourceVisibility(
                competitionEnabled: model.competitionDeadlinesEnabled,
                schoolNoticeEnabled: model.schoolContestNoticesEnabled,
                conferenceEnabled: model.conferenceDeadlinesEnabled,
                summerCampEnabled: model.summerCampDeadlinesEnabled,
                hackathonEnabled: model.hackathonDeadlinesEnabled,
                customEnabled: model.customDeadlinesEnabled
            ), language: model.appLanguage, today: .now
        )
        return await snapshotCache.prepareMonth(for: key, input: input)
    }

    private func beginPreparedMonthTransition(_ transition: MobileMonthPageWindow.Transition) {
        monthPageTask?.cancel()
        frozenMonthDetailsDate = selectedDate
        let ownerRevision = model.calendarDataOwnerRevision
        monthPageTask = Task { @MainActor in
            while !Task.isCancelled {
                guard mode == .month, let window = monthPageWindow,
                      model.calendarDataOwnerRevision == ownerRevision,
                      window.transition?.generation == transition.generation else { return }
                let generation = snapshotCache.generation
                var prepared = [Date: [MobileMonthDaySnapshot]]()
                for page in window.pages {
                    guard await prepareMonthData(page.monthStart) else { break }
                    let days = monthGridDates(containing: page.monthStart)
                    prepared[page.monthStart] = snapshotCache.preparedMonth(for: snapshotCacheKey(for: days, scope: "month"))
                }
                guard !Task.isCancelled, model.calendarDataOwnerRevision == ownerRevision else { return }
                if generation != snapshotCache.generation || prepared.count != window.pages.count {
                    await Task.yield()
                    continue
                }
                frozenMonthGeneration = generation
                frozenMonthPages = prepared
                let targetLayout = "\(monthLayoutEpoch)|\(generation)|\(StrictContractDateParser.string(from: transition.targetDate))|true"
                let sourceLayout = "\(monthLayoutEpoch)|\(generation)|\(StrictContractDateParser.string(from: frozenMonthDetailsDate ?? selectedDate))|false"
                // Incoming data and an actual layout acknowledgement are both
                // required before changing the translation of the mounted pages.
                for _ in 0..<250 {
                    if monthPageReadiness[transition.targetMonth] == targetLayout,
                       monthPageReadiness[transition.sourceMonth] == sourceLayout { break }
                    do { try await Task.sleep(for: .milliseconds(8)) } catch { return }
                }
                guard !Task.isCancelled, mode == .month,
                      model.calendarDataOwnerRevision == ownerRevision,
                      monthPageWindow?.transition?.generation == transition.generation else { return }
                if generation != snapshotCache.generation {
                    await Task.yield()
                    continue
                }
                session.prepareTransition(direction: transition.direction)
                session.commitMonthNavigation(to: transition.targetDate, preferredDay: window.preferredDayOfMonth)
                guard monthPageReadiness[transition.targetMonth] == targetLayout,
                      monthPageReadiness[transition.sourceMonth] == sourceLayout else {
                    // An interrupted/offscreen viewport must not start a motion
                    // against unlaid-out content after the bounded wait.
                    finishMonthTransition(generation: transition.generation)
                    return
                }
                let duration = AppLaunchConfiguration.usesSlowCalendarAnimation ? 2.0 : 0.24
                if #available(iOS 17.0, *) {
                    withAnimation(.easeInOut(duration: duration), completionCriteria: .removed) {
                        monthPagingProgress = -CGFloat(transition.direction)
                    } completion: {
                        finishMonthTransition(generation: transition.generation)
                    }
                } else {
                    withAnimation(.easeInOut(duration: duration)) { monthPagingProgress = -CGFloat(transition.direction) }
                    do { try await Task.sleep(for: .seconds(duration)) } catch { return }
                    finishMonthTransition(generation: transition.generation)
                }
                return
            }
        }
    }

    private func finishMonthTransition(generation: UInt64) {
        guard var window = monthPageWindow, window.settle(generation: generation) else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            monthPageWindow = window
            monthPagingProgress = 0
            monthPageReadiness = monthPageReadiness.filter { entry in window.pages.contains { $0.monthStart == entry.key } }
            frozenMonthPages = frozenMonthPages.filter { entry in window.pages.contains { $0.monthStart == entry.key } }
            frozenMonthDetailsDate = nil
            resetMonthDetailsScroll()
        }
        if let pending = pendingMonthPosition {
            pendingMonthPosition = nil
            settleMonthPosition(to: pending)
        }
        if window.hasPendingNavigation {
            monthPageTask = Task { @MainActor in
                await Task.yield()
                guard mode == .month, var next = monthPageWindow,
                      next.transition == nil else { return }
                let transition = next.beginPendingNavigation(animated: !reduceMotion)
                monthPageWindow = next
                if let transition {
                    beginPreparedMonthTransition(transition)
                } else {
                    session.commitMonthNavigation(to: next.selectedDate, preferredDay: next.preferredDayOfMonth)
                }
            }
        }
    }

    private func rebaseMonthPages() {
        monthPageTask?.cancel()
        monthPageTask = nil
        var window = monthPageWindow ?? MobileMonthPageWindow(selectedDate: selectedDate, calendar: calendar)
        window.rebase(to: selectedDate, preservingMonthDayAnchor: window.selectedDate == selectedDate)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            monthPageWindow = window
            monthLayoutEpoch &+= 1
            monthPagingProgress = 0
            frozenMonthPages.removeAll()
            monthPageReadiness.removeAll()
            frozenMonthDetailsDate = nil
            pendingMonthPosition = nil
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
            .onChanged { value in
                trackPeriodDrag(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height
                )
            }
            .onEnded { value in
                defer { finishTrackedDrag() }
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

    private func monthNavigationGesture(
        travelDistance: CGFloat,
        detailsCanScrollBackward: Bool = false
    ) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                let detailsCanScrollBackwardAtStart =
                    monthDragRoutingSession.detailsCanScrollBackwardAtStart ??
                    monthDetailsScrollState.routingSnapshot(
                        fallback: detailsCanScrollBackward
                    )
                if monthDragRoutingSession.detailsCanScrollBackwardAtStart == nil {
                    monthDragRoutingSession.detailsCanScrollBackwardAtStart =
                        detailsCanScrollBackwardAtStart
                }
                guard !monthDragRoutingSession.isRoutedToDetails else { return }
                let axis = monthDragAxis ?? TeachingCalendarLogic.gestureAxis(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height
                )
                guard let axis else { return }
                if axis == .vertical,
                   TeachingCalendarLogic.routesMonthDragToDetails(
                       position: effectiveMonthPosition,
                       verticalTranslation: value.translation.height,
                       detailsCanScrollBackward: detailsCanScrollBackwardAtStart
                   ) {
                    monthDragRoutingSession.isRoutedToDetails = true
                    return
                }
                if axis == .vertical, monthPageWindow?.transition != nil { return }
                if monthDragAxis != axis { monthDragAxis = axis }
                if !suppressesEventSelection { suppressesEventSelection = true }
                switch axis {
                case .horizontal:
                    if !isHorizontalPaging { isHorizontalPaging = true }
                case .vertical:
                    monthDragTranslation = value.translation.height
                }
            }
            .onEnded { value in
                defer { finishTrackedDrag() }
                guard !monthDragRoutingSession.isRoutedToDetails else { return }
                if monthDragAxis == .horizontal,
                   let direction = TeachingCalendarLogic.swipeDirection(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height,
                    predictedHorizontalTranslation: value.predictedEndTranslation.width
                ) {
                    moveDate(direction)
                    return
                }

                guard monthDragAxis == .vertical else { return }
                let position = TeachingCalendarLogic.monthPosition(
                    isExpanded: effectiveMonthPosition == .expanded,
                    isDetailRaised: effectiveMonthPosition == .detailRaised,
                    verticalTranslation: value.translation.height * (usesLandscapeMonthStops ? 2 : 1),
                    travelDistance: travelDistance
                )
                let target = TeachingCalendarLogic.settledMonthPosition(
                    position: position,
                    verticalTranslation: value.translation.height,
                    predictedVerticalTranslation: value.predictedEndTranslation.height,
                    allowsIntermediatePosition: !usesLandscapeMonthStops
                )
                settleMonthPosition(to: target)
            }
    }

    private func trackPeriodDrag(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat
    ) {
        guard let axis = TeachingCalendarLogic.gestureAxis(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation
        ) else { return }
        suppressesEventSelection = true
        if axis == .horizontal {
            isHorizontalPaging = true
        }
    }

    private func finishTrackedDrag() {
        isHorizontalPaging = false
        monthDragAxis = nil
        monthDragRoutingSession.reset()
        let suppressionID = UUID()
        eventSelectionSuppressionID = suppressionID
        Task { @MainActor in
            await Task.yield()
            guard eventSelectionSuppressionID == suppressionID else { return }
            suppressesEventSelection = false
        }
    }

    private var modeSelection: Binding<MobileCalendarMode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode else { return }
                AppHaptics.selection()
                changeMode(to: newMode)
            }
        )
    }

    private func changeMode(to newMode: MobileCalendarMode, selecting date: Date? = nil) {
        Task { @MainActor in
            await session.requestModeChange(to: newMode.rawValue, selecting: date)
        }
    }

    private var currentMonthPosition: TeachingCalendarLogic.MonthPosition {
        if isMonthExpanded { return .expanded }
        return isMonthDetailRaised ? .detailRaised : .collapsed
    }

    private var effectiveMonthPosition: TeachingCalendarLogic.MonthPosition {
        TeachingCalendarLogic.normalizedMonthPosition(
            currentMonthPosition,
            allowsIntermediatePosition: !usesLandscapeMonthStops
        )
    }

    private var monthAccessibilityValue: String {
        switch effectiveMonthPosition {
        case .expanded: "已展开"
        case .collapsed: "已收起"
        case .detailRaised: "日程已展开"
        }
    }

    private func settleMonthPosition(to target: TeachingCalendarLogic.MonthPosition) {
        if monthPageWindow?.transition != nil {
            pendingMonthPosition = target
            return
        }
        let normalizedTarget = TeachingCalendarLogic.normalizedMonthPosition(
            target,
            allowsIntermediatePosition: !usesLandscapeMonthStops
        )
        guard TeachingCalendarLogic.requiresMonthPositionUpdate(
            current: currentMonthPosition,
            target: normalizedTarget,
            verticalTranslation: monthDragTranslation
        ) else {
            return
        }
        if normalizedTarget != effectiveMonthPosition { AppHaptics.selection() }
        withAnimation(Self.monthExpansionAnimation) {
            monthDragTranslation = 0
            let expandsMonth = normalizedTarget == .expanded
            let raisesDetails = normalizedTarget == .detailRaised
            if isMonthExpanded != expandsMonth {
                isMonthExpanded = expandsMonth
            }
            if isMonthDetailRaised != raisesDetails {
                isMonthDetailRaised = raisesDetails
            }
        }
    }

    private func normalizeMonthPositionForLayout() {
        guard effectiveMonthPosition != currentMonthPosition else { return }
        settleMonthPosition(to: effectiveMonthPosition)
    }

    private func selectMonthDay(_ day: Date) {
        if sameDay(day, selectedDate) {
            resetMonthDetailsScroll()
        }
        navigate(to: day)
        settleMonthPosition(to: usesLandscapeMonthStops ? .detailRaised : .collapsed)
    }

    private func requestMonthDaySelection(_ day: Date) {
        guard !suppressesEventSelection else { return }
        selectMonthDay(day)
    }

    private func resetMonthDetailsScroll() {
        monthDetailsCanScrollBackward = false
        monthDetailsScrollResetID = UUID()
    }

    private var contentIdentity: String {
        MobileCalendarAnimationPartition.contentIdentity(
            modeRawValue: mode.rawValue,
            selectedDate: selectedDate,
            calendar: calendar
        )
    }

    private var monthGridIdentity: String {
        MobileCalendarAnimationPartition.monthGridIdentity(
            selectedDate: selectedDate,
            calendar: calendar
        )
    }

    private var weekContextText: String {
        TeachingCalendarLogic.weekContext(
            for: selectedDate,
            teachingWeekNumber: teachingWeekNumber(on: selectedDate),
            language: model.appLanguage,
            calendar: calendar
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

    private var pageTransition: AnyTransition {
        TeachingCalendarNavigationMotion.transition(direction: session.transitionDirection)
    }

    private func dateStripForeground(holiday: HolidayItem?) -> Color {
        guard let holiday else { return AppTheme.text }
        return holiday.type == "holiday" ? AppTheme.danger : AppTheme.primary
    }

    private func dayAccessibilityLabel(_ day: Date) -> String {
        TeachingCalendarLogic.dayAccessibilityLabel(
            todayText: sameDay(day, .now) ? model.localized("今天") : "",
            formattedDate: fullDateFormatter.string(from: day),
            holidayNames: holidayItems(on: day).map(\.name),
            courseDescriptions: courses(on: day).map { "\($0.timeRange)\($0.name)" }
        )
    }

    private func sameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
    private static let viewAnimation = TeachingCalendarNavigationMotion.pageAnimation
    private static let pageAnimation = TeachingCalendarNavigationMotion.pageAnimation
    private static let monthExpansionAnimation = Animation.easeInOut(duration: 0.28)
    private static let detailsContentAnimation = Animation.easeOut(duration: 0.16)
    private static let yearMonthKeyFormatter = formatter("yyyy-MM")
    private var usesEnglishFormatting: Bool {
        model.appLanguage.resolvedResourceName == "en"
    }
    private var fullDateFormatter: DateFormatter {
        dateFormatterCache.formatter(
            format: usesEnglishFormatting ? "EEEE, MMMM d, yyyy" : "yyyy年M月d日 EEEE",
            locale: model.appLanguage.locale
        )
    }

    private var monthFormatter: DateFormatter {
        dateFormatterCache.formatter(
            format: usesEnglishFormatting ? "MMM" : "M月",
            locale: model.appLanguage.locale
        )
    }

    private var monthDayCompactFormatter: DateFormatter {
        dateFormatterCache.formatter(
            format: usesEnglishFormatting ? "MMM d" : "M月d日",
            locale: model.appLanguage.locale
        )
    }

    private var weekdayFormatter: DateFormatter {
        dateFormatterCache.formatter(format: "E", locale: model.appLanguage.locale)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = format
        return formatter
    }
}

private struct MobileDeadlineStoreContent<Content: View>: View {
    @EnvironmentObject private var deadlineStore: CalendarDeadlineStore
    private let content: (CalendarDeadlineStore) -> Content

    init(@ViewBuilder content: @escaping (CalendarDeadlineStore) -> Content) {
        self.content = content
    }

    var body: some View {
        content(deadlineStore)
    }
}

private struct MobileAlmanacCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var dailyInfo: DailyInfoStore
    let day: Date

    var body: some View {
        let date = StrictContractDateParser.string(from: day)
        VStack(alignment: .leading, spacing: 10) {
            Label("黄历信息", systemImage: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            if dailyInfo.loadingAlmanacDates.contains(date), dailyInfo.almanacByDate[date] == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在查询…")
                }
                .foregroundStyle(AppTheme.secondaryText)
            } else if let error = dailyInfo.almanacErrors[date], dailyInfo.almanacByDate[date] == nil {
                Button {
                    Task {
                        await dailyInfo.loadAlmanac(
                            date: date,
                            sampleMode: model.isSampleMode,
                            force: true
                        )
                    }
                } label: {
                    Label("\(error)，点击重试", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
            } else if let info = dailyInfo.almanacByDate[date] {
                Text("农历 \(info.lunarDate) · \(info.weekday)")
                    .font(.headline)
                Text("\(info.ganzhiYear)年 · \(info.ganzhiMonth)月 · \(info.ganzhiDay)日 · 肖\(info.zodiac)")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                let festival = [info.solarTerm, info.lunarFestival, info.solarFestival]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                if !festival.isEmpty {
                    Text(festival)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                if let yi = info.yi {
                    adviceRow("宜", value: yi, color: AppTheme.primary)
                }
                if let ji = info.ji {
                    adviceRow("忌", value: ji, color: AppTheme.danger)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("民俗信息仅供参考 · 第三方来源")
                HStack {
                    Link(
                        "农历：UAPI",
                        destination: URL(
                            string: "https://uapis.cn/docs/api-reference/get-misc-lunartime"
                        )!
                    )
                    Link(
                        "宜忌：Timeless",
                        destination: URL(string: "https://api.timelessq.com/docs/api-15277838")!
                    )
                }
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("calendar.mobile.almanac")
    }

    private func adviceRow(_ title: String, value: String, color: Color) -> some View {
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
        .padding(9)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MobileMonthDetailsScrollConfiguration: UIViewRepresentable {
    @Binding var canScrollBackward: Bool
    let resetID: UUID
    let scrollState: MobileMonthDetailsScrollState

    func makeCoordinator() -> Coordinator {
        Coordinator(
            canScrollBackward: $canScrollBackward,
            resetID: resetID,
            scrollState: scrollState
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        context.coordinator.scheduleAttachmentIfNeeded(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.canScrollBackward = $canScrollBackward
        context.coordinator.scrollState = scrollState
        context.coordinator.requestReset(resetID)
        context.coordinator.scheduleAttachmentIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject {
        var canScrollBackward: Binding<Bool>
        var scrollState: MobileMonthDetailsScrollState
        private var requestedResetID: UUID
        private var appliedResetID: UUID?
        private weak var scrollView: UIScrollView?
        private var attachmentScheduled = false
        private var isActive = true

        init(
            canScrollBackward: Binding<Bool>,
            resetID: UUID,
            scrollState: MobileMonthDetailsScrollState
        ) {
            self.canScrollBackward = canScrollBackward
            requestedResetID = resetID
            self.scrollState = scrollState
        }

        func scheduleAttachmentIfNeeded(from view: UIView) {
            guard isActive, scrollView == nil, !attachmentScheduled else { return }
            attachmentScheduled = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, self.isActive else { return }
                self.attachmentScheduled = false
                guard self.scrollView == nil else { return }

                var ancestor = view.superview
                while let current = ancestor {
                    if let scrollView = current as? UIScrollView {
                        scrollView.bounces = false
                        scrollView.alwaysBounceVertical = false
                        scrollView.showsVerticalScrollIndicator = false
                        scrollView.showsHorizontalScrollIndicator = false
                        self.observe(scrollView)
                        return
                    }
                    ancestor = current.superview
                }
            }
        }

        func requestReset(_ resetID: UUID) {
            requestedResetID = resetID
            applyPendingResetIfNeeded()
        }

        func observe(_ scrollView: UIScrollView) {
            guard self.scrollView !== scrollView else {
                applyPendingResetIfNeeded()
                updateScrollState(scrollView)
                return
            }
            self.scrollView?.panGestureRecognizer.removeTarget(
                self,
                action: #selector(scrollViewDidPan(_:))
            )
            scrollState.detach(self.scrollView)
            self.scrollView = scrollView
            scrollState.attach(scrollView)
            scrollView.panGestureRecognizer.addTarget(
                self,
                action: #selector(scrollViewDidPan(_:))
            )
            applyPendingResetIfNeeded()
            updateScrollState(scrollView)
        }

        func stopObserving() {
            isActive = false
            attachmentScheduled = false
            scrollView?.panGestureRecognizer.removeTarget(
                self,
                action: #selector(scrollViewDidPan(_:))
            )
            scrollState.detach(scrollView)
            scrollView = nil
        }

        @objc private func scrollViewDidPan(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            scrollState.recordPan(recognizer)
            updateScrollState(scrollView)
        }

        private func updateScrollState(_ scrollView: UIScrollView) {
            let topOffset = -scrollView.adjustedContentInset.top
            let canScrollBackward = scrollView.contentOffset.y > topOffset + 1
            guard self.canScrollBackward.wrappedValue != canScrollBackward else { return }
            self.canScrollBackward.wrappedValue = canScrollBackward
        }

        private func applyPendingResetIfNeeded() {
            guard appliedResetID != requestedResetID, let scrollView else { return }
            appliedResetID = requestedResetID
            let topOffset = -scrollView.adjustedContentInset.top
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: topOffset),
                animated: false
            )
            updateScrollState(scrollView)
        }

    }
}
#endif
