import SwiftUI

struct CourseCatalogRow<ExpandedContent: View>: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let metadata: String
    let metadataSymbol: String
    let counts: CourseSubmissionCounts
    let identifier: String
    let isExpanded: Bool
    let toggle: () -> Void
    let details: () -> Void
    let expandedContent: ExpandedContent

    init(title: String, metadata: String, metadataSymbol: String, counts: CourseSubmissionCounts,
         identifier: String, isExpanded: Bool, toggle: @escaping () -> Void,
         details: @escaping () -> Void, @ViewBuilder content: () -> ExpandedContent) {
        self.title = title; self.metadata = metadata; self.metadataSymbol = metadataSymbol
        self.counts = counts; self.identifier = identifier; self.isExpanded = isExpanded
        self.toggle = toggle; self.details = details; self.expandedContent = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { toggle() }
                } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.primaryOnSoftSurface)
                        .frame(width: 40, height: 40)
                        .background(theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.headline).foregroundStyle(theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !summary.isEmpty {
                            Text(summary).font(.caption).foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(theme.secondaryText).accessibilityHidden(true)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier)
                .accessibilityValue(model.localized(isExpanded ? "收起" : "展开"))
                Button(action: details) {
                    Image(systemName: "info.circle").font(.title3)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryOnSoftSurface)
                .accessibilityLabel(model.localized("课程详情") + " · " + title)
                .accessibilityHint(model.localized("打开本课详情与已同步活动"))
                .accessibilityIdentifier(identifier + ".info")
            }
            if isExpanded {
                expandedContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityIdentifier(identifier + ".activities")
            }
        }
        .padding(12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.border, lineWidth: 1) }
    }

    private var summary: String {
        [metadata.isEmpty ? nil : metadata,
         counts.pending > 0 ? model.localizedFormat("待交 %d", counts.pending) : nil,
         counts.submitted > 0 ? model.localizedFormat("已交 %d", counts.submitted) : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
