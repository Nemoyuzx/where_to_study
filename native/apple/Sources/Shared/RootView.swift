import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
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
                .padding(.horizontal, 20)
                Divider()
                List(AppSection.allCases, selection: $model.selectedSection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .accessibilityIdentifier(section.accessibilityIdentifier)
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
                    .tabItem {
                        Label(section.title, systemImage: section.systemImage)
                            .accessibilityIdentifier(section.accessibilityIdentifier)
                    }
                    .tag(section)
            }
        }
        .tint(AppTheme.primary)
        #endif
        }
        .onAppear {
            model.refreshClassroomsIfNeeded()
            #if os(macOS)
            model.startDailyClassroomRefresh()
            #endif
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.refreshClassroomsIfNeeded()
                model.refreshDailyCourseNotificationAuthorization()
            }
        }
        .preferredColorScheme(.light)
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
