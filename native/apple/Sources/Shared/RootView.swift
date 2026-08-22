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

    static func calendarPresentation(
        width: CGFloat,
        horizontalClass: AdaptiveHorizontalClass
    ) -> CalendarPresentationLayout {
        guard horizontalClass == .regular else { return .compact }
        return width >= minimumExpandedCalendarWidth ? .expanded : .compact
    }

    static func contentColumnCount(width: CGFloat) -> Int {
        width >= minimumTwoColumnWidth ? 2 : 1
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var teachingCalendarSession = TeachingCalendarSessionState()
    @StateObject private var dailyInfo = DailyInfoStore()
    @StateObject private var calendarDeadlines = CalendarDeadlineStore()
    #if os(macOS)
    @State private var macSidebarVisibility: NavigationSplitViewVisibility = .all
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isRegularSidebarExpanded = true
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
                    regularNavigation
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
        .onChange(of: model.account) { _ in
            calendarDeadlines.clearAssignments()
        }
        .environmentObject(dailyInfo)
        .environmentObject(calendarDeadlines)
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

    #if os(macOS)
    private var splitNavigation: some View {
        NavigationSplitView(columnVisibility: $macSidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 250)
        } detail: {
            sectionView(model.selectedSection)
        }
        .navigationSplitViewStyle(.balanced)
    }
    #endif

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
    private var regularNavigation: some View {
        HStack(spacing: 0) {
            regularSidebar
                .frame(width: isRegularSidebarExpanded ? 224 : 64)
                .animation(.easeInOut(duration: 0.22), value: isRegularSidebarExpanded)

            Divider()

            sectionView(model.selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.background)
    }

    private var regularSidebar: some View {
        VStack(alignment: isRegularSidebarExpanded ? .leading : .center, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isRegularSidebarExpanded.toggle()
                }
            } label: {
                Image(systemName: isRegularSidebarExpanded ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.primary)
            .accessibilityLabel(isRegularSidebarExpanded ? "收起侧栏" : "展开侧栏")
            .accessibilityIdentifier("navigation.sidebar-toggle")

            if isRegularSidebarExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BUPT")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("Where To Study")
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .transition(.opacity)
            }

            Divider()

            ForEach(AppSection.allCases) { section in
                Button {
                    model.selectedSection = section
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 24, height: 24, alignment: .center)
                        if isRegularSidebarExpanded {
                            Text(section.title)
                                .font(.body.weight(model.selectedSection == section ? .semibold : .regular))
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .foregroundStyle(model.selectedSection == section ? AppTheme.primary : AppTheme.text)
                    .frame(
                        maxWidth: isRegularSidebarExpanded ? .infinity : nil,
                        minHeight: 42,
                        alignment: isRegularSidebarExpanded ? .leading : .center
                    )
                    .frame(
                        width: isRegularSidebarExpanded ? nil : 42,
                        height: 42,
                        alignment: .center
                    )
                    .padding(.horizontal, isRegularSidebarExpanded ? 12 : 0)
                    .background(
                        model.selectedSection == section
                            ? AppTheme.primary.opacity(0.14)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: isRegularSidebarExpanded ? .infinity : nil, alignment: .center)
                .accessibilityIdentifier(section.accessibilityIdentifier)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(model.selectedSection == section ? .isSelected : [])
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, isRegularSidebarExpanded ? 12 : 10)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.surface.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("layout.regular-sidebar")
    }

    private var tabNavigation: some View {
        TabView(selection: $model.selectedSection) {
            ForEach(AppSection.allCases) { section in
                compactTabSectionView(section)
                    .tabItem {
                        Label(section.title, systemImage: section.systemImage)
                            .accessibilityIdentifier(section.accessibilityIdentifier)
                    }
                    .tag(section)
            }
        }
        .tint(AppTheme.primary)
        .accessibilityIdentifier("layout.compact-tabs")
    }

    @ViewBuilder
    private func compactTabSectionView(_ section: AppSection) -> some View {
        if section == .calendar {
            sectionView(section)
                .ignoresSafeArea(.container, edges: .bottom)
        } else {
            sectionView(section)
        }
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            MobileTeachingCalendarView(session: session)
        } else {
            GeometryReader { proxy in
                switch AdaptiveLayoutPolicy.calendarPresentation(
                    width: proxy.size.width,
                    horizontalClass: AdaptiveHorizontalClass(horizontalSizeClass: horizontalSizeClass)
                ) {
                case .compact:
                    MobileTeachingCalendarView(session: session)
                case .expanded:
                    TeachingCalendarView(session: session)
                }
            }
        }
    }
}
#endif
