import SwiftUI

/// Local presentation state only; opening the full table never refreshes data.
struct ShuttleFullTimetableDisclosure<Content: View, Header: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    let language: AppLanguage
    private let content: Content
    private let header: Header

    init(language: AppLanguage, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Header) {
        self.language = language
        self.content = content()
        self.header = label()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $isExpanded) {
                content.accessibilityIdentifier("queries.shuttle.full-timetable.content")
            } label: {
                header
            }
            .animation(reduceMotion || AppLaunchConfiguration.forcesReducedMotionForUITests
                ? nil : .easeOut(duration: 0.16), value: isExpanded)
            .accessibilityValue(AppLocalization.string(isExpanded ? "已展开" : "已折叠", language: language))
            .accessibilityIdentifier("queries.shuttle.full-timetable.toggle")
        }
        .accessibilityElement(children: .contain)
    }
}
