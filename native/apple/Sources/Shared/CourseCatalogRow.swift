import SwiftUI

struct CourseCatalogRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    let title: String
    let metadata: String
    let metadataSymbol: String
    let counts: CourseSubmissionCounts
    let identifier: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: "book")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.primaryOnSoftSurface)
                        .frame(width: 40, height: 40)
                        .background(theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.headline).foregroundStyle(theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !metadata.isEmpty || counts.hasEvidence {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 6) { chips }.fixedSize(horizontal: true, vertical: false)
                                VStack(alignment: .leading, spacing: 6) { chips }
                            }
                        }
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(theme.secondaryText).accessibilityHidden(true)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
            .accessibilityHint(model.localized("打开本课详情与已同步活动"))
            Divider().padding(.leading, 52)
        }
    }

    @ViewBuilder private var chips: some View {
        if !metadata.isEmpty { chip(metadata, symbol: metadataSymbol) }
        if counts.pending > 0 { chip(model.localizedFormat("待交 %d", counts.pending), symbol: "calendar.badge.clock") }
        if counts.submitted > 0 { chip(model.localizedFormat("已交 %d", counts.submitted), symbol: "checkmark.circle") }
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.caption)
            .foregroundStyle(theme.primaryOnSoftSurface)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }
}
