import SwiftUI

// A small timestamp badge plus an exact-time hairline. This does not replace
// the all-day event, alter course durations or occupy a fabricated time slot.
struct CalendarDeadlineMomentMarker: View {
    @Environment(\.appTheme) private var theme
    let moment: CalendarDeadlineMoment
    let width: CGFloat
    let height: CGFloat
    let anchorY: CGFloat
    let badgeY: CGFloat
    var anchorYs: [CGFloat] = []
    var pendingStatusLabel = ""
    let onSelect: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for y in anchorYs.isEmpty ? [anchorY] : anchorYs {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                    if abs(badgeY - y) > 1 {
                        path.move(to: CGPoint(x: width - 2, y: y))
                        path.addLine(to: CGPoint(x: width - 2, y: badgeY))
                    }
                }
            }
            .stroke(theme.primaryFill, lineWidth: 1)
            .allowsHitTesting(false)
            ForEach(Array((anchorYs.isEmpty ? [anchorY] : anchorYs).enumerated()), id: \.offset) { _, y in
                Circle().fill(theme.primaryFill).frame(width: 4, height: 4)
                    .position(x: -1, y: y).allowsHitTesting(false)
            }
            Button(action: onSelect) { badgeLabel }
            .buttonStyle(.plain)
            .position(x: width / 2, y: badgeY)
            .accessibilityLabel(accessibilityDescription)
            if moment.hasPendingSubmission {
                Circle().fill(AppTheme.danger).frame(width: 6, height: 6)
                    .overlay { Circle().stroke(theme.surface, lineWidth: 1) }
                    .position(x: 1, y: badgeY - 6)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private var horizontalPadding: CGFloat { width < 30 ? 0 : width < 70 ? 2 : 5 }

    private var badgeLabel: some View {
        HStack(spacing: 2) {
            Text(moment.time).monospacedDigit().fixedSize(horizontal: true, vertical: false)
            if let first = moment.events.first {
                Text("·").fixedSize(horizontal: true, vertical: false)
                Text(first.title).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading).clipped()
            }
            if moment.events.count > 1 { Text("+\(moment.events.count - 1)") }
        }
        .font(.system(size: width < 70 ? 8 : 10, weight: .semibold))
        .lineLimit(1)
        .padding(.horizontal, horizontalPadding)
        .frame(width: width, height: 18, alignment: .leading)
        .foregroundStyle(theme.onPrimary)
        .background(theme.primaryFill, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }

    private var accessibilityDescription: String {
        let times = moment.anchorMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }.joined(separator: " / ")
        let titles = moment.events.map(\.title).joined(separator: "，")
        let status = moment.hasPendingSubmission && !pendingStatusLabel.isEmpty ? "，" + pendingStatusLabel : ""
        return times + "，" + titles + status
    }
}
