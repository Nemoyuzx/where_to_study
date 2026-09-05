import SwiftUI
import UIKit

final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        DailyCourseNotificationCenterConfiguration.installForegroundDelegate()
        return true
    }
}

@main
struct WhereToStudyiOSApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var appDelegate
    @StateObject private var privacyConsent = PrivacyConsentState(
        bypassesConsent: AppLaunchConfiguration.bypassesPrivacyConsent,
        resetsConsent: AppLaunchConfiguration.forcesPrivacyConsent
    )

    var body: some Scene {
        WindowGroup {
            Group {
                if privacyConsent.hasAccepted {
                    ConsentedApplicationRoot()
                } else {
                    PrivacyConsentGate(state: privacyConsent)
                        .environment(
                            \.locale,
                            AppLaunchConfiguration.privacyConsentLanguage.locale
                        )
                }
            }
        }
    }
}

@MainActor
private struct ConsentedApplicationRoot: View {
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppLaunchConfiguration.makeModel())
    }

    var body: some View {
        RootView()
            .environmentObject(model)
            .environmentObject(model.navigation)
            .environment(\.locale, model.appLanguage.locale)
    }
}
