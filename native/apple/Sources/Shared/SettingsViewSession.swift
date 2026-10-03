import SwiftUI

// Root retains these references across tab/sidebar replacement. It does not
// subscribe; the editing views and presentation hosts observe their own state.
@MainActor
final class SettingsViewSession {
    let privacyPresentation = PrivacyPolicyPresentation()
    let supportPresentation = InAppPresentationState()
    let favoritePresentation = InAppPresentationState()
    let reminderDraft = SettingsPreClassReminderDraft()
    let colorThemeDraft = SettingsColorThemeDraft()
    let languageScroll = SettingsLanguageScrollState()

    func dismissPresentations() {
        if privacyPresentation.isPresented { privacyPresentation.isPresented = false }
        if supportPresentation.isPresented { supportPresentation.isPresented = false }
        if favoritePresentation.isPresented { favoritePresentation.isPresented = false }
    }
}

struct SettingsPresentationHost: View {
    let session: SettingsViewSession

    var body: some View {
        Color.clear
            .background { PrivacyPolicyPresentationHost(presentation: session.privacyPresentation) }
            .background {
                InAppSheetPresentationHost(presentation: session.supportPresentation) {
                    AppSupportView().buttonStyle(.automatic)
                }
            }
            #if os(iOS)
            .background {
                InAppFullScreenPresentationHost(presentation: session.favoritePresentation) {
                    FavoriteDeadlineManagementPresentation().buttonStyle(.automatic)
                }
            }
            #endif
    }
}
