import SwiftUI
import WidgetKit

private struct TodayCourseEntry: TimelineEntry {
    let date: Date
    let courses: [TodayCourseWidgetData.Course]
    let preferences: TodayCourseWidgetData.Preferences
    let weekNumber: Int?
    let language: TodayCourseWidgetData.Language
}

private struct TodayCourseProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodayCourseEntry {
        TodayCourseEntry(
            date: .now,
            courses: TodayCourseWidgetData.previewCourses(),
            preferences: .default,
            weekNumber: 8,
            language: TodayCourseWidgetData.loadLanguage()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayCourseEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TodayCourseEntry>) -> Void) {
        let now = Date.now
        let archive = TodayCourseWidgetData.load()
        let dates = TodayCourseWidgetData.timelineDates(after: now, archive: archive)
        let reloadDate = TodayCourseWidgetData.nextMidnight(after: now).addingTimeInterval(60)
        completion(Timeline(
            entries: dates.map { entry(at: $0, archive: archive) },
            policy: .after(reloadDate)
        ))
    }

    private func entry(
        at date: Date,
        archive: TodayCourseWidgetData.Archive? = TodayCourseWidgetData.load()
    ) -> TodayCourseEntry {
        TodayCourseEntry(
            date: date,
            courses: TodayCourseWidgetData.courses(on: date, archive: archive),
            preferences: TodayCourseWidgetData.loadPreferences(),
            weekNumber: TodayCourseWidgetData.weekNumber(on: date, archive: archive),
            language: TodayCourseWidgetData.loadLanguage()
        )
    }
}

private struct TodayCourseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayCourseEntry

    var body: some View {
        TodayCourseWidgetCard(
            date: entry.date,
            courses: entry.courses,
            preferences: entry.preferences,
            weekNumber: entry.weekNumber,
            family: family,
            usesWidgetContainer: true,
            language: entry.language
        )
    }
}

@main
struct WhereToStudyWidget: Widget {
    let kind = "TodayCourseWidget"

    var body: some WidgetConfiguration {
        let language = TodayCourseWidgetData.loadLanguage()
        return StaticConfiguration(kind: kind, provider: TodayCourseProvider()) { entry in
            TodayCourseWidgetView(entry: entry)
        }
        .configurationDisplayName(language.text(
            chinese: "今日课程",
            english: "Today's Courses"
        ))
        .description(language.text(
            chinese: "查看今天的课程、节次、教室、教师与上课状态。",
            english: "See today's classes, periods, rooms, teachers, and live status."
        ))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
