import SwiftUI
import WidgetKit

struct TodayCourseWidgetCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let date: Date
    let courses: [TodayCourseWidgetData.Course]
    let preferences: TodayCourseWidgetData.Preferences
    let weekNumber: Int?
    let family: WidgetFamily
    let usesWidgetContainer: Bool
    var language: TodayCourseWidgetData.Language = .simplifiedChinese

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 7) {
            header
            contextLine

            if courses.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(Array(courses.prefix(courseLimit))) { course in
                        courseRow(course)
                    }
                    if courses.count > courseLimit {
                        Text(language.text(
                            chinese: "另有 \(courses.count - courseLimit) 门课程",
                            english: "\(courses.count - courseLimit) more courses"
                        ))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(family == .systemSmall ? 12 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetCardSurface(
            background: widgetBackground,
            usesWidgetContainer: usesWidgetContainer
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(primary)
            Text(language.text(chinese: "今日课程", english: "Today's Courses"))
                .font(family == .systemSmall ? .subheadline.weight(.bold) : .headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(courses.isEmpty ? "" : language.text(
                chinese: "\(courses.count) 门",
                english: "\(courses.count) courses"
            ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var contextLine: some View {
        HStack(spacing: 5) {
            Text(TodayCourseWidgetData.dayContext(
                on: date,
                weekNumber: weekNumber,
                language: language
            ))
                .lineLimit(1)
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
        .foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(TodayCourseWidgetData.emptyMessage(language: language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if family != .systemSmall {
                    Text(language.text(
                        chinese: "今天可以自由安排",
                        english: "Your day is free"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, family == .systemSmall ? 8 : 12)
    }

    private func courseRow(_ course: TodayCourseWidgetData.Course) -> some View {
        let phase = TodayCourseWidgetData.coursePhase(course, at: date)
        let highlighted = course.id == highlightedCourseID

        return HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(highlighted ? primary : theme.accent.color)
                .frame(width: 3, height: family == .systemSmall ? 28 : 31)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(course.name)
                        .font(courseNameFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if highlighted, let phase, phase != .finished {
                        phaseBadge(phase)
                    }
                }
                Text(courseDetails(course))
                    .font(family == .systemSmall ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func phaseBadge(_ phase: TodayCourseWidgetData.CoursePhase) -> some View {
        Text(phase.badgeText(language: language))
            .font(.caption2.weight(.bold))
            .foregroundStyle(phase == .inProgress ? primary : Color.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(phase == .inProgress ? primary.opacity(0.14) : theme.accent.color.opacity(0.24))
            )
    }

    private var courseLimit: Int {
        let familyLimit = switch family {
        case .systemSmall: 2
        case .systemMedium: 3
        default: TodayCourseWidgetData.maximumCourseLimit
        }
        return min(familyLimit, preferences.normalized.courseLimit)
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
        colorScheme == .dark ? .dark : .light
    }

    private var primary: Color { theme.primary.color }
    private var widgetBackground: Color { theme.background.color }

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
