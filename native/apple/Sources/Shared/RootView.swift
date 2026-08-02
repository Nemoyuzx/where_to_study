import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BUPT")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("Where To Study")
                        .font(.headline)
                }
                Divider()
                List(AppSection.allCases, selection: $model.selectedSection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                .listStyle(.sidebar)
            }
            .padding(.top, 16)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            sectionView(model.selectedSection)
        }
        #else
        TabView(selection: $model.selectedSection) {
            ForEach(AppSection.allCases) { section in
                sectionView(section)
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    .tag(section)
            }
        }
        .tint(AppTheme.primary)
        #endif
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .planner: PlannerView()
        case .calendar: TeachingCalendarView()
        case .settings: SettingsView()
        }
    }
}
