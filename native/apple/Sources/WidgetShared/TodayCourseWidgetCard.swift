import SwiftUI
import WidgetKit

struct TodayCourseWidgetCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let date: Date
    let courses: [TodayCourseWidgetData.Course]
    var tomorrowCourses: [TodayCourseWidgetData.Course] = []
    let preferences: TodayCourseWidgetData.Preferences
    let weekNumber: Int?
    let family: WidgetFamily
    let usesWidgetContainer: Bool
    var language: TodayCourseWidgetData.Language = .simplifiedChinese
    var colorTheme: ColorThemeConfiguration = .default

    var body: some View {
        ViewThatFits(in: .vertical) {
            // Each candidate includes the same full set of today's rows. SwiftUI
            // measures real text and spacing, including the tomorrow heading.
            if maximumTomorrowCount >= 6 { content(tomorrowCount: 6).fixedSize(horizontal: false, vertical: true) }
            if maximumTomorrowCount >= 5 { content(tomorrowCount: 5).fixedSize(horizontal: false, vertical: true) }
            if maximumTomorrowCount >= 4 { content(tomorrowCount: 4).fixedSize(horizontal: false, vertical: true) }
            if maximumTomorrowCount >= 3 { content(tomorrowCount: 3).fixedSize(horizontal: false, vertical: true) }
            if maximumTomorrowCount >= 2 { content(tomorrowCount: 2).fixedSize(horizontal: false, vertical: true) }
            if maximumTomorrowCount >= 1 { content(tomorrowCount: 1).fixedSize(horizontal: false, vertical: true) }
            content(tomorrowCount: 0).fixedSize(horizontal: false, vertical: true)
            // Shorter system allocations can also reduce today's visible rows.
            // These fallback candidates never spend that space on tomorrow.
            if courseLimit > 5 { content(todayCount: 5, tomorrowCount: 0).fixedSize(horizontal: false, vertical: true) }
            if courseLimit > 4 { content(todayCount: 4, tomorrowCount: 0).fixedSize(horizontal: false, vertical: true) }
            if courseLimit > 3 { content(todayCount: 3, tomorrowCount: 0).fixedSize(horizontal: false, vertical: true) }
            if courseLimit > 2 { content(todayCount: 2, tomorrowCount: 0).fixedSize(horizontal: false, vertical: true) }
            content(todayCount: 1, tomorrowCount: 0)
        }
        .padding(family == .systemSmall ? 12 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetCardSurface(
            background: widgetBackground,
            usesWidgetContainer: usesWidgetContainer
        )
    }

    private func content(todayCount: Int? = nil, tomorrowCount: Int) -> some View {
        let visibleTodayCount = min(todayCount ?? courseLimit, courses.count)
        return VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 7) {
            header
            contextLine

            if courses.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(Array(courses.prefix(visibleTodayCount))) { course in
                        courseRow(course, isToday: true)
                    }
                    if courses.count > visibleTodayCount {
                        Text(language.text(
                            chinese: "另有 \(courses.count - visibleTodayCount) 门课程",
                            english: "\(courses.count - visibleTodayCount) more courses"
                        ))
                            .font(.caption2)
                            .foregroundStyle(widgetSecondaryText)
                            .lineLimit(1)
                    }
                }
            }
            if tomorrowCount > 0 {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    Text(language.text(chinese: "明日课程", english: "Tomorrow's Courses"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(widgetSecondaryText)
                        .lineLimit(1)
                        .accessibilityIdentifier("widget.tomorrow-heading")
                    ForEach(Array(tomorrowCourses.prefix(tomorrowCount))) { course in
                        courseRow(course, isToday: false)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(primary)
            Text(language.text(chinese: "今日课程", english: "Today's Courses"))
                .font(family == .systemSmall ? .subheadline.weight(.bold) : .headline)
                .foregroundStyle(widgetText)
            Spacer(minLength: 4)
            Text(courses.isEmpty ? "" : language.text(
                chinese: "\(courses.count) 门",
                english: "\(courses.count) courses"
            ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(widgetSecondaryText)
        }
    }

    private var contextLine: some View {
        HStack(spacing: 5) {
            Text(TodayCourseWidgetData.dayContext(
                on: date,
                weekNumber: weekNumber,
                language: language,
                compact: family == .systemSmall
            ))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
            if family != .systemSmall {
                Text("·")
                Text(TodayCourseWidgetData.statusSummary(
                    for: courses,
                    at: date,
                    language: language
                ))
                    .lineLimit(1)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(widgetSecondaryText)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(TodayCourseWidgetData.emptyMessage(language: language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(widgetText)
                if family != .systemSmall {
                    Text(language.text(
                        chinese: "今天可以自由安排",
                        english: "Your day is free"
                    ))
                        .font(.caption)
                        .foregroundStyle(widgetSecondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, family == .systemSmall ? 8 : 12)
    }

    private func courseRow(_ course: TodayCourseWidgetData.Course, isToday: Bool) -> some View {
        let phase = isToday ? TodayCourseWidgetData.coursePhase(course, at: date) : nil
        let highlighted = isToday && course.id == highlightedCourseID

        return HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(highlighted ? primary : theme.accent.color)
                .frame(width: 3, height: family == .systemSmall ? 28 : 31)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(course.name)
                        .font(courseNameFont)
                        .foregroundStyle(widgetText)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if highlighted, let phase, phase != .finished {
                        phaseBadge(phase)
                    }
                }
                Text(courseDetails(course))
                    .font(family == .systemSmall ? .caption2 : .caption)
                    .foregroundStyle(widgetSecondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func phaseBadge(_ phase: TodayCourseWidgetData.CoursePhase) -> some View {
        Text(phase.badgeText(language: language))
            .font(.caption2.weight(.bold))
            .foregroundStyle(badgeTextColor(phase))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(phase == .inProgress ? primary.opacity(0.14) : theme.accent.color.opacity(0.24))
            )
    }

    private var familyCourseLimit: Int {
        switch family {
        case .systemSmall: 2
        case .systemMedium: 3
        default: TodayCourseWidgetData.maximumCourseLimit
        }
    }

    private var courseLimit: Int {
        min(familyCourseLimit, preferences.normalized.courseLimit)
    }

    private var maximumTomorrowCount: Int {
        TodayCourseWidgetData.maximumTomorrowCourseCount(
            todayCount: courses.count,
            tomorrowCount: tomorrowCourses.count,
            preferences: preferences,
            familyCourseLimit: familyCourseLimit
        )
    }

    private var rowSpacing: CGFloat {
        switch family {
        case .systemSmall: 5
        case .systemMedium: 6
        default: 8
        }
    }

    private var courseNameFont: Font {
        family == .systemSmall ? .caption.weight(.semibold) : .subheadline.weight(.semibold)
    }

    private var highlightedCourseID: String? {
        TodayCourseWidgetData.highlightedCourseID(in: courses, at: date)
    }

    private var theme: WidgetThemePalette {
        .resolved(colorTheme, dark: colorScheme == .dark)
    }

    private var primary: Color { theme.primary.color }
    private var widgetBackground: Color { theme.background.color }
    private var surfaces: ThemeSurfacePalette {
        .resolved(primary: colorTheme.seeds.primary, dark: colorScheme == .dark)
    }
    private var widgetText: Color {
        colorTheme.preset == .default ? .primary : WidgetThemeColor(surfaces.text).color
    }
    private var widgetSecondaryText: Color {
        colorTheme.preset == .default ? .secondary : WidgetThemeColor(surfaces.secondaryText).color
    }
    private func badgeTextColor(_ phase: TodayCourseWidgetData.CoursePhase) -> Color {
        guard colorTheme.preset != .default else { return phase == .inProgress ? primary : .primary }
        let primaryRGB = surfaces.readable(colorTheme.seeds.primary.readableText(dark: colorScheme == .dark))
        let background = surfaces.surface.blended(toward: phase == .inProgress ? primaryRGB : colorTheme.seeds.accent,
                                                  amount: phase == .inProgress ? 0.14 : 0.24)
        let ink = (phase == .inProgress ? primaryRGB : surfaces.text)
            .adjusted(against: background, toward: colorScheme == .dark ? .white : .black)
        return WidgetThemeColor(ink).color
    }

    private func courseDetails(_ course: TodayCourseWidgetData.Course) -> String {
        var values = [course.timeRange]
        if family != .systemSmall, let sectionText = nonempty(course.sectionText) {
            values.append(sectionText)
        }
        if preferences.showsLocation, !course.room.isEmpty {
            values.append(language.text(
                chinese: "地点：\(course.room)",
                english: "Room: \(course.room)"
            ))
        }
        if preferences.showsTeacher, let teacher = nonempty(course.teacher) {
            values.append(language.text(
                chinese: "教师：\(teacher)",
                english: "Teacher: \(teacher)"
            ))
        }
        return values.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

extension WidgetThemeColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

private extension View {
    @ViewBuilder
    func widgetCardSurface(background surface: Color, usesWidgetContainer: Bool) -> some View {
        if usesWidgetContainer {
            #if os(macOS)
            if #available(macOS 14.0, *) {
                containerBackground(surface, for: .widget)
            } else {
                background(surface)
            }
            #else
            if #available(iOS 17.0, *) {
                containerBackground(surface, for: .widget)
            } else {
                background(surface)
            }
            #endif
        } else {
            background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
