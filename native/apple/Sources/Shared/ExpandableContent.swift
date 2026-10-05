import SwiftUI

/// Keep an opened subtree's identity during height animation. The content is
/// clipped from the top, not inserted with an independent sliding transition.
struct ExpandableContent<Content: View>: View {
    let expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasMounted = false
    private let content: () -> Content

    init(expanded: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.expanded = expanded
        self.content = content
    }

    var body: some View {
        Group {
            if expanded || hasMounted {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: expanded ? nil : 0, alignment: .top)
                    .clipped()
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(expanded)
                    .accessibilityHidden(!expanded)
                    .onAppear { hasMounted = true }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: expanded)
    }
}
