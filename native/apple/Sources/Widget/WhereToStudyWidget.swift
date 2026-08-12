import SwiftUI
import WidgetKit

private struct TodayCourseEntry: TimelineEntry {
    let date: Date
    let courses: [TodayCourseWidgetData.Course]
    let hasSchedule: Bool
}

private struct TodayCourseProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodayCourseEntry {
        TodayCourseEntry(
            date: .now,
            courses: [
                .init(
                    id: "placeholder",
                    name: "数据挖掘",
                    room: "教二楼-335",
                    timeRange: "09:50-12:15",
                    weekday: 1,
                    weekNumbers: [1],
                    examWeekNumbers: [],
                    startSlot: 2
                )
            ],
            hasSchedule: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayCourseEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TodayCourseEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(
            entries: [entry(at: now)],
            policy: .after(TodayCourseWidgetData.nextMidnight(after: now))
        ))
    }

    private func entry(at date: Date) -> TodayCourseEntry {
        let archive = TodayCourseWidgetData.load()
        return TodayCourseEntry(
            date: date,
            courses: TodayCourseWidgetData.courses(on: date, archive: archive),
            hasSchedule: archive != nil
        )
    }
}

private struct TodayCourseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: TodayCourseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(primary)
                Text("今日课程")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text(entry.courses.isEmpty ? "" : "\(entry.courses.count) 门")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !entry.hasSchedule {
                message("打开应用获取个人课表", icon: "arrow.clockwise")
            } else if entry.courses.isEmpty {
                message("今天没有课程", icon: "checkmark.circle")
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
                    ForEach(Array(entry.courses.prefix(courseLimit))) { course in
                        courseRow(course)
                    }
                    if entry.courses.count > courseLimit {
                        Text("另有 \(entry.courses.count - courseLimit) 门课程")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .widgetSurface(background: widgetBackground)
    }

    private var courseLimit: Int {
        switch family {
        case .systemSmall: 2
        case .systemMedium: 3
        default: 6
        }
    }

    private func courseRow(_ course: TodayCourseWidgetData.Course) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.accent.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text([course.timeRange, course.room].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func message(_ text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(primary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var theme: WidgetThemePalette {
        colorScheme == .dark ? .dark : .light
    }

    private var primary: Color { theme.primary.color }
    private var widgetBackground: Color { theme.background.color }
}

private extension WidgetThemeColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

private extension View {
    @ViewBuilder
    func widgetSurface(background surface: Color) -> some View {
        if #available(macOS 14.0, *) {
            containerBackground(surface, for: .widget)
        } else {
            background(surface)
        }
    }
}

@main
struct WhereToStudyWidget: Widget {
    let kind = "TodayCourseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayCourseProvider()) { entry in
            TodayCourseWidgetView(entry: entry)
        }
        .configurationDisplayName("今日课程")
        .description("查看今天的课程时间与教室。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
