import SwiftUI

struct SettingsView: View {
    private enum AccountField: Hashable {
        case account
        case password
        case termID
        case termStartDate
    }

    @EnvironmentObject private var model: AppModel
    @State private var showingClearDataConfirmation = false
    @State private var showingPrivacyPolicy = false
    @FocusState private var focusedAccountField: AccountField?

    var body: some View {
        GeometryReader { proxy in
            let columnCount = AdaptiveLayoutPolicy.contentColumnCount(width: proxy.size.width)
            #if os(macOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageTitle(eyebrow: "Where To Study", title: "设置")
                    if columnCount == 2 {
                        let widths = DesktopColumnLayoutPolicy.widths(containerWidth: proxy.size.width)
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                accountSurface
                            }
                            .frame(width: widths.leading, alignment: .top)
                            VStack(spacing: 16) {
                                notificationSurface
                                localDataSurface
                                aboutSurface
                            }
                            .frame(width: widths.trailing, alignment: .top)
                        }
                    } else {
                        VStack(spacing: 16) {
                            accountSurface
                            notificationSurface
                            localDataSurface
                            aboutSurface
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
                    if columnCount == 2 {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                accountSurface
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            VStack(spacing: 16) {
                                notificationSurface
                                localDataSurface
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                        aboutSurface
                    } else {
                        VStack(spacing: 16) {
                            accountSurface
                            notificationSurface
                            localDataSurface
                            aboutSurface
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
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            #endif
            #endif
        }
        .background(AppTheme.background)
        .accessibilityIdentifier("screen.settings")
        .animation(.easeInOut(duration: 0.22), value: model.statusMessage)
        .animation(.easeInOut(duration: 0.22), value: model.dailyCourseNotificationStatusMessage)
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    AppHaptics.impact()
                    dismissKeyboard()
                }
                .accessibilityIdentifier("action.dismiss-keyboard")
            }
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
            Text("此操作会删除本机保存的账户密码、个人课表、空教室和节假日缓存，且无法撤销。")
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
    }

    private var accountSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Label("个人账户", systemImage: "person.crop.circle")
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
                    model.canPreserveSavedPassword ? "已安全保存，留空保持不变" : "教务密码",
                    text: $model.password
                )
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSampleMode)
                    .focused($focusedAccountField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedAccountField = .termID
                    }
                    .accessibilityIdentifier("field.password")
                TextField("学期编号", text: $model.termID)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSampleMode)
                    .focused($focusedAccountField, equals: .termID)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedAccountField = .termStartDate
                    }
                    .accessibilityIdentifier("field.term-id")
                TextField("第一周周一（YYYY-MM-DD）", text: $model.termStartDate)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSampleMode)
                    .focused($focusedAccountField, equals: .termStartDate)
                    .submitLabel(.done)
                    .onSubmit {
                        dismissKeyboard()
                    }
                    .accessibilityIdentifier("field.term-start-date")
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
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isRefreshingSchedule || model.isSampleMode)
                if !model.statusMessage.isEmpty {
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
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
                .tint(AppTheme.primary)
                .disabled(model.isSampleMode && !model.isReviewDemo)
                Text("仅在当天有课时通知；课表更新或账号变更后会自动重排。")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                if !model.dailyCourseNotificationStatusMessage.isEmpty {
                    Text(model.dailyCourseNotificationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var localDataSurface: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label("本地数据", systemImage: "externaldrive")
                    .font(.headline)
                Text("清除已保存的教务账户与密码、个人课表、空教室和节假日缓存，并恢复本地设置。")
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
    }

    private func dismissKeyboard() {
        focusedAccountField = nil
    }
}
