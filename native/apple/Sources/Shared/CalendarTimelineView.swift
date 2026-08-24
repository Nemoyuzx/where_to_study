import SwiftUI

enum CalendarAllDayEventKind: String, Equatable, Sendable {
    case holiday
    case workday
    case assignment
    case schoolNotice
    case publicDeadline
}

struct CalendarAllDayEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: CalendarAllDayEventKind
    let deadlineItem: PublicDeadlineItem?

    init(
        id: String,
        title: String,
        kind: CalendarAllDayEventKind,
        deadlineItem: PublicDeadlineItem? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.deadlineItem = deadlineItem
    }
}

enum CalendarDeadlinePresentation {
    private static let deadlinePriority: [CalendarAllDayEventKind] = [
        .assignment,
        .schoolNotice,
        .publicDeadline,
    ]

    static func isVisible(
        _ item: PublicDeadlineItem,
        competitionEnabled: Bool,
        schoolNoticeEnabled: Bool,
        summerCampEnabled: Bool,
        hackathonEnabled: Bool,
        customEnabled: Bool = false
    ) -> Bool {
        if item.source == .schoolNotice { return schoolNoticeEnabled }
        if item.source == .custom { return customEnabled }
        switch item.kind {
        case .competition: return competitionEnabled
        case .summerCamp: return summerCampEnabled
        case .hackathon: return hackathonEnabled
        case .custom: return customEnabled
        }
    }

    static func preferredDeadlineKind(
        in events: [CalendarAllDayEvent]
    ) -> CalendarAllDayEventKind? {
        topTwoDeadlineKinds(in: events).first
    }

    static func topTwoDeadlineKinds(
        in events: [CalendarAllDayEvent]
    ) -> [CalendarAllDayEventKind] {
        Array(
            deadlinePriority
                .filter { kind in events.contains(where: { $0.kind == kind }) }
                .prefix(2)
        )
    }

    static func showsSecondaryTodayIndicator(
        isToday: Bool,
        deadlineKind: CalendarAllDayEventKind?
    ) -> Bool {
        isToday && deadlineKind != nil
    }
}

struct CalendarTimelineDay: Identifiable {
    let date: Date
    let courses: [Course]
    let holidays: [HolidayItem]
    let allDayEvents: [CalendarAllDayEvent]

    init(
        date: Date,
        courses: [Course],
        holidays: [HolidayItem],
        allDayEvents: [CalendarAllDayEvent]? = nil
    ) {
        self.date = date
        self.courses = courses
        self.holidays = holidays
        self.allDayEvents = allDayEvents ?? holidays.map { holiday in
            CalendarAllDayEvent(
                id: "holiday-\(holiday.id)",
                title: "\(holiday.type == "holiday" ? "休" : "班") \(holiday.name)",
                kind: holiday.type == "holiday" ? .holiday : .workday
            )
        }
    }

    var id: Date { date }
}

enum CalendarTimelineLogic {
    static let startMinute = 8 * 60
    static let endMinute = 22 * 60

    static func minute(of value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0 ... 23).contains(hour),
            (0 ... 59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    static func position(minute: Int) -> CGFloat {
        let raw = CGFloat(minute - startMinute) / CGFloat(endMinute - startMinute)
        return min(max(raw, 0), 1)
    }

    static func hourLabelIsObscured(
        hourMinute: Int,
        currentMinute: Int,
        threshold: Int = 12
    ) -> Bool {
        abs(hourMinute - currentMinute) <= threshold
    }

    static func mobileViewportHeight(
        compactWidth: Bool,
        compactHeight: Bool
    ) -> CGFloat {
        if compactHeight { return 300 }
        return compactWidth ? 420 : 700
    }

    static func minimumDayAreaWidth(
        dayCount: Int,
        minimumDayWidth: CGFloat
    ) -> CGFloat {
        guard dayCount > 1 else { return 160 }
        return CGFloat(dayCount) * minimumDayWidth
    }

    static var wholeHourMinutes: [Int] {
        Array(stride(from: startMinute, through: endMinute, by: 60))
    }

    static var courseBoundaryMinutes: [Int] {
        Array(Set(SlotMetadata.defaults.flatMap { slot in
            [minute(of: slot.start), minute(of: slot.end)].compactMap { $0 }
        })).sorted()
    }

    static var nonHourlyCourseBoundaryMinutes: [Int] {
        courseBoundaryMinutes.filter { $0 % 60 != 0 }
    }

    static func courseMetadata(_ course: Course) -> String {
        [course.room, course.teacher.isEmpty ? "" : "教师：\(course.teacher)"]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct CalendarTimelineView: View {
    @EnvironmentObject private var model: AppModel
    let days: [CalendarTimelineDay]
    let selectedDate: Date
    var onSelectDay: ((Date) -> Void)?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    private let calendar = Calendar.shanghai
    private let hourAxisWidth: CGFloat = 52
    private let slotAxisWidth: CGFloat = 104
    private let headerHeight: CGFloat = 72
    private let hourHeight: CGFloat = 64

    private var timelineHeight: CGFloat { hourHeight * 14 }
    private var totalHeight: CGFloat { headerHeight + timelineHeight + 2 }
    private var contentLeft: CGFloat { hourAxisWidth + slotAxisWidth }
    private var minimumDayAreaWidth: CGFloat {
        #if os(iOS)
        CalendarTimelineLogic.minimumDayAreaWidth(dayCount: days.count, minimumDayWidth: 96)
        #else
        CalendarTimelineLogic.minimumDayAreaWidth(dayCount: days.count, minimumDayWidth: 118)
        #endif
    }

    var body: some View {
        #if os(iOS)
        ScrollView(.vertical, showsIndicators: true) {
            timelineContent
        }
        .frame(height: min(totalHeight, mobileViewportHeight))
        .accessibilityElement(children: .contain)
        #else
        ScrollView(.vertical, showsIndicators: true) {
            timelineContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("calendar.desktop.timeline-scroll")
        .accessibilityElement(children: .contain)
        #endif
    }

    private var timelineContent: some View {
        GeometryReader { proxy in
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                HStack(alignment: .top, spacing: 0) {
                    axisContent(now: timeline.date)
                    ScrollView(.horizontal, showsIndicators: days.count > 1) {
                        dayContent(
                            width: max(proxy.size.width - contentLeft, minimumDayAreaWidth),
                            now: timeline.date
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: totalHeight)
    }

    #if os(iOS)
    private var mobileViewportHeight: CGFloat {
        CalendarTimelineLogic.mobileViewportHeight(
            compactWidth: horizontalSizeClass == .compact,
            compactHeight: verticalSizeClass == .compact
        )
    }
    #endif

    private func axisContent(now: Date) -> some View {
        ZStack(alignment: .topLeading) {
            AppTheme.surface
            axisGrid
            axisHeaders
            hourLabels(now: now)
            slotLabels
            currentTimeAxisLabel(now: now)
        }
        .frame(width: contentLeft, height: totalHeight)
        .clipped()
    }

    private func dayContent(width: CGFloat, now: Date) -> some View {
        let dayWidth = width / CGFloat(max(days.count, 1))
        return ZStack(alignment: .topLeading) {
            AppTheme.surface
            selectedColumn(dayWidth: dayWidth)
            dayGrid(width: width, dayWidth: dayWidth)
            dayHeaders(dayWidth: dayWidth, now: now)
            courseBlocks(dayWidth: dayWidth)
            currentTimeLine(width: width, dayWidth: dayWidth, now: now)
        }
        .frame(width: width, height: totalHeight)
        .clipped()
    }

    @ViewBuilder
    private func selectedColumn(dayWidth: CGFloat) -> some View {
        if let index = days.firstIndex(where: {
            calendar.isDate($0.date, inSameDayAs: selectedDate)
        }) {
            Rectangle()
                .fill(AppTheme.selectedDate.opacity(0.10))
                .frame(width: dayWidth, height: totalHeight)
                .offset(x: CGFloat(index) * dayWidth)
                .allowsHitTesting(false)
        }
    }

    private var axisGrid: some View {
        Canvas { context, _ in
            context.fill(
                Path(CGRect(x: 0, y: 0, width: contentLeft, height: headerHeight)),
                with: .color(AppTheme.background)
            )
            var structure = Path()
            structure.move(to: CGPoint(x: 0, y: headerHeight))
            structure.addLine(to: CGPoint(x: contentLeft, y: headerHeight))
            structure.move(to: CGPoint(x: hourAxisWidth, y: 0))
            structure.addLine(to: CGPoint(x: hourAxisWidth, y: totalHeight))
            structure.move(to: CGPoint(x: contentLeft, y: 0))
            structure.addLine(to: CGPoint(x: contentLeft, y: totalHeight))
            context.stroke(structure, with: .color(AppTheme.border), lineWidth: 1)

            var hourLines = Path()
            for minute in CalendarTimelineLogic.wholeHourMinutes {
                let y = yPosition(minute: minute)
                hourLines.move(to: CGPoint(x: 0, y: y))
                hourLines.addLine(to: CGPoint(x: contentLeft, y: y))
            }
            context.stroke(hourLines, with: .color(AppTheme.border), lineWidth: 1)

            var slotLines = Path()
            for minute in CalendarTimelineLogic.nonHourlyCourseBoundaryMinutes {
                let y = yPosition(minute: minute)
                slotLines.move(to: CGPoint(x: hourAxisWidth, y: y))
                slotLines.addLine(to: CGPoint(x: contentLeft, y: y))
            }
            context.stroke(
                slotLines,
                with: .color(AppTheme.secondaryText.opacity(0.30)),
                style: StrokeStyle(lineWidth: 0.7, dash: [4, 4])
            )
        }
    }

    private func dayGrid(width: CGFloat, dayWidth: CGFloat) -> some View {
        Canvas { context, _ in
            context.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: headerHeight)),
                with: .color(AppTheme.background)
            )
            var structure = Path()
            structure.move(to: CGPoint(x: 0, y: headerHeight))
            structure.addLine(to: CGPoint(x: width, y: headerHeight))
            for index in 0 ... max(days.count, 1) {
                let x = CGFloat(index) * dayWidth
                structure.move(to: CGPoint(x: x, y: 0))
                structure.addLine(to: CGPoint(x: x, y: totalHeight))
            }
            context.stroke(structure, with: .color(AppTheme.border), lineWidth: 1)

            var hourLines = Path()
            for minute in CalendarTimelineLogic.wholeHourMinutes {
                let y = yPosition(minute: minute)
                hourLines.move(to: CGPoint(x: 0, y: y))
                hourLines.addLine(to: CGPoint(x: width, y: y))
            }
            context.stroke(hourLines, with: .color(AppTheme.border), lineWidth: 1)

            var slotLines = Path()
            for minute in CalendarTimelineLogic.nonHourlyCourseBoundaryMinutes {
                let y = yPosition(minute: minute)
                slotLines.move(to: CGPoint(x: 0, y: y))
                slotLines.addLine(to: CGPoint(x: width, y: y))
            }
            context.stroke(
                slotLines,
                with: .color(AppTheme.secondaryText.opacity(0.30)),
                style: StrokeStyle(lineWidth: 0.7, dash: [4, 4])
            )
        }
    }

    private var axisHeaders: some View {
        Group {
            Text("整点")
                .font(.caption.bold())
                .frame(width: hourAxisWidth, height: headerHeight)
                .position(x: hourAxisWidth / 2, y: headerHeight / 2)
            Text("课程节次")
                .font(.caption.bold())
                .frame(width: slotAxisWidth, height: headerHeight)
                .position(x: hourAxisWidth + slotAxisWidth / 2, y: headerHeight / 2)
        }
        .foregroundStyle(AppTheme.text)
    }

    private func hourLabels(now: Date) -> some View {
        let currentMinute = currentMinuteIfVisible(now)
        return ForEach(8 ... 22, id: \.self) { hour in
            let hourMinute = hour * 60
            let rawY = yPosition(minute: hourMinute)
            let y = hour == 8 ? rawY + 10 : (hour == 22 ? rawY - 7 : rawY - 5)
            if currentMinute.map({
                CalendarTimelineLogic.hourLabelIsObscured(
                    hourMinute: hourMinute,
                    currentMinute: $0
                )
            }) != true {
                Text(String(format: "%02d:00", hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: hourAxisWidth - 4)
                    .position(x: hourAxisWidth / 2, y: y)
            }
        }
    }

    private var slotLabels: some View {
        ForEach(SlotMetadata.defaults) { slot in
            if let start = CalendarTimelineLogic.minute(of: slot.start),
               let end = CalendarTimelineLogic.minute(of: slot.end) {
                VStack(spacing: 1) {
                    Text("第 \(slot.label) 节").font(.caption2.bold())
                    Text("\(slot.start)-\(slot.end)")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: slotAxisWidth - 4)
                .position(
                    x: hourAxisWidth + slotAxisWidth / 2,
                    y: (yPosition(minute: start) + yPosition(minute: end)) / 2
                )
            }
        }
    }

    private func dayHeaders(dayWidth: CGFloat, now: Date) -> some View {
        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
            let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)
            let isToday = calendar.isDate(day.date, inSameDayAs: now)
            Button {
                onSelectDay?(day.date)
            } label: {
                VStack(spacing: 5) {
                    Text(dayHeaderFormatter.string(from: day.date))
                        .font(.caption.bold())
                        .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.text)
                    Text(headerDetail(for: day))
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? AppTheme.onPrimary : headerDetailColor(for: day))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 4)
                .frame(width: dayWidth, height: headerHeight)
                .background(isSelected ? AppTheme.selectedDate : Color.clear)
                .overlay(alignment: .bottom) {
                    if isToday {
                        Rectangle().fill(Self.nowRed).frame(height: 3).padding(.horizontal, 6)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(onSelectDay == nil)
            .position(
                x: dayWidth * (CGFloat(index) + 0.5),
                y: headerHeight / 2
            )
            .accessibilityLabel(dayAccessibilityLabel(day))
        }
    }

    private func courseBlocks(dayWidth: CGFloat) -> some View {
        ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
            let placements = placeCourses(day.courses)
            let trackCount = max(placements.map(\.track).max().map { $0 + 1 } ?? 1, 1)
            ForEach(placements) { placement in
                if let start = SlotMetadata.defaults[safe: placement.course.startSlot]
                    .flatMap({ CalendarTimelineLogic.minute(of: $0.start) }),
                   let end = SlotMetadata.defaults[safe: placement.course.endSlot]
                    .flatMap({ CalendarTimelineLogic.minute(of: $0.end) }) {
                    let trackWidth = dayWidth / CGFloat(trackCount)
                    let x = CGFloat(dayIndex) * dayWidth
                        + CGFloat(placement.track) * trackWidth
                        + 3
                    let top = yPosition(minute: start) + 2
                    let bottom = max(top + 34, yPosition(minute: end) - 2)
                    courseBlock(
                        placement: placement,
                        trackWidth: trackWidth,
                        x: x,
                        top: top,
                        bottom: bottom
                    )
                }
            }
        }
    }

    private func courseBlock(
        placement: CoursePlacement,
        trackWidth: CGFloat,
        x: CGFloat,
        top: CGFloat,
        bottom: CGFloat
    ) -> some View {
        let blockWidth = max(trackWidth - 6, 20)
        let blockHeight = bottom - top
        let isSingleDay = days.count == 1
        let metadata = CalendarTimelineLogic.courseMetadata(placement.course)
        let background = placement.track == 0
            ? AppTheme.primaryFill
            : AppTheme.primaryFill.opacity(0.86)

        return VStack(alignment: .leading, spacing: 1) {
            Text(placement.course.name)
                .font(.system(size: isSingleDay ? 11 : 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if blockHeight >= 38 {
                Text(placement.course.timeRange)
                    .font(.system(size: isSingleDay ? 9 : 8, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if blockHeight >= 42, !metadata.isEmpty {
                Text(metadata)
                    .font(.system(size: isSingleDay ? 9 : 8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .foregroundStyle(AppTheme.onPrimary)
        .padding(isSingleDay ? 5 : 4)
        .frame(width: blockWidth, height: blockHeight, alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .position(x: x + blockWidth / 2, y: (top + bottom) / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(placement.course.timeRange)，\(placement.course.name)，\(metadata)"
        )
    }

    @ViewBuilder
    private func currentTimeLine(width: CGFloat, dayWidth: CGFloat, now: Date) -> some View {
        let todayIndex = days.firstIndex { calendar.isDate($0.date, inSameDayAs: now) }
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if let todayIndex,
           (CalendarTimelineLogic.startMinute ... CalendarTimelineLogic.endMinute).contains(minute) {
            let y = yPosition(minute: minute)
            let left = CGFloat(todayIndex) * dayWidth
            Path { path in
                path.move(to: CGPoint(x: left, y: y))
                path.addLine(to: CGPoint(x: min(left + dayWidth, width), y: y))
            }
            .stroke(Self.nowRed, lineWidth: 2)
            Circle()
                .fill(Self.nowRed)
                .frame(width: 8, height: 8)
                .position(x: left, y: y)
        }
    }

    @ViewBuilder
    private func currentTimeAxisLabel(now: Date) -> some View {
        if let minute = currentMinuteIfVisible(now) {
            Text(timeFormatter.string(from: now))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppTheme.onPrimary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(Self.nowRed))
                .fixedSize()
                .frame(width: hourAxisWidth)
                .position(x: hourAxisWidth / 2, y: yPosition(minute: minute))
        }
    }

    private func currentMinuteIfVisible(_ now: Date) -> Int? {
        guard days.contains(where: { calendar.isDate($0.date, inSameDayAs: now) }) else {
            return nil
        }
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        guard (CalendarTimelineLogic.startMinute ... CalendarTimelineLogic.endMinute).contains(minute) else {
            return nil
        }
        return minute
    }

    private func yPosition(minute: Int) -> CGFloat {
        headerHeight + timelineHeight * CalendarTimelineLogic.position(minute: minute)
    }

    private func placeCourses(_ courses: [Course]) -> [CoursePlacement] {
        var trackEnds = [Int]()
        return courses.sorted {
            ($0.startSlot, $0.endSlot, $0.name) < ($1.startSlot, $1.endSlot, $1.name)
        }.map { course in
            let track = trackEnds.firstIndex(where: { $0 < course.startSlot }) ?? trackEnds.count
            if track == trackEnds.count {
                trackEnds.append(course.endSlot)
            } else {
                trackEnds[track] = course.endSlot
            }
            return CoursePlacement(course: course, track: track)
        }
    }

    private func headerDetail(for day: CalendarTimelineDay) -> String {
        guard !day.courses.isEmpty else { return model.localized("无课") }
        return model.appLanguage.resolvedResourceName == "en"
            ? "\(day.courses.count) courses"
            : "\(day.courses.count) 门课"
    }

    private func headerDetailColor(for day: CalendarTimelineDay) -> Color {
        if !day.courses.isEmpty { return AppTheme.primary }
        return AppTheme.secondaryText
    }

    private func dayAccessibilityLabel(_ day: CalendarTimelineDay) -> String {
        let holidays = day.holidays.map(\.name).joined(separator: "，")
        let courses = day.courses.map { "\($0.timeRange)\($0.name)" }.joined(separator: "，")
        return [accessibleDateFormatter.string(from: day.date), holidays, courses.isEmpty ? model.localized("无课") : courses]
            .filter { !$0.isEmpty }
            .joined(separator: "，")
    }

    private struct CoursePlacement: Identifiable {
        let course: Course
        let track: Int

        var id: String { "\(course.id)|\(track)" }
    }

    private static let nowRed = AppTheme.danger
    private var dayHeaderFormatter: DateFormatter {
        formatter("M/d E")
    }

    private var accessibleDateFormatter: DateFormatter {
        formatter(model.appLanguage.resolvedResourceName == "en" ? "EEEE, MMMM d, yyyy" : "yyyy年M月d日 EEEE")
    }

    private var timeFormatter: DateFormatter {
        formatter("HH:mm")
    }

    private func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = model.appLanguage.locale
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = format
        return formatter
    }
}
