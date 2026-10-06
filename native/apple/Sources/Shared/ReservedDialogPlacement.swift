import Foundation

struct DialogReservedArea {
    let frame: CGRect
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat
    let isActive: Bool

    var exclusion: CGRect {
        let frame = frame.standardized
        return CGRect(x: frame.minX - max(0, leading), y: frame.minY - max(0, top),
                      width: frame.width + max(0, leading) + max(0, trailing),
                      height: frame.height + max(0, top) + max(0, bottom))
    }
}

enum ReservedDialogPlacement {
    // The existing card has 20pt outer padding and a 30pt close control.
    // Never shrink it into a sliver that makes dismissing the dialog impossible.
    static let minimumPane = CGSize(width: 220, height: 180)
    static let maximumCandidates = 128

    static func pane(in bounds: CGRect, regions: [DialogReservedArea]) -> CGRect {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let exclusions = regions.filter { $0.isActive && $0.frame.origin.x.isFinite &&
            $0.frame.origin.y.isFinite && $0.frame.width.isFinite && $0.frame.height.isFinite &&
            $0.top.isFinite && $0.leading.isFinite && $0.bottom.isFinite && $0.trailing.isFinite }
            .map { $0.exclusion.intersection(bounds) }.filter { !$0.isNull && !$0.isEmpty }
        guard !exclusions.isEmpty else { return bounds }
        var candidates = [bounds]
        for exclusion in exclusions {
            var next: [CGRect] = []
            for candidate in candidates {
                guard candidate.intersects(exclusion) else { next.append(candidate); continue }
                // Full-length strips preserve usable rectangles on all sides of
                // a small camera region, as well as either side of a hinge.
                next += [
                    CGRect(x: candidate.minX, y: candidate.minY,
                           width: exclusion.minX - candidate.minX, height: candidate.height),
                    CGRect(x: exclusion.maxX, y: candidate.minY,
                           width: candidate.maxX - exclusion.maxX, height: candidate.height),
                    CGRect(x: candidate.minX, y: candidate.minY,
                           width: candidate.width, height: exclusion.minY - candidate.minY),
                    CGRect(x: candidate.minX, y: exclusion.maxY,
                           width: candidate.width, height: candidate.maxY - exclusion.maxY)
                ].filter { $0.width > 0 && $0.height > 0 }
            }
            candidates = Array(next.sorted { preferred($0, over: $1, bounds: bounds) }
                .prefix(maximumCandidates))
            if candidates.isEmpty { break }
        }
        if let pane = candidates.first(where: { $0.width >= minimumPane.width && $0.height >= minimumPane.height }) {
            return pane
        }
        // No rectangle can fit the close control and content. Keep the original
        // accessible card rather than clipping controls or retrying indefinitely.
        return bounds
    }

    private static func preferred(_ left: CGRect, over right: CGRect, bounds: CGRect) -> Bool {
        let leftArea = left.width * left.height
        let rightArea = right.width * right.height
        if leftArea != rightArea { return leftArea > rightArea }
        let leftDistance = abs(left.midX - bounds.midX) + abs(left.midY - bounds.midY)
        let rightDistance = abs(right.midX - bounds.midX) + abs(right.midY - bounds.midY)
        if leftDistance != rightDistance { return leftDistance < rightDistance }
        if left.minY != right.minY { return left.minY < right.minY }
        return left.minX > right.minX
    }
}
