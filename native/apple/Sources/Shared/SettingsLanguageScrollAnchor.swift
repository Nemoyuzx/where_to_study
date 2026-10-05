import SwiftUI

@MainActor
final class SettingsLanguageScrollState {
    static let targetID = "settings.language.anchor"
    static let coordinateSpace = "settings.language.viewport"
    var cardFrame: CGRect = .zero
    var viewportSize: CGSize = .zero
    private var pendingAnchor: UnitPoint?
    private var targetLanguage: AppLanguage?
    private var pendingWork: DispatchWorkItem?
    private var revision = 0
    func isSettled(for language: AppLanguage) -> Bool {
        pendingWork == nil && pendingAnchor == nil && targetLanguage == nil &&
            cardFrame.width > 0 && cardFrame.height > 0 && viewportSize.width > 0 && viewportSize.height > 0
    }
    var readinessGeometry: [Double] {
        [cardFrame.minX, cardFrame.minY, cardFrame.width, cardFrame.height,
         viewportSize.width, viewportSize.height].map(Double.init)
    }
    #if DEBUG
    private var debugMessages = 0

    func log(_ message: String) {
        guard (AppLaunchConfiguration.isUITesting || AppLaunchConfiguration.isReviewDemo),
              ProcessInfo.processInfo.arguments.contains("--ui-test-language-anchor"), debugMessages < 12 else { return }
        debugMessages += 1
        NSLog("%@", "SETTINGS_LANGUAGE_ANCHOR \(message)")
    }
    #endif

    func capture(beforeSwitchTo language: AppLanguage) {
        cancel()
        #if DEBUG
        debugMessages = 0
        log("capture language=\(language.rawValue) frame=\(cardFrame) viewport=\(viewportSize) revision=\(revision)")
        #endif
        guard viewportSize.height > 0, cardFrame.height > 0 else {
            #if DEBUG
            log("capture skipped: zero geometry")
            #endif
            return
        }
        let available = max(1, viewportSize.height - cardFrame.height)
        pendingAnchor = UnitPoint(x: 0.5, y: min(1, max(0, cardFrame.minY / available)))
        targetLanguage = language
        #if DEBUG
        log("captured target=\(String(describing: pendingAnchor))")
        #endif
    }

    func restore(using proxy: ScrollViewProxy, language: AppLanguage) {
        #if DEBUG
        log("restore requested language=\(language.rawValue) target=\(String(describing: targetLanguage)) frame=\(cardFrame) viewport=\(viewportSize)")
        #endif
        guard targetLanguage == language, let anchor = pendingAnchor else {
            #if DEBUG
            log("restore skipped: missing target")
            #endif
            return
        }
        let requestedRevision = revision
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.revision == requestedRevision else { return }
            self.pendingWork = nil
            self.pendingAnchor = nil
            self.targetLanguage = nil
            #if DEBUG
            self.log("restore executing anchor=\(anchor) frameBefore=\(self.cardFrame)")
            #endif
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(Self.targetID, anchor: anchor) }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-language-anchor") {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.log("restore next queue frameAfter=\(self.cardFrame)")
                }
            }
            #endif
        }
        pendingWork = work
        DispatchQueue.main.async(execute: work)
    }

    func cancel() {
        revision &+= 1
        #if DEBUG
        log("cancel revision=\(revision)")
        #endif
        pendingWork?.cancel()
        pendingWork = nil
        pendingAnchor = nil
        targetLanguage = nil
    }
}

private struct SettingsLanguageCardFrame: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0 && next.height > 0 { value = next }
    }
}

struct SettingsLanguageCardAnchor: ViewModifier {
    func body(content: Content) -> some View {
        content.id(SettingsLanguageScrollState.targetID).background {
            GeometryReader { geometry in
                Color.clear.preference(key: SettingsLanguageCardFrame.self,
                    value: geometry.frame(in: .named(SettingsLanguageScrollState.coordinateSpace)))
            }
        }
    }
}

struct SettingsLanguageScrollAnchor: ViewModifier {
    let state: SettingsLanguageScrollState
    let language: AppLanguage

    func body(content: Content) -> some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                content.coordinateSpace(name: SettingsLanguageScrollState.coordinateSpace)
                    .onPreferenceChange(SettingsLanguageCardFrame.self) {
                        state.cardFrame = $0
                        #if DEBUG
                        state.log("preference language=\(language.rawValue) frame=\($0)")
                        #endif
                    }
                    .onAppear { state.viewportSize = viewport.size }
                    .onChange(of: viewport.size) { state.viewportSize = $0 }
                    .onChange(of: language) { state.restore(using: proxy, language: $0) }
                    .onDisappear { state.cancel() }
            }
        }
    }
}
