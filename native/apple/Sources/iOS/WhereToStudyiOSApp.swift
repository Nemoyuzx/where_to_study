import SwiftUI

@main
struct WhereToStudyiOSApp: App {
    @StateObject private var model = AppLaunchConfiguration.makeModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}
