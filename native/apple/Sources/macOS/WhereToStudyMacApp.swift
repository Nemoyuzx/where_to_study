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
                .environmentObject(model.navigation)
                .environment(\.locale, model.appLanguage.locale)
                .frame(minWidth: 960, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            MacAppKeyboardCommands(navigation: model.navigation)
        }

        MenuBarExtra {
            MacMenuBarView()
                .environmentObject(model)
                .environmentObject(model.navigation)
                .environment(\.locale, model.appLanguage.locale)
        } label: {
            MacMenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MacAppKeyboardCommands: Commands {
    @ObservedObject var navigation: PrimaryNavigationState

    var body: some Commands {
        CommandMenu("导航") {
            Button("空教室") { navigation.selectedSection = .planner }
                .keyboardShortcut(KeyEquivalent(AppSection.planner.keyboardShortcutDigit), modifiers: [.option])
            Button("教学日历") { navigation.selectedSection = .calendar }
                .keyboardShortcut(KeyEquivalent(AppSection.calendar.keyboardShortcutDigit), modifiers: [.option])
            Button("查询") { navigation.selectedSection = .queries }
                .keyboardShortcut(KeyEquivalent(AppSection.queries.keyboardShortcutDigit), modifiers: [.option])
            Button("设置") { navigation.selectedSection = .settings }
                .keyboardShortcut(KeyEquivalent(AppSection.settings.keyboardShortcutDigit), modifiers: [.option])

            Divider()

            Button("日视图") { AppKeyboardCommandNotification.post(.dayView) }
                .keyboardShortcut("d", modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button("周视图") { AppKeyboardCommandNotification.post(.weekView) }
                .keyboardShortcut("w", modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button("月视图") { AppKeyboardCommandNotification.post(.monthView) }
                .keyboardShortcut("m", modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button("年视图") { AppKeyboardCommandNotification.post(.yearView) }
                .keyboardShortcut("y", modifiers: [])
                .disabled(navigation.selectedSection != .calendar)

            Divider()

            Button("上一时间段") { AppKeyboardCommandNotification.post(.previousPeriod) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button("下一时间段") { AppKeyboardCommandNotification.post(.nextPeriod) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button("今天") { AppKeyboardCommandNotification.post(.today) }
                .keyboardShortcut(.home, modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button("关闭弹层") { AppKeyboardCommandNotification.post(.dismissOverlay) }
                .keyboardShortcut(.escape, modifiers: [])
        }
    }
}
