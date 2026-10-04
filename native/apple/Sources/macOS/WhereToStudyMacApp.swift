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
                .environment(\.layoutDirection, model.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
                .frame(minWidth: 960, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            MacAppKeyboardCommands(model: model)
        }

        MenuBarExtra {
            MacMenuBarView()
                .environmentObject(model)
                .environmentObject(model.navigation)
                .environment(\.locale, model.appLanguage.locale)
                .environment(\.layoutDirection, model.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
        } label: {
            MacMenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MacAppKeyboardCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: PrimaryNavigationState

    init(model: AppModel) {
        self.model = model
        navigation = model.navigation
    }

    var body: some Commands {
        CommandMenu(model.localized("导航")) {
            Button(model.localized("空教室")) { navigation.selectedSection = .planner }
                .keyboardShortcut(KeyEquivalent(AppSection.planner.keyboardShortcutDigit), modifiers: [.option])
            Button(model.localized("教学日历")) { navigation.selectedSection = .calendar }
                .keyboardShortcut(KeyEquivalent(AppSection.calendar.keyboardShortcutDigit), modifiers: [.option])
            Button(model.localized("课程")) { navigation.selectedSection = .courses }
                .keyboardShortcut(KeyEquivalent(AppSection.courses.keyboardShortcutDigit), modifiers: [.option])
            Button(model.localized("查询")) { navigation.selectedSection = .queries }
                .keyboardShortcut(KeyEquivalent(AppSection.queries.keyboardShortcutDigit), modifiers: [.option])
            Button(model.localized("设置")) { navigation.selectedSection = .settings }
                .keyboardShortcut(KeyEquivalent(AppSection.settings.keyboardShortcutDigit), modifiers: [.option])

            Divider()

            Button(model.localized("日视图")) { AppKeyboardCommandNotification.post(.dayView) }
                .keyboardShortcut("d", modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button(model.localized("周视图")) { AppKeyboardCommandNotification.post(.weekView) }
                .keyboardShortcut("w", modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button(model.localized("月视图")) { AppKeyboardCommandNotification.post(.monthView) }
                .keyboardShortcut("m", modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button(model.localized("年视图")) { AppKeyboardCommandNotification.post(.yearView) }
                .keyboardShortcut("y", modifiers: [])
                .disabled(navigation.selectedSection != .calendar)

            Divider()

            Button(model.localized("上一时间段")) { AppKeyboardCommandNotification.post(.previousPeriod) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button(model.localized("下一时间段")) { AppKeyboardCommandNotification.post(.nextPeriod) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button(model.localized("今天")) { AppKeyboardCommandNotification.post(.today) }
                .keyboardShortcut(.home, modifiers: [])
                .disabled(navigation.selectedSection != .calendar)
            Button(model.localized("关闭弹层")) { AppKeyboardCommandNotification.post(.dismissOverlay) }
                .keyboardShortcut(.escape, modifiers: [])
        }
    }
}
