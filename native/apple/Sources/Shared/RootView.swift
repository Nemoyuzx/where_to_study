import SwiftUI

enum AdaptiveHorizontalClass: Equatable {
    case compact
    case regular
}

enum PrimaryNavigationLayout: Equatable {
    case tabs
    case sidebar
}

enum CalendarPresentationLayout: Equatable {
    case compact
    case expanded
}

enum AdaptiveLayoutPolicy {
    static let minimumSidebarWidth: CGFloat = 700
    static let minimumExpandedCalendarWidth: CGFloat = 760
    static let minimumTwoColumnWidth: CGFloat = 760

    static func primaryNavigation(
        width: CGFloat,
        horizontalClass: AdaptiveHorizontalClass
    ) -> PrimaryNavigationLayout {
        horizontalClass == .regular && width >= minimumSidebarWidth ? .sidebar : .tabs
    }

    static func calendarPresentation(width: CGFloat) -> CalendarPresentationLayout {
        width >= minimumExpandedCalendarWidth ? .expanded : .compact
    }

    static func contentColumnCount(width: CGFloat) -> Int {
        width >= minimumTwoColumnWidth ? 2 : 1
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var teachingCalendarSession = TeachingCalendarSessionState()
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if model.isSampleMode {
                sampleModeBanner
            }

            Group {
            #if os(macOS)
            splitNavigation
            #else
            GeometryReader { proxy in
                let horizontalClass = AdaptiveHorizontalClass(
                    horizontalSizeClass: horizontalSizeClass
                )
                switch AdaptiveLayoutPolicy.primaryNavigation(
                    width: proxy.size.width,
                    horizontalClass: horizontalClass
                ) {
                case .sidebar:
                    splitNavigation
                case .tabs:
                    tabNavigation
                }
            }
            #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

    private var sampleModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
            Text("示例数据 · 不连接北邮教务服务")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AppTheme.text)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AppTheme.accent)
        .accessibilityIdentifier("banner.sample-mode")
    }

    private var splitNavigation: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 250)
        } detail: {
            sectionView(model.selectedSection)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BUPT")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
                Text("Where To Study")
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
            }
            .padding(.horizontal, sidebarTitlePadding)

            Divider()

            List(AppSection.allCases) { section in
                Button {
                    model.selectedSection = section
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.body.weight(model.selectedSection == section ? .semibold : .regular))
                        .foregroundStyle(AppTheme.text)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    model.selectedSection == section
                        ? AppTheme.primary.opacity(0.14)
                        : Color.clear
                )
                .accessibilityIdentifier(section.accessibilityIdentifier)
                .accessibilityAddTraits(model.selectedSection == section ? .isSelected : [])
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.surface.ignoresSafeArea())
        .accessibilityIdentifier("layout.regular-sidebar")
    }

    #if os(iOS)
    private var tabNavigation: some View {
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
        .toolbarBackground(AppTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .accessibilityIdentifier("layout.compact-tabs")
    }
    #endif

    private var sidebarTitlePadding: CGFloat {
        #if os(macOS)
        40
        #else
        24
        #endif
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .planner: PlannerView()
        case .calendar:
            #if os(iOS)
            AdaptiveTeachingCalendarView(session: teachingCalendarSession)
            #else
            TeachingCalendarView(session: teachingCalendarSession)
            #endif
        case .settings: SettingsView()
        }
    }
}

#if os(iOS)
private extension AdaptiveHorizontalClass {
    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        self = horizontalSizeClass == .regular ? .regular : .compact
    }
}

private struct AdaptiveTeachingCalendarView: View {
    @ObservedObject var session: TeachingCalendarSessionState

    var body: some View {
        GeometryReader { proxy in
            switch AdaptiveLayoutPolicy.calendarPresentation(width: proxy.size.width) {
            case .compact:
                MobileTeachingCalendarView(session: session)
            case .expanded:
                TeachingCalendarView(session: session)
            }
        }
    }
}
#endif
