import SwiftUI
import WidgetKit

enum SettingsSurfaceID: String, Hashable {
    case account
    case semester
    case notification
    case information
    case queries
    case widget
    case language
    case aboutAndPrivacy
    case localData
}

private struct FavoriteDeadlineManagementView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if model.favoriteDeadlines.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "star")
                            .font(.system(size: 30))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("暂无收藏日程")
                            .font(.headline)
                        Text("在教学日历的 DDL 详情右侧点击星标后，会在这里保存完整快照。")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    ForEach(model.favoriteDeadlines, id: \.favoriteID) { item in
                        favoriteRow(item)
                    }
                }
                Text("收藏仅保存在本机，不会上传或跨设备同步；清除本地数据会一并删除。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(AppTheme.background)
        .navigationTitle("收藏管理")
        .accessibilityIdentifier("favorites.page")
    }

    private func favoriteRow(_ item: PublicDeadlineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(item.source == .schoolNotice ? AppTheme.schoolNotice : AppTheme.publicDeadline)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text(
                    [
                        String(item.deadline.prefix(16)).replacingOccurrences(of: "T", with: " "),
                        item.sourceName ?? item.source.title,
                        item.organizer,
                    ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 8)
            Button {
                AppHaptics.selection()
                model.setFavorite(item, isFavorite: false)
            } label: {
                Image(systemName: "star.fill")
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消收藏")
            .accessibilityIdentifier("favorites.remove.\(item.source.rawValue).\(item.id)")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1))
    }
}

#if os(iOS)
private struct FavoriteDeadlineManagementPresentation: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FavoriteDeadlineManagementView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                            .accessibilityIdentifier("favorites.dismiss")
                    }
                }
        }
    }
}
#endif

enum SettingsLayoutPolicy {
    static let leadingColumn: [SettingsSurfaceID] = [
        .account,
        .semester
    ]

    static let trailingColumn: [SettingsSurfaceID] = [
        .notification,
        .information,
        .queries,
        .widget,
        .language,
        .aboutAndPrivacy,
        .localData
    ]

    static let singleColumn: [SettingsSurfaceID] = [
        .account,
        .semester,
        .notification,
        .information,
        .queries,
        .widget,
        .language,
        .aboutAndPrivacy,
        .localData
    ]
}

struct SettingsView: View {
    private enum AccountField: Hashable {
        case account
        case password
        case termID
        case termStartDate
        case customURL
    }

    private enum WidgetPreviewSize: String, CaseIterable, Identifiable {
        case small
        case medium
        case large

        var id: String { rawValue }

        var title: String {
            switch self {
            case .small: "小号"
            case .medium: "中号"
            case .large: "大号"
            }
        }

        var family: WidgetFamily {
            switch self {
            case .small: .systemSmall
            case .medium: .systemMedium
            case .large: .systemLarge
            }
        }

        var aspectRatio: CGFloat {
            switch self {
            case .small, .large: 1
            case .medium: 2.12
            }
        }

        var maximumWidth: CGFloat {
            switch self {
            case .small: 174
            case .medium, .large: 360
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var calendarDeadlines: CalendarDeadlineStore
    @State private var showingClearDataConfirmation = false
    @State private var showingPrivacyPolicy = false
    @State private var showingFavoriteManagement = false
    @State private var widgetPreviewSize: WidgetPreviewSize = .medium
    @State private var customFeedValidationStatus = ""
    @State private var isValidatingCustomFeed = false
    @FocusState private var focusedAccountField: AccountField?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
            let columnCount = AdaptiveLayoutPolicy.contentColumnCount(width: proxy.size.width)
            #if os(macOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageTitle(eyebrow: "Where To Study", title: "设置")
                    referenceNotice
                    if columnCount == 2 {
                        let widths = DesktopColumnLayoutPolicy.widths(containerWidth: proxy.size.width)
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                settingsSurfaces(SettingsLayoutPolicy.leadingColumn)
                            }
                            .frame(width: widths.leading, alignment: .top)
                            VStack(spacing: 16) {
                                settingsSurfaces(SettingsLayoutPolicy.trailingColumn)
                            }
                            .frame(width: widths.trailing, alignment: .top)
                        }
                    } else {
                        VStack(spacing: 16) {
                            settingsSurfaces(SettingsLayoutPolicy.singleColumn)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            #else
            let pageMetrics = MobilePageLayoutPolicy.metrics(availableHeight: proxy.size.height)
            ScrollView {
                VStack(alignment: .leading, spacing: pageMetrics.sectionSpacing) {
                    PageTitle(
                        eyebrow: "Where To Study",
                        title: "设置",
                        compact: pageMetrics.usesCompactTitle
                    )
                    referenceNotice
                    if columnCount == 2 {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                settingsSurfaces(SettingsLayoutPolicy.leadingColumn)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            VStack(spacing: 16) {
                                settingsSurfaces(SettingsLayoutPolicy.trailingColumn)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        VStack(spacing: 16) {
                            settingsSurfaces(SettingsLayoutPolicy.singleColumn)
                        }
                    }
                }
                .padding(.horizontal, pageMetrics.horizontalPadding)
                .padding(.top, pageMetrics.topPadding)
                .padding(.bottom, pageMetrics.bottomPadding)
                .frame(maxWidth: columnCount == 2 ? 1120 : 720)
                .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            #endif
            }
        }
        .background(AppTheme.background)
        .accessibilityIdentifier("screen.settings")
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingFavoriteManagement) {
            FavoriteDeadlineManagementPresentation()
        }
        #endif
        .confirmationDialog(
            "清除本地数据？",
            isPresented: $showingClearDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除本地数据", role: .destructive) {
                AppHaptics.impact()
                model.clearLocalData()
            }
            Button("取消", role: .cancel) {
                AppHaptics.impact()
            }
        } message: {
            Text("此操作会删除本机保存的账户密码、个人课表、空教室、节假日缓存、自定义日程设置与收藏，且无法撤销。")
        }
    }

    @ViewBuilder
    private func settingsSurfaces(_ surfaces: [SettingsSurfaceID]) -> some View {
        ForEach(surfaces, id: \.self) { surface in
            settingsSurface(surface)
        }
    }

    @ViewBuilder
    private func settingsSurface(_ surface: SettingsSurfaceID) -> some View {
        switch surface {
        case .account:
            accountSurface
        case .semester:
            semesterSurface
        case .notification:
            notificationSurface
        case .information:
            informationSurface
        case .queries:
            queriesSurface
        case .widget:
            widgetSurface
        case .language:
            languageSurface
        case .aboutAndPrivacy:
            aboutSurface
        case .localData:
            localDataSurface
        }
    }

    private var aboutSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Label("关于本应用", systemImage: "info.circle")
                    .font(.headline)
                Text("Where To Study 是独立开发的非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                if model.isSampleMode {
                    Label("内置示例模式已开启，不会连接教务服务或读写真实用户数据。", systemImage: "eye")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                    if model.canExitSampleMode {
                        Button {
                            AppHaptics.impact()
                            model.exitReviewDemo()
                        } label: {
                            Label("返回真实数据", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("action.exit-sample-mode")
                    }
                } else {
                    Button {
                        AppHaptics.impact()
                        model.enterReviewDemo()
                    } label: {
                        Label("浏览内置示例数据", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canEnterReviewDemo)
                    .accessibilityIdentifier("action.enter-sample-mode")
                }
                Divider()
                Button {
                    AppHaptics.impact()
                    dismissKeyboard()
                    showingPrivacyPolicy = true
                } label: {
                    Label("隐私说明", systemImage: "hand.raised")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("隐私说明")
                .accessibilityHint("在应用内查看隐私声明")
                .accessibilityIdentifier("action.open-privacy-policy")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("个人账户", systemImage: "person.crop.circle")
                    Spacer()
                    #if os(iOS)
                    if focusedAccountField != nil {
                        Button("完成") {
                            AppHaptics.impact()
                            dismissKeyboard()
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("action.dismiss-keyboard")
                    }
                    #endif
                }
                .font(.headline)
                TextField("学号", text: $model.account)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSampleMode)
                    .focused($focusedAccountField, equals: .account)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedAccountField = .password
                    }
                    .accessibilityIdentifier("field.account")
                SecureField(
                    model.localized(
                        model.canPreserveSavedPassword
                            ? "已安全保存，留空保持不变"
                            : "教务密码"
                    ),
                    text: $model.password
                )
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSampleMode)
                    .focused($focusedAccountField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit {
                        dismissKeyboard()
                    }
                    .accessibilityIdentifier("field.password")
                Picker(
                    "默认校区",
                    selection: Binding(
                        get: { model.campusID },
                        set: { campusID in
                            guard campusID != model.campusID else { return }
                            AppHaptics.selection()
                            model.campusID = campusID
                        }
                    )
                ) {
                    Text("西土城").tag("01")
                    Text("沙河").tag("04")
                }
                .pickerStyle(.segmented)
                .disabled(model.isSampleMode)
                Button {
                    AppHaptics.impact()
                    model.saveSettings()
                } label: {
                    Label("保存设置", systemImage: "checkmark")
                        .foregroundStyle(AppTheme.onPrimary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryFill)
                .disabled(model.isSampleMode)
                Button {
                    AppHaptics.impact()
                    if model.saveSettings() {
                        model.refreshSchedule()
                    }
                } label: {
                    Label(
                        model.isRefreshingSchedule ? "正在获取…" : "获取/刷新个人课表",
                        systemImage: "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isRefreshingSchedule || model.isSampleMode)
                if !model.statusMessage.isEmpty {
                    Text(model.localized(model.statusMessage))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var languageSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("界面语言", systemImage: "globe")
                    .font(.headline)
                Picker(
                    "界面语言",
                    selection: Binding(
                        get: { model.appLanguage },
                        set: { language in
                            AppHaptics.selection()
                            model.setAppLanguage(language)
                        }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(model.localized(language.titleKey)).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                Text("API 、课程与竞赛返回的原始内容不会自动翻译。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("settings.language")
    }

    private var semesterSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("学期设置", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Toggle(
                    "自动检测当前学期",
                    isOn: Binding(
                        get: { model.automaticTermDetectionEnabled },
                        set: { enabled in
                            AppHaptics.selection()
                            model.setAutomaticTermDetectionEnabled(enabled)
                        }
                    )
                )
                .toggleStyle(.switch)
                .tint(AppTheme.primary)
                .disabled(model.isSampleMode)
                TextField("学期编号", text: $model.termID)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSampleMode || model.automaticTermDetectionEnabled)
                    .focused($focusedAccountField, equals: .termID)
                    .submitLabel(.next)
                    .onSubmit { focusedAccountField = .termStartDate }
                    .accessibilityIdentifier("field.term-id")
                TextField("第一周周一（YYYY-MM-DD）", text: $model.termStartDate)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSampleMode || model.automaticTermDetectionEnabled)
                    .focused($focusedAccountField, equals: .termStartDate)
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }
                    .accessibilityIdentifier("field.term-start-date")
                Text(
                    model.automaticTermDetectionEnabled
                        ? "启动或获取/刷新课表后，会自动应用教务返回的学期与开学日期。"
                        : "已关闭自动检测，将使用上方手动填写的学期信息。"
                )
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
                Button {
                    AppHaptics.impact()
                    model.saveSettings()
                } label: {
                    Label("保存学期设置", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isSampleMode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notificationSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("课程提醒", systemImage: "bell")
                    .font(.headline)
                Toggle(
                    "每天 07:30 发送当日课程摘要",
                    isOn: Binding(
                        get: { model.dailyCourseNotificationsEnabled },
                        set: { enabled in
                            AppHaptics.selection()
                            model.setDailyCourseNotificationsEnabled(enabled)
                        }
                    )
                )
                .toggleStyle(.switch)
                .tint(AppTheme.primary)
                .disabled(model.isSampleMode && !model.isReviewDemo)
                Text("仅在当天有课时通知；课表更新或账号变更后会自动重排。")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                if !model.dailyCourseNotificationStatusMessage.isEmpty {
                    Text(model.localized(model.dailyCourseNotificationStatusMessage))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var informationSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("日期详情与生活信息", systemImage: "rectangle.stack.badge.plus")
                    .font(.headline)
                featureToggle(
                    "校区天气",
                    isOn: model.weatherEnabled,
                    set: model.setWeatherEnabled
                )
                featureToggle(
                    "黄历与宜忌",
                    isOn: model.almanacEnabled,
                    set: model.setAlmanacEnabled
                )
                Divider()
                deadlineLegend("课程作业 DDL", color: AppTheme.assignment)
                featureToggle(
                    "学科竞赛 DDL",
                    isOn: model.competitionDeadlinesEnabled,
                    set: model.setCompetitionDeadlinesEnabled,
                    markerColor: AppTheme.publicDeadline
                )
                featureToggle(
                    "校内竞赛通知",
                    isOn: model.schoolContestNoticesEnabled,
                    set: model.setSchoolContestNoticesEnabled,
                    markerColor: AppTheme.schoolNotice
                )
                featureToggle(
                    "学术会议 DDL",
                    isOn: model.conferenceDeadlinesEnabled,
                    set: model.setConferenceDeadlinesEnabled,
                    markerColor: AppTheme.publicDeadline
                )
                featureToggle(
                    "夏令营 DDL",
                    isOn: model.summerCampDeadlinesEnabled,
                    set: model.setSummerCampDeadlinesEnabled,
                    markerColor: AppTheme.publicDeadline
                )
                featureToggle(
                    "黑客松 DDL",
                    isOn: model.hackathonDeadlinesEnabled,
                    set: model.setHackathonDeadlinesEnabled,
                    markerColor: AppTheme.publicDeadline
                )
                Divider()
                Toggle(
                    "自定义日程源",
                    isOn: Binding(
                        get: { model.customDeadlinesEnabled },
                        set: { enabled in
                            AppHaptics.selection()
                            model.setCustomDeadlinesEnabled(enabled)
                        }
                    )
                )
                .toggleStyle(.switch)
                .tint(AppTheme.primary)
                .disabled(model.isSampleMode)
                .accessibilityIdentifier("settings.custom-deadlines-enabled")
                TextField("自定义日程 HTTPS 地址", text: $model.customDeadlinesURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSampleMode)
                    .focused($focusedAccountField, equals: .customURL)
                    .onSubmit { validateAndSaveCustomFeed() }
                    .accessibilityIdentifier("settings.custom-deadlines-url")
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    #endif
                Button {
                    validateAndSaveCustomFeed()
                } label: {
                    Label(
                        isValidatingCustomFeed ? "正在校验…" : "保存并校验自定义源",
                        systemImage: "checkmark.shield"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isSampleMode || isValidatingCustomFeed)
                .accessibilityIdentifier("settings.custom-deadlines-save")
                if !customFeedValidationStatus.isEmpty {
                    Text(model.localized(customFeedValidationStatus))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .accessibilityIdentifier("settings.custom-deadlines-status")
                }
                Text("自定义源只发送不带凭据的 HTTPS GET；普通条目随开关隐藏，收藏快照始终保留在本机。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Group {
                    #if os(iOS)
                    Button {
                        showingFavoriteManagement = true
                    } label: {
                        Label("收藏管理", systemImage: "star")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    #else
                    NavigationLink {
                        FavoriteDeadlineManagementView()
                    } label: {
                        Label("收藏管理", systemImage: "star")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    #endif
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.favorite-management")
                Text("天气、黄历和 DDL 来自第三方公开服务；校内竞赛通知由脚本从学校内部网站公开通知页提取整理，各卡片底部会标明具体来源。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var queriesSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Label("信息查询", systemImage: "magnifyingglass")
                    .font(.headline)
                Text("查询今日班车状态与当前生效时刻表，或搜索、分类浏览公开活动和校内竞赛通知。")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                NavigationLink {
                    InformationQueriesView()
                } label: {
                    Label("打开班车与重要事件查询", systemImage: "bus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.open-information-queries")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var referenceNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(AppTheme.primary)
            Text("显示数据仅供参考，请以实际情况为准。\nDisplayed data is for reference only; please rely on the actual official information.")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("settings.reference-notice")
    }

    private func featureToggle(
        _ title: String,
        isOn: Bool,
        set: @escaping (Bool) -> Void,
        markerColor: Color? = nil
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { isOn },
                set: { enabled in
                    AppHaptics.selection()
                    set(enabled)
                }
            )
        ) {
            HStack(spacing: 8) {
                Text(model.localized(title))
                Spacer(minLength: 8)
                if let markerColor {
                    Circle()
                        .fill(markerColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(AppTheme.primary)
        .disabled(model.isSampleMode)
    }

    private func deadlineLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(model.localized(title))
            Spacer(minLength: 8)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func validateAndSaveCustomFeed() {
        AppHaptics.impact()
        dismissKeyboard()
        do {
            guard let url = try model.saveCustomDeadlineSettings() else {
                customFeedValidationStatus = "自定义日程设置已保存"
                calendarDeadlines.clearCustomSource()
                return
            }
            isValidatingCustomFeed = true
            customFeedValidationStatus = "正在校验自定义日程源…"
            Task { @MainActor in
                defer { isValidatingCustomFeed = false }
                do {
                    let metadata = try await calendarDeadlines.validateCustomFeed(sourceURL: url)
                    customFeedValidationStatus = model.localizedFormat(
                        "自定义日程源校验成功：%@，%lld 项",
                        metadata.sourceName,
                        Int64(metadata.itemCount)
                    )
                } catch {
                    customFeedValidationStatus = error.localizedDescription
                }
            }
        } catch {
            customFeedValidationStatus = error.localizedDescription
        }
    }

    private var widgetSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("桌面小组件", systemImage: "rectangle.grid.1x2")
                    .font(.headline)
                Toggle(
                    "显示课程地点",
                    isOn: Binding(
                        get: { model.widgetShowsLocation },
                        set: { enabled in
                            AppHaptics.selection()
                            model.setWidgetShowsLocation(enabled)
                        }
                    )
                )
                .toggleStyle(.switch)
                .tint(AppTheme.primary)
                .disabled(model.isSampleMode)
                Toggle(
                    "显示任课教师",
                    isOn: Binding(
                        get: { model.widgetShowsTeacher },
                        set: { enabled in
                            AppHaptics.selection()
                            model.setWidgetShowsTeacher(enabled)
                        }
                    )
                )
                .toggleStyle(.switch)
                .tint(AppTheme.primary)
                .disabled(model.isSampleMode)

                Text("最多显示课程")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                Picker(
                    "最多显示课程",
                    selection: Binding(
                        get: { model.widgetCourseLimit },
                        set: { limit in
                            AppHaptics.selection()
                            model.setWidgetCourseLimit(limit)
                        }
                    )
                ) {
                    ForEach(1 ... TodayCourseWidgetData.maximumCourseLimit, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.isSampleMode)

                Divider()
                HStack {
                    Label("样式预览", systemImage: "eye")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("示例内容")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Picker("预览尺寸", selection: $widgetPreviewSize) {
                    ForEach(WidgetPreviewSize.allCases) { size in
                        Text(model.localized(size.title)).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TodayCourseWidgetCard(
                    date: .now,
                    courses: TodayCourseWidgetData.previewCourses(),
                    preferences: TodayCourseWidgetData.Preferences(
                        showsLocation: model.widgetShowsLocation,
                        showsTeacher: model.widgetShowsTeacher,
                        courseLimit: model.widgetCourseLimit
                    ),
                    weekNumber: 8,
                    family: widgetPreviewSize.family,
                    usesWidgetContainer: false,
                    language: TodayCourseWidgetData.Language.resolve(
                        rawValue: model.appLanguage.rawValue
                    )
                )
                .aspectRatio(widgetPreviewSize.aspectRatio, contentMode: .fit)
                .frame(maxWidth: widgetPreviewSize.maximumWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("今日课程小组件\(widgetPreviewSize.title)样式预览")
                .accessibilityIdentifier("widget.preview")

                Text("小组件会显示日期、教学周、当前或下一节状态、节次、地点与教师；大号样式最多展示 6 门课程。设置会同步到 iPhone、iPad 与 Mac。")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var localDataSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("本地数据", systemImage: "externaldrive")
                    .font(.headline)
                Text("清除已保存的教务账户与密码、个人课表、空教室、节假日缓存、自定义日程设置与收藏，并恢复本地设置。")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                Button(role: .destructive) {
                    AppHaptics.impact()
                    showingClearDataConfirmation = true
                } label: {
                    Label("清除本地数据", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isSampleMode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var termConsistencyIndicator: some View {
        if SemesterLogic.matchesCurrentPeriod(
            termID: model.termID,
            termStartDate: model.termStartDate
        ) {
            Label("✓ 与当前学期一致", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.primary)
        } else if SemesterLogic.isValidTermID(model.termID),
                  SemesterLogic.isValidTermStartDate(model.termStartDate) {
            Label("当前设置与检测结果不同", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func applySuggestedTerm() {
        let suggested = SemesterLogic.suggestTerm()
        model.termID = suggested.termID
        model.termStartDate = suggested.termStartDate
    }

    private func dismissKeyboard() {
        focusedAccountField = nil
    }
}
