import SwiftUI

/// Local presentation state only; opening the full table never refreshes data.
struct ShuttleFullTimetableDisclosure<Content: View, Header: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    let language: AppLanguage
    private let content: () -> Content
    private let header: Header

    init(language: AppLanguage, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Header) {
        self.language = language
        self.content = content
        self.header = label()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    header.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(AppLocalization.string(isExpanded ? "已展开" : "已折叠", language: language))
            .accessibilityIdentifier("queries.shuttle.full-timetable.toggle")
            ExpandableContent(expanded: isExpanded) {
                content().padding(.top, 12)
                    .accessibilityIdentifier("queries.shuttle.full-timetable.content")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
