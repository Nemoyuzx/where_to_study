import AppKit
import SwiftUI

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        DailyCourseNotificationCenterConfiguration.installForegroundDelegate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}

@main
struct WhereToStudyMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var model = AppLaunchConfiguration.makeModel()

    var body: some Scene {
        Window("Where To Study", id: "main") {
            RootView()
                .environmentObject(model)
                .environment(\.locale, model.appLanguage.locale)
                .frame(minWidth: 960, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 840)

        MenuBarExtra {
            MacMenuBarView()
                .environmentObject(model)
                .environment(\.locale, model.appLanguage.locale)
        } label: {
            MacMenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}
