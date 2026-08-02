import SwiftUI

@main
struct WhereToStudyMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 840)
    }
}
