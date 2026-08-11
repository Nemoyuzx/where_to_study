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
    @StateObject private var model = AppLaunchConfiguration.makeModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}
