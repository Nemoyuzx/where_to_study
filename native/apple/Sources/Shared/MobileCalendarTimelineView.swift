#if os(iOS)
import SwiftUI
import UIKit

enum MobileCalendarTimelineLayout {
    static let startMinute = 8 * 60
    static let endMinute = 22 * 60
    static let hourHeight: CGFloat = 72
    static let axisWidth: CGFloat = 56
    static let bottomContentInset: CGFloat = 104

    static func contentBottomInset(isLandscape: Bool) -> CGFloat {
        isLandscape ? 0 : bottomContentInset
    }

    static var timelineHeight: CGFloat {
        CGFloat(endMinute - startMinute) / 60 * hourHeight
    }

    static func yPosition(minute: Int) -> CGFloat {
        let clamped = min(max(minute, startMinute), endMinute)
        return CGFloat(clamped - startMinute) / 60 * hourHeight
    }

    static func contentWidth(
        availableWidth: CGFloat,
        dayCount: Int,
        showsWeekColumns: Bool
    ) -> CGFloat {
        let viewportWidth = max(availableWidth - axisWidth, 1)
        return viewportWidth
    }

    static func initialVisibleHour(currentHour: Int, includesToday: Bool) -> Int {
        guard includesToday else { return 8 }
        return min(max(currentHour - 1, 8), 20)
    }
}

enum MobileCalendarYearLayout {
    // The compact calendar intentionally extends beneath UIKit's floating tab bar.
    // Keep the last mini-month and its tappable dates above that overlay.
    static let bottomContentInset: CGFloat = 104

    static func contentBottomInset(isLandscape _: Bool) -> CGFloat {
        bottomContentInset
    }
}

enum MobileCalendarAllDayLayout {
    static let height: CGFloat = 40

    static func dayWidth(availableWidth: CGFloat, dayCount: Int) -> CGFloat {
        let timelineWidth = MobileCalendarTimelineLayout.contentWidth(
            availableWidth: availableWidth,
            dayCount: dayCount,
            showsWeekColumns: dayCount > 1
        )
        return timelineWidth / CGFloat(max(dayCount, 1))
    }

    static func labels(for days: [CalendarTimelineDay]) -> [String] {
        days.map { day in
            guard let first = day.allDayEvents.first else { return "" }
            let hiddenCount = day.allDayEvents.count - 1
            return hiddenCount > 0 ? "\(first.title) +\(hiddenCount)" : first.title
        }
    }
}

struct MobileCalendarTimelineView: View {
    let days: [CalendarTimelineDay]
    let selectedDate: Date
    let showsWeekColumns: Bool
    var isScrollEnabled = true
    var bottomContentInset = MobileCalendarTimelineLayout.bottomContentInset
    var onSelectDay: ((Date) -> Void)?
    var onSelectCourse: ((Date, Course) -> Void)?

    private let calendar = Calendar.shanghai

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            HStack(alignment: .top, spacing: 0) {
                                hourAxis
                                timelineGridViewport(availableWidth: proxy.size.width)
                            }

                            scrollAnchors
                        }
                        .frame(height: MobileCalendarTimelineLayout.timelineHeight)

                        Color.clear
                            .frame(height: bottomContentInset)
                            .accessibilityHidden(true)
                    }
                }
                .scrollDisabled(!isScrollEnabled)
                .background(MobileDirectionalScrollLock())
                .task(id: scrollRequestID) {
                    do {
                        try await Task.sleep(nanoseconds: 100_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    reader.scrollTo(scrollAnchorID(initialVisibleHour), anchor: .center)
                }
            }
        }
        .background(AppTheme.surface)
        .accessibilityElement(children: .contain)
    }

    private var scrollAnchors: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(8 ... 22, id: \.self) { hour in
                Color.clear
                    .frame(
                        width: 1,
                        height: hour == 22 ? 0 : MobileCalendarTimelineLayout.hourHeight
                    )
                    .id(scrollAnchorID(hour))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(
            width: 1,
            height: MobileCalendarTimelineLayout.timelineHeight,
            alignment: .topLeading
        )
    }

    private func scrollAnchorID(_ hour: Int) -> String {
        "mobile-calendar-hour-\(hour)"
    }

    private var scrollRequestID: String {
        let date = calendar.startOfDay(for: selectedDate).timeIntervalSinceReferenceDate
        return "\(date)-\(showsWeekColumns)-\(initialVisibleHour)"
    }

    private var hourAxis: some View {
        ZStack(alignment: .topLeading) {
            AppTheme.surface
            ForEach(8 ... 22, id: \.self) { hour in
                let y = MobileCalendarTimelineLayout.yPosition(minute: hour * 60)
                Text(String(format: "%02d:00", hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier(String(format: "calendar.mobile.hour.%02d", hour))
                    .frame(width: MobileCalendarTimelineLayout.axisWidth - 8, alignment: .trailing)
                    .position(
                        x: (MobileCalendarTimelineLayout.axisWidth - 8) / 2,
                        y: adjustedHourLabelY(hour: hour, rawY: y)
                    )
            }
        }
        .frame(
            width: MobileCalendarTimelineLayout.axisWidth,
            height: MobileCalendarTimelineLayout.timelineHeight
        )
        .overlay(alignment: .trailing) { Divider() }
    }

    @ViewBuilder
    private func timelineGridViewport(availableWidth: CGFloat) -> some View {
        let viewportWidth = max(availableWidth - MobileCalendarTimelineLayout.axisWidth, 1)
        let contentWidth = MobileCalendarTimelineLayout.contentWidth(
            availableWidth: availableWidth,
            dayCount: days.count,
            showsWeekColumns: showsWeekColumns
        )
        timelineGrid(width: contentWidth)
            .frame(width: viewportWidth, height: MobileCalendarTimelineLayout.timelineHeight)
    }

    private func timelineGrid(width: CGFloat) -> some View {
        let dayCount = max(days.count, 1)
        let dayWidth = width / CGFloat(dayCount)

        return ZStack(alignment: .topLeading) {
            AppTheme.surface
            selectedColumn(dayWidth: dayWidth)
            grid(width: width, dayWidth: dayWidth)
            if !showsWeekColumns {
                slotGuides(width: width)
            }
            courseBlocks(dayWidth: dayWidth)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ZStack(alignment: .topLeading) {
                    currentTimeIndicator(width: width, dayWidth: dayWidth, now: context.date)
                }
                .frame(width: width, height: MobileCalendarTimelineLayout.timelineHeight, alignment: .topLeading)
            }
            .allowsHitTesting(false)
        }
        .frame(width: width, height: MobileCalendarTimelineLayout.timelineHeight)
    }

    private func grid(width: CGFloat, dayWidth: CGFloat) -> some View {
        Canvas { context, _ in
            var hourLines = Path()
            for hour in 8 ... 22 {
                let y = MobileCalendarTimelineLayout.yPosition(minute: hour * 60)
                hourLines.move(to: CGPoint(x: 0, y: y))
                hourLines.addLine(to: CGPoint(x: width, y: y))
            }
            context.stroke(hourLines, with: .color(AppTheme.border), lineWidth: 1)

            var slotLines = Path()
            for minute in CalendarTimelineLogic.nonHourlyCourseBoundaryMinutes {
                let y = MobileCalendarTimelineLayout.yPosition(minute: minute)
                slotLines.move(to: CGPoint(x: 0, y: y))
                slotLines.addLine(to: CGPoint(x: width, y: y))
            }
            context.stroke(
                slotLines,
                with: .color(AppTheme.secondaryText.opacity(0.24)),
                style: StrokeStyle(lineWidth: 0.7, dash: [4, 4])
            )

            guard showsWeekColumns else { return }
            var columns = Path()
            for index in 0 ... max(days.count, 1) {
                let x = CGFloat(index) * dayWidth
                columns.move(to: CGPoint(x: x, y: 0))
                columns.addLine(to: CGPoint(x: x, y: MobileCalendarTimelineLayout.timelineHeight))
            }
            context.stroke(columns, with: .color(AppTheme.border.opacity(0.7)), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func selectedColumn(dayWidth: CGFloat) -> some View {
        if showsWeekColumns,
           let index = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) }) {
            Rectangle()
                .fill(AppTheme.selectedDate.opacity(0.10))
                .frame(width: dayWidth, height: MobileCalendarTimelineLayout.timelineHeight)
                .offset(x: CGFloat(index) * dayWidth)
                .allowsHitTesting(false)
        }
    }

    private func slotGuides(width: CGFloat) -> some View {
        ForEach(SlotMetadata.defaults) { slot in
            if let start = CalendarTimelineLogic.minute(of: slot.start),
               let end = CalendarTimelineLogic.minute(of: slot.end) {
                let y = (MobileCalendarTimelineLayout.yPosition(minute: start)
                    + MobileCalendarTimelineLayout.yPosition(minute: end)) / 2
                HStack(spacing: 5) {
                    Text("第\(slot.label)节")
                        .fontWeight(.semibold)
                    Text("\(slot.start)-\(slot.end)")
                        .monospacedDigit()
                }
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AppTheme.surface.opacity(0.92), in: Capsule())
                .overlay { Capsule().stroke(AppTheme.border.opacity(0.7), lineWidth: 0.5) }
                .fixedSize()
                .position(x: 66, y: y)
                .accessibilityLabel("第\(slot.label)节，\(slot.start)到\(slot.end)")
            }
        }
        .frame(width: width, height: MobileCalendarTimelineLayout.timelineHeight, alignment: .topLeading)
    }

    private func courseBlocks(dayWidth: CGFloat) -> some View {
        ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
            ForEach(day.coursePlacements) { placement in
                if let start = SlotMetadata.defaults[safe: placement.course.startSlot]
                    .flatMap({ CalendarTimelineLogic.minute(of: $0.start) }),
                   let end = SlotMetadata.defaults[safe: placement.course.endSlot]
                    .flatMap({ CalendarTimelineLogic.minute(of: $0.end) }) {
                    let trackWidth = dayWidth / CGFloat(day.courseTrackCount)
                    let inset: CGFloat = showsWeekColumns ? 1 : 3
                    let x = CGFloat(dayIndex) * dayWidth
                        + CGFloat(placement.track) * trackWidth
                        + inset
                    let top = MobileCalendarTimelineLayout.yPosition(minute: start) + 2
                    let bottom = max(top + 38, MobileCalendarTimelineLayout.yPosition(minute: end) - 2)
                    courseBlock(
                        date: day.date,
                        placement: placement,
                        width: max(trackWidth - inset * 2, showsWeekColumns ? 8 : 24),
                        x: x,
                        top: top,
                        bottom: bottom
                    )
                }
            }
        }
    }

    private func courseBlock(
        date: Date,
        placement: CalendarCoursePlacement,
        width: CGFloat,
        x: CGFloat,
        top: CGFloat,
        bottom: CGFloat
    ) -> some View {
        let height = bottom - top
        let metadata = CalendarTimelineLogic.courseMetadata(placement.course)
        return Button {
            onSelectCourse?(date, placement.course)
        } label: {
            VStack(alignment: .leading, spacing: showsWeekColumns ? 1 : 2) {
                Text(placement.course.name)
                    .font(.system(size: showsWeekColumns ? 10 : 12, weight: .semibold))
                    .lineLimit(showsWeekColumns ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if height >= 38 {
                    Text(placement.course.timeRange)
                        .font(.system(size: showsWeekColumns ? 8 : 10, design: .monospaced))
                        .lineLimit(showsWeekColumns ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsWeekColumns, height >= 48 {
                    Text(placement.course.room.isEmpty ? "地点未标注" : placement.course.room)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(placement.course.teacher.isEmpty ? "教师未标注" : "教师：\(placement.course.teacher)")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if height >= 44, !metadata.isEmpty {
                    Text(metadata)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .foregroundStyle(AppTheme.onPrimary)
            .padding(showsWeekColumns ? 5 : 6)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(AppTheme.primaryFill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .leading) {
                Rectangle().fill(AppTheme.accent).frame(width: 3)
            }
        }
        .buttonStyle(.plain)
        .position(x: x + width / 2, y: (top + bottom) / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(placement.course.timeRange)，\(placement.course.name)，\(metadata)"
        )
    }

    @ViewBuilder
    private func currentTimeIndicator(width: CGFloat, dayWidth: CGFloat, now: Date) -> some View {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if let index = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: now) }),
           (MobileCalendarTimelineLayout.startMinute ... MobileCalendarTimelineLayout.endMinute)
            .contains(minute) {
            let y = MobileCalendarTimelineLayout.yPosition(minute: minute)
            let left = showsWeekColumns ? CGFloat(index) * dayWidth : 0
            let lineWidth = showsWeekColumns ? dayWidth : width

            Path { path in
                path.move(to: CGPoint(x: left, y: y))
                path.addLine(to: CGPoint(x: min(left + lineWidth, width), y: y))
            }
            .stroke(AppTheme.danger, lineWidth: 2)

            Circle()
                .fill(AppTheme.danger)
                .frame(width: 8, height: 8)
                .position(x: left + 4, y: y)

            if !showsWeekColumns {
                Text(Self.timeFormatter.string(from: now))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.onPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.danger, in: Capsule())
                    .position(x: left + 30, y: y - 13)
            }
        }
    }

    private var initialVisibleHour: Int {
        MobileCalendarTimelineLayout.initialVisibleHour(
            currentHour: calendar.component(.hour, from: .now),
            includesToday: days.contains(where: { calendar.isDateInToday($0.date) })
        )
    }

    private func adjustedHourLabelY(hour: Int, rawY: CGFloat) -> CGFloat {
        if hour == 8 { return rawY + 8 }
        if hour == 22 { return rawY - 8 }
        return rawY
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

struct MobileDirectionalScrollLock: UIViewRepresentable {
    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        configureNearestScrollView(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        configureNearestScrollView(from: uiView)
    }

    private func configureNearestScrollView(from view: UIView) {
        DispatchQueue.main.async {
            var ancestor = view.superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView {
                    scrollView.isDirectionalLockEnabled = true
                    scrollView.alwaysBounceHorizontal = false
                    return
                }
                ancestor = current.superview
            }
        }
    }
}
#endif
