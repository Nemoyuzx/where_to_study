import SwiftUI

// The existing privacy holder contains only presentation state. Share its
// interface with other local destinations while retaining the privacy host.
typealias InAppPresentationState = PrivacyPolicyPresentation

struct InAppSheetPresentationHost<Content: View>: View {
    @ObservedObject var presentation: InAppPresentationState
    private let content: @MainActor () -> Content

    init(presentation: InAppPresentationState, @ViewBuilder content: @escaping @MainActor () -> Content) {
        self.presentation = presentation
        self.content = content
    }

    var body: some View {
        Color.clear.sheet(isPresented: $presentation.isPresented) { content() }
    }
}

#if os(iOS)
struct InAppFullScreenPresentationHost<Content: View>: View {
    @ObservedObject var presentation: InAppPresentationState
    private let content: @MainActor () -> Content

    init(presentation: InAppPresentationState, @ViewBuilder content: @escaping @MainActor () -> Content) {
        self.presentation = presentation
        self.content = content
    }

    var body: some View {
        Color.clear.fullScreenCover(isPresented: $presentation.isPresented) { content() }
    }
}
#endif
