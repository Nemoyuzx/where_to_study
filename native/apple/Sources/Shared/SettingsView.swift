import SwiftUI
import WidgetKit

enum SettingsSurfaceID: String, Hashable {
    case account
    case qmplus
    case semester
    case notification
    case information
    case network
    case widget
    case colorTheme
    case language
    case aboutAndPrivacy
    case localData
}

enum AppFilingInformation {
    static let displayText = "APP 备案：琼ICP备2026012322号-2A"
    static let registryURL = URL(string: "https://beian.miit.gov.cn/")!
}

private struct FavoriteDeadlineManagementView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if model.favoriteDeadlines.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "star")
                            .font(.system(size: 30))
                            .foregroundStyle(theme.secondaryText)
                        Text("暂无收藏日程")
                            .font(.headline)
                        Text("在教学日历的 DDL 详情右侧点击星标后，会在这里保存完整快照。")
                            .font(.callout)
                            .foregroundStyle(theme.secondaryText)
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
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(theme.background)
        .navigationTitle("收藏管理")
        .accessibilityIdentifier("favorites.page")
    }

    private func favoriteRow(_ item: PublicDeadlineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(CalendarDeadlinePresentation.tint(for: item))
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
                .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 8)
            Button {
                AppHaptics.selection()
                model.setFavorite(item, isFavorite: false)
            } label: {
                Image(systemName: "star.fill")
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消收藏")
            .accessibilityIdentifier("favorites.remove.\(item.source.rawValue).\(item.id)")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
    }
}

#if os(iOS)
struct FavoriteDeadlineManagementPresentation: View {
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
        .qmplus,
        .semester
    ]

    static let trailingColumn: [SettingsSurfaceID] = [
        .notification,
        .information,
        .network,
        .widget,
        .colorTheme,
        .language,
        .aboutAndPrivacy,
        .localData
    ]

    static let singleColumn: [SettingsSurfaceID] = [
        .account,
        .qmplus,
        .semester,
        .notification,
        .information,
        .network,
        .widget,
        .colorTheme,
        .language,
        .aboutAndPrivacy,
        .localData
    ]
}

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    private enum AccountField: Hashable {
        case account
        case password
        case teachingCloudPassword
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: SettingsViewSession
    @State private var showingClearDataConfirmation = false
    @State private var widgetPreviewSize: WidgetPreviewSize = .medium
    @State private var customFeedValidationStatus = ""
    @State private var isValidatingCustomFeed = false
    @FocusState private var focusedAccountField: AccountField?

    init(session: SettingsViewSession) {
        self.session = session
    }

    private var privacyPresentation: PrivacyPolicyPresentation { session.privacyPresentation }
    private var supportPresentation: InAppPresentationState { session.supportPresentation }
    private var favoritePresentation: InAppPresentationState { session.favoritePresentation }
    private var reminderDraft: SettingsPreClassReminderDraft { session.reminderDraft }
    private var colorThemeDraft: SettingsColorThemeDraft { session.colorThemeDraft }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
            let columnCount = AdaptiveLayoutPolicy.contentColumnCount(width: proxy.size.width)
            Group {
            #if os(macOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageTitle(eyebrow: "Where To Study", title: "设置")
                    referenceNotice
                    if columnCount == 2 {
                        let widths = DesktopColumnLayoutPolicy.widths(containerWidth: proxy.size.width)
                        HStack(alignment: .top, spacing: 16) {
                            LazyVStack(spacing: 16) {
                                settingsSurfaces(SettingsLayoutPolicy.leadingColumn)
                            }
                            .frame(width: widths.leading, alignment: .top)
                            LazyVStack(spacing: 16) {
                                settingsSurfaces(SettingsLayoutPolicy.trailingColumn)
                            }
                            .frame(width: widths.trailing, alignment: .top)
                        }
                    } else {
                        LazyVStack(spacing: 16) {
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
                            LazyVStack(spacing: 16) {
                                settingsSurfaces(SettingsLayoutPolicy.leadingColumn)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            LazyVStack(spacing: 16) {
                                settingsSurfaces(SettingsLayoutPolicy.trailingColumn)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        LazyVStack(spacing: 16) {
                            settingsSurfaces(SettingsLayoutPolicy.singleColumn)
                        }
                    }
                }
                .padding(.horizontal, pageMetrics.horizontalPadding)
                .padding(.top, pageMetrics.topPadding)
                .padding(.bottom, pageMetrics.bottomPadding)
                .frame(maxWidth: columnCount == 2 ? 1120 : 720)
                .frame(maxWidth: .infinity)
                #if DEBUG && os(iOS)
                .background {
                    if (AppLaunchConfiguration.isUITesting || AppLaunchConfiguration.isReviewDemo),
                       ProcessInfo.processInfo.arguments.contains("--ui-test-language-geometry") {
                        SettingsLanguageViewportMarker()
                    }
                }
                #endif
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            #endif
            }
            .modifier(SettingsLanguageScrollAnchor(state: session.languageScroll, language: model.appLanguage))
            #if DEBUG
            .overlay(alignment: .topLeading) {
                SettingsLayoutMetricsProbe(columnCount: columnCount, width: proxy.size.width)
            }
            #endif
            }
            .background(theme.configuration.preset == .default ? Color.clear : theme.background)
        }
        .background(theme.background)
        .accessibilityIdentifier("screen.settings")
        .confirmationDialog(
            "清除本地数据？",
            isPresented: $showingClearDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除本地数据", role: .destructive) {
                AppHaptics.impact()
                model.clearLocalData()
                reminderDraft.reset(to: model.preClassNotificationOffsets)
                colorThemeDraft.reset(to: model.colorTheme.custom)
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
        case .qmplus:
            QMplusSettingsSurface(store: model.qmplus)
        case .semester:
            semesterSurface
        case .notification:
            notificationSurface
        case .information:
            informationSurface
        case .network:
            Surface { systemNetworkAssistanceDescription.frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxWidth: .infinity, alignment: .leading)
        case .widget:
            widgetSurface
        case .colorTheme:
            ColorThemeSettingsSurface(draft: colorThemeDraft)
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
                    .foregroundStyle(theme.secondaryText)
                if model.isSampleMode {
                    Label("内置示例模式已开启，不会连接教务服务或读写真实用户数据。", systemImage: "eye")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.primary)
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
                #if os(iOS)
                Link(destination: AppFilingInformation.registryURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                        Text(model.localized(AppFilingInformation.displayText))
                            .font(.callout)
                            .multilineTextAlignment(.center)
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text(model.localized(AppFilingInformation.displayText)))
                .accessibilityHint(
                    Text(model.localized("在工信部备案管理系统中查询备案信息"))
                )
                .accessibilityIdentifier("action.open-app-filing")
                #endif
                Button {
                    guard !supportPresentation.isPresented else { return }
                    AppHaptics.impact()
                    dismissKeyboard()
                    supportPresentation.isPresented = true
                } label: {
                    Label("帮助与支持", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("在应用内查看联系方式和常见问题")
                .accessibilityIdentifier("action.open-app-support")
                PrivacyPolicyButton(presentation: privacyPresentation, beforePresent: dismissKeyboard) {
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
                Text("Where To Study 是独立开发的非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.account-unofficial-notice")
                TextField("学号", text: $model.account)
                    .textFieldStyle(ThemeTextFieldStyle())
                    .disabled(model.isSampleMode)
                    .focused($focusedAccountField, equals: .account)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedAccountField = .password
                    }
                    .accessibilityIdentifier("field.account")
                VStack(alignment: .leading, spacing: 6) {
                    Text("教务密码")
                        .font(.subheadline.weight(.medium))
                    SecureField(
                        model.localized(
                            model.canPreserveSavedPassword
                                ? "已安全保存，留空保持不变"
                                : "教务密码"
                        ),
                        text: $model.password
                    )
                        .textFieldStyle(ThemeTextFieldStyle())
                        .disabled(model.isSampleMode)
                        .focused($focusedAccountField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedAccountField = .teachingCloudPassword
                        }
                        .accessibilityLabel("教务密码")
                        .accessibilityIdentifier("field.password")
                    Text("用于移动教务登录和查询课表、成绩及考试安排；可能与统一身份认证密码不同。部分账号的初始密码可能是八位出生日期（YYYYMMDD），请以本人实际设置为准。")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("教学云平台密码（选填）")
                        .font(.subheadline.weight(.medium))
                    SecureField(
                        model.localized(model.canPreserveSavedTeachingCloudPassword
                            ? "已安全保存，留空保持不变" : "留空使用教务密码"),
                        text: $model.teachingCloudPassword
                    )
                    .textFieldStyle(ThemeTextFieldStyle())
                    .disabled(model.isSampleMode)
                    .focused($focusedAccountField, equals: .teachingCloudPassword)
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }
                    .accessibilityLabel("教学云平台密码（选填）")
                    .accessibilityIdentifier("field.teaching-cloud-password")
                    Text(model.localized(model.canPreserveSavedTeachingCloudPassword
                        ? "已设置独立的教学云平台密码"
                        : "教学云平台当前使用教务密码"))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Text("用于课程作业 DDL 查询，通常是统一身份认证密码；未单独设置时使用教务密码。已保存的独立密码留空不变；修改后请保存设置。")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.canPreserveSavedTeachingCloudPassword || !model.teachingCloudPassword.isEmpty {
                        Button {
                            model.useAcademicPasswordForAssignments()
                        } label: {
                            Label("改用教务密码", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isSampleMode)
                        .accessibilityLabel("改用教务密码")
                        .accessibilityHint("清除单独保存的教学云密码，之后使用教务密码获取作业")
                        .accessibilityIdentifier("action.teaching-cloud-use-academic-password")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("保存账号前请阅读并同意隐私政策。")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    PrivacyPolicyButton(presentation: privacyPresentation, beforePresent: dismissKeyboard) {
                        Label("查看隐私政策", systemImage: "hand.raised")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("action.open-account-privacy-policy")
                }
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
                .background(ThemeSegmentedSurface())
                .disabled(model.isSampleMode)
                Button {
                    AppHaptics.impact()
                    model.saveSettings()
                } label: {
                    Label("保存设置", systemImage: "checkmark")
                        .foregroundStyle(theme.onPrimary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.primaryFill)
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
                if !model.currentCourseDeletions.isEmpty {
                    Divider()
                    Label("已删除课程（本学期）", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                    ForEach(model.currentCourseDeletions) { deletion in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(deletion.name).font(.subheadline)
                                Text(deletion.teacher).font(.caption)
                                Text(deletion.scope == .course
                                    ? model.localized("本学期整门课程")
                                    : "\(deletion.date ?? "") · \(deletion.startSlot + 1)–\(deletion.endSlot + 1)")
                                    .font(.caption)
                            }
                            Spacer()
                            Button("恢复") { model.restoreCourseDeletion(deletion) }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("action.restore-course.\(deletion.id)")
                        }
                    }
                }
                if !model.statusMessage.isEmpty {
                    Text(model.localized(model.statusMessage))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
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
                Menu {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            AppHaptics.selection()
                            changeInterfaceLanguage(to: language)
                        } label: {
                            HStack {
                                Text(verbatim: language == .system ? model.localized(language.titleKey) : language.nativeName)
                                if model.appLanguage == language { Image(systemName: "checkmark") }
                            }
                        }
                            .accessibilityIdentifier("settings.language.option.\(language.rawValue)")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: model.appLanguage == .system ? model.localized(model.appLanguage.titleKey) : model.appLanguage.nativeName)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryOnSoftSurface)
                .accessibilityLabel(model.localized("界面语言"))
                .accessibilityValue(model.appLanguage == .system ? model.localized(model.appLanguage.titleKey) : model.appLanguage.nativeName)
                .accessibilityIdentifier("settings.language")
                Text("API 、课程与竞赛返回的原始内容不会自动翻译。")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("settings.language")
        .modifier(SettingsLanguageCardAnchor())
    }

    private func changeInterfaceLanguage(to language: AppLanguage) {
        let apply = { [model, session] in
            session.languageScroll.capture(beforeSwitchTo: language)
            #if DEBUG && os(iOS)
            if (AppLaunchConfiguration.isUITesting || AppLaunchConfiguration.isReviewDemo),
               ProcessInfo.processInfo.arguments.contains("--ui-test-language-geometry") {
                SettingsLanguageViewportMarker.prepareForLanguageSwitch()
            }
            #endif
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.setAppLanguage(language) }
        }
        #if os(iOS) || os(macOS)
        session.languageTransition.request(
            current: model.appLanguage, target: language,
            label: model.localized("正在切换界面语言"), reduceMotion: reduceMotion,
            completionReady: { [weak model, weak scroll = session.languageScroll] in
                model?.appLanguage == language && model?.languageUpdatePending == false &&
                    model?.languageUpdateSucceeded == true &&
                    scroll?.isSettled(for: language) == true
            },
            completionFailed: { [weak model] in
                model?.appLanguage == language && model?.languageUpdatePending == false &&
                    model?.languageUpdateSucceeded == false
            },
            completionGeometry: { [weak scroll = session.languageScroll] in
                guard let scroll else { return [] }
                return scroll.readinessGeometry
            }, change: apply
        )
        #else
        guard language != model.appLanguage else { return }
        apply()
        #endif
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
                .tint(theme.primary)
                .disabled(model.isSampleMode)
                TextField("学期编号", text: $model.termID)
                    .textFieldStyle(ThemeTextFieldStyle())
                    .disabled(model.isSampleMode || model.automaticTermDetectionEnabled)
                    .focused($focusedAccountField, equals: .termID)
                    .submitLabel(.next)
                    .onSubmit { focusedAccountField = .termStartDate }
                    .accessibilityIdentifier("field.term-id")
                TextField("第一周周一（YYYY-MM-DD）", text: $model.termStartDate)
                    .textFieldStyle(ThemeTextFieldStyle())
                    .environment(\.layoutDirection, .leftToRight)
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
                .foregroundStyle(theme.secondaryText)
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
                    "每天发送当日课程摘要",
                    isOn: Binding(
                        get: { model.dailyCourseNotificationsEnabled },
                        set: { enabled in
                            AppHaptics.selection()
                            model.setDailyCourseNotificationsEnabled(enabled)
                        }
                    )
                )
                .toggleStyle(.switch)
                .accessibilityIdentifier("settings.daily-course.enabled")
                .tint(theme.primary)
                .disabled(model.isSampleMode && !model.isReviewDemo)
                DatePicker(
                    "提醒时间（北京时间）",
                    selection: Binding(
                        get: {
                            Calendar.shanghai.startOfDay(for: .now)
                                .addingTimeInterval(TimeInterval(model.dailyCourseNotificationMinutes * 60))
                        },
                        set: { date in
                            let parts = Calendar.shanghai.dateComponents([.hour, .minute], from: date)
                            model.setDailyCourseNotificationMinutes((parts.hour ?? 7) * 60 + (parts.minute ?? 30))
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .environment(\.timeZone, Calendar.shanghai.timeZone)
                .accessibilityIdentifier("settings.daily-course.time")
                .disabled(model.isSampleMode && !model.isReviewDemo)
                Text("仅在当天有课时通知；课表更新或账号变更后会自动重排。")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                if !model.dailyCourseNotificationStatusMessage.isEmpty {
                    Text(model.localized(model.dailyCourseNotificationStatusMessage))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
                Divider()
                PreClassReminderSettingsView(draft: reminderDraft)
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
                    markerColor: AppTheme.competitionDeadline
                )
                featureToggle(
                    "校内竞赛通知",
                    isOn: model.schoolContestNoticesEnabled,
                    set: model.setSchoolContestNoticesEnabled,
                    markerColor: AppTheme.schoolNotice
                )
                featureToggle(
                    "学术会议/期刊专题 DDL",
                    isOn: model.conferenceDeadlinesEnabled,
                    set: model.setConferenceDeadlinesEnabled,
                    markerColor: AppTheme.conferenceDeadline
                )
                featureToggle(
                    "夏令营/预推免 DDL",
                    isOn: model.summerCampDeadlinesEnabled,
                    set: model.setSummerCampDeadlinesEnabled,
                    markerColor: AppTheme.summerCampDeadline
                )
                featureToggle(
                    "黑客松 DDL",
                    isOn: model.hackathonDeadlinesEnabled,
                    set: model.setHackathonDeadlinesEnabled,
                    markerColor: AppTheme.hackathonDeadline
                )
                Divider()
                Toggle(
                    isOn: Binding(
                        get: { model.customDeadlinesEnabled },
                        set: { enabled in
                            AppHaptics.selection()
                            model.setCustomDeadlinesEnabled(enabled)
                        }
                    )
                ) {
                    HStack(spacing: 8) {
                        Text(model.localized("自定义日程源"))
                        Spacer(minLength: 8)
                        Circle()
                            .fill(AppTheme.customDeadline)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }
                .toggleStyle(.switch)
                .tint(theme.primary)
                .disabled(model.isSampleMode)
                .accessibilityIdentifier("settings.custom-deadlines-enabled")
                TextField("自定义日程 HTTPS 地址", text: $model.customDeadlinesURL)
                    .textFieldStyle(ThemeTextFieldStyle())
                    .environment(\.layoutDirection, .leftToRight)
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
                        .foregroundStyle(theme.secondaryText)
                        .accessibilityIdentifier("settings.custom-deadlines-status")
                }
                Text("自定义源只发送不带凭据的 HTTPS GET；普通条目随开关隐藏，收藏快照始终保留在本机。")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                Group {
                    #if os(iOS)
                    Button {
                        guard !favoritePresentation.isPresented else { return }
                        favoritePresentation.isPresented = true
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
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var referenceNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(theme.primaryOnSoftSurface)
            Text("显示数据仅供参考，请以实际情况为准。\nDisplayed data is for reference only; please rely on the actual official information.")
                .font(.callout)
                .foregroundStyle(theme.secondaryOnSoftSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("settings.reference-notice")
    }

    private var systemNetworkAssistanceDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.localized("系统网络辅助"), systemImage: "wifi").font(.headline)
            #if os(iOS)
            Text(model.localized("支持蜂窝网络的 iPhone／iPad 可在系统设置管理“连接助理”（较旧系统为“Wi-Fi 助理”）。Wi-Fi 较弱时是否使用蜂窝数据由系统、机型及网络条件决定。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            Link(model.localized("查看 Apple 官方网络辅助说明"), destination: URL(string: "https://support.apple.com/127686")!)
                .font(.caption).accessibilityIdentifier("settings.network-assistance.help")
            #else
            Text(model.localized("macOS 可在系统设置中选择可用网络或个人热点。本应用不提供强制蜂窝网络或双通道开关。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            #endif
            Text(model.localized("本应用不会自动开启或更改系统网络辅助，也不能保证 Wi-Fi 与蜂窝网络同时使用。蜂窝数据或个人热点可能产生额外费用，请自行确认套餐。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
        }.accessibilityIdentifier("settings.network-assistance")
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
        .tint(theme.primary)
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
                .tint(theme.primary)
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
                .tint(theme.primary)
                .disabled(model.isSampleMode)

                Text("最多显示课程")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
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
                .background(ThemeSegmentedSurface())
                .labelsHidden()
                .disabled(model.isSampleMode)

                Divider()
                HStack {
                    Label("样式预览", systemImage: "eye")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("示例内容")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
                Picker("预览尺寸", selection: $widgetPreviewSize) {
                    ForEach(WidgetPreviewSize.allCases) { size in
                        Text(model.localized(size.title)).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .background(ThemeSegmentedSurface())
                .labelsHidden()
                TodayCourseWidgetCard(
                    date: .now,
                    courses: TodayCourseWidgetData.previewTodayCourses(),
                    tomorrowCourses: TodayCourseWidgetData.previewTomorrowCourses(),
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
                    ),
                    colorTheme: model.colorTheme
                )
                .aspectRatio(widgetPreviewSize.aspectRatio, contentMode: .fit)
                .frame(maxWidth: widgetPreviewSize.maximumWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("今日课程小组件\(widgetPreviewSize.title)样式预览")
                .accessibilityIdentifier("widget.preview")

                Text("小组件优先显示今日课程，空间充足时显示明日课程；两日合计不超过课程数量设置，大号最多 6 门。设置会应用到本机小组件。")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
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
                    .foregroundStyle(theme.secondaryText)
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
                .foregroundStyle(theme.primary)
        } else if SemesterLogic.isValidTermID(model.termID),
                  SemesterLogic.isValidTermStartDate(model.termStartDate) {
            Label("当前设置与检测结果不同", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func applySuggestedTerm() {
        let suggested = SemesterLogic.suggestTerm()
        model.termID = suggested.termID
        model.termStartDate = suggested.termStartDate
    }

    private func dismissKeyboard() {
        if focusedAccountField != nil { focusedAccountField = nil }
    }
}

private struct QMplusSettingsSurface: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: QMplusStore
    @State private var detailsExpanded = false

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader
                featureToggle
                ExpandableContent(expanded: detailsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                Text(model.localized("登录与同步在后台完成，只在需要验证码或 MFA 时自动显示官方窗口。无法识别的页面会暂停，您可手动继续。"))
                    .font(.callout).foregroundStyle(theme.secondaryText)
                Text(model.localized(store.statusKey)).font(.caption).foregroundStyle(theme.secondaryText)
                if let code = store.automaticLoginDiagnostic {
                    Text(verbatim: "QMplus · \(code)").font(.caption2.monospaced())
                        .foregroundStyle(theme.secondaryText).textSelection(.enabled)
                        .accessibilityIdentifier("settings.qmplus.diagnostic")
                }
                ViewThatFits(in: .horizontal) {
                    HStack { connectionActions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading) { connectionActions }
                }
                .buttonStyle(.bordered)
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["WTS_QMPLUS_AUTH_TRACE"] == "1" {
                    Button("QA: Show courses") { model.navigation.selectedSection = .courses }
                        .accessibilityIdentifier("qa.qmplus.show-courses")
                }
                #endif
                if store.requiresManualContinuation {
                    Button { store.continueManually(sampleMode: model.isSampleMode) } label: {
                        Label(model.localized("手动继续"), systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered).disabled(model.isSampleMode || !model.qmplusEnabled)
                    .accessibilityIdentifier("settings.qmplus.manual-continue")
                }
                QMplusCredentialSettingsEditor(authorization: store.credentialAuthorization, draft: store.credentialDraft,
                    language: model.appLanguage, sampleMode: model.isSampleMode,
                    save: store.saveCredentials, disable: store.disableCredentialAutofill)
                Text(model.localized("QMplus 使用独立的官方网页登录，与北邮教务账号无关。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: detailsExpanded)
        .onAppear { detailsExpanded = model.qmplusEnabled }
        .onChange(of: model.qmplusEnabled) { detailsExpanded = $0 }
        .accessibilityIdentifier("settings.qmplus")
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label("QMplus", systemImage: "network").font(.headline).fixedSize()
            Text(model.localized("仅适用国院")).font(.caption).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { detailsExpanded.toggle() } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(detailsExpanded ? 180 : 0))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.localized(detailsExpanded ? "收起" : "展开"))
            .accessibilityIdentifier("settings.qmplus.details-toggle")
        }
    }

    private var featureToggle: some View {
        let binding = Binding<Bool>(
            get: { model.qmplusEnabled },
            set: { model.setQMplusEnabled($0) })
        return Toggle(model.localized("启用 QMplus"), isOn: binding)
            .toggleStyle(.switch)
            .disabled(model.isSampleMode)
            .accessibilityIdentifier("settings.qmplus.enabled")
    }

    @ViewBuilder private var connectionActions: some View {
        Button(model.localized("连接 QMplus")) { store.connect(sampleMode: model.isSampleMode) }
            .disabled(model.isSampleMode || !model.qmplusEnabled).accessibilityIdentifier("settings.qmplus.connect")
    }
}

#if DEBUG
private struct SettingsLayoutMetricsProbe: View {
    let columnCount: Int
    let width: CGFloat

    var body: some View {
        if (AppLaunchConfiguration.isUITesting || AppLaunchConfiguration.isUITestingLive || AppLaunchConfiguration.isReviewDemo)
            && ProcessInfo.processInfo.arguments.contains("--ui-test-settings-layout") {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Settings layout metrics")
                .accessibilityValue("\(columnCount)|\(width)")
                .accessibilityIdentifier("settings.layout-metrics")
                .accessibilityHidden(false)
                .allowsHitTesting(false)
        }
    }
}
#endif
