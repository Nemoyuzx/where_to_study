import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private static let githubURL = URL(
        string: "https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md"
    )!

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WHERE TO STUDY")
                            .font(.caption.bold())
                            .foregroundStyle(theme.secondaryText)
                        Text("隐私声明 / Privacy Policy")
                            .font(.largeTitle.bold())
                            .foregroundStyle(theme.text)
                            .accessibilityIdentifier("screen.privacy-policy")
                        Text("生效日期 / Effective date: 2026-10-03")
                            .font(.callout)
                            .foregroundStyle(theme.secondaryText)
                    }

                    #if os(iOS) && DEBUG
                    if PrivacyPolicyPresentationTiming.isEnabled {
                        MobileDetailPresentationProbe(
                            metricsLabel: "Privacy policy presentation metrics",
                            requestedAt: { PrivacyPolicyPresentationTiming.requestedAt }
                        ).frame(width: 48, height: 10)
                    }
                    #endif

                    Text("Where To Study 是用于查看北京邮电大学个人课表、空教室及相关学习信息的独立非官方客户端，不由学校运营，也不代表学校官方立场。\n\nWhere To Study is an independent, unofficial client for BUPT schedules, empty classrooms, and related study information. It is not operated by or affiliated with BUPT.")
                        .foregroundStyle(theme.text)

                    privacySection(
                        title: "账户与教务请求 / Account and academic requests",
                        body: "学号和密码保存在操作系统的受保护凭据存储中。保存有效凭据且开启自动学期检测后，启动时会自动刷新一次个人课表以校验学期号和第一周周一。你主动请求课表、空教室或作业时也会按对应用途通过 HTTPS 使用凭据。课表和空教室请求发送到 jwglweixin.bupt.edu.cn；平台允许时还可能自动刷新当天空教室。维护者无法读取凭据，设置接口也不会返回密码。\n\nCredentials stay in protected OS storage. With valid saved credentials and automatic term detection enabled, the app refreshes the personal schedule once at launch to verify the term identifier and first Monday. Credentials are also used over HTTPS for schedules, classrooms, or assignments you request. Schedule and classroom requests go to jwglweixin.bupt.edu.cn; supported platforms may refresh today’s classrooms automatically. The maintainer cannot read credentials, and settings APIs never return a password."
                    )
                    privacySection(
                        title: "本地数据 / Local data",
                        body: "课表、空教室、校区、学期和功能开关缓存在设备上；收藏会把完整日程快照保存在本机，不上传或跨设备同步。受支持系统上的课程小组件只读取本地课表快照。“清除本地数据”会移除凭据、缓存、收藏、偏好和应用管理的提醒。\n\nSchedules, classroom results, campus, term, and preferences are cached locally. Favorites keep complete event snapshots on this device and are neither uploaded nor synchronized. Course widgets on supported systems read only a local schedule snapshot. “Clear local data” removes credentials, caches, favorites, preferences, and app-managed reminders."
                    )
                    privacySection(
                        title: "节假日数据 / Holiday data",
                        body: "应用可能通过 unpkg 获取固定版本 holiday-calendar 的中国法定节假日和调休数据；Android 在已有权限时也可能读取系统节假日日历。请求仅含 CN 与年份。iOS 只依据权威休息日数据显示“休”，不会把所有节日名称都当作休息日。\n\nThe app may retrieve pinned holiday-calendar data through unpkg; Android may also read the OS holiday calendar when permitted. Requests contain only CN and year. iOS marks rest days only from authoritative rest-day data, not from every festival name."
                    )
                    privacySection(
                        title: "天气、黄历、班车与公开活动 / Weather, almanac, shuttle, and public events",
                        body: "UAPI 按所选校区对应行政区提供天气与基础黄历，不读取 GPS；Timeless 可补充宜忌。where-to-study.cn 从北京邮电大学后勤部公开通知解析班车状态和时刻表。Contest DDL 提供竞赛、会议、期刊专题、夏令营、黑客松与预推免等公开活动；应用比较 GitHub Pages 主源与 https://where-to-study.cn/contest-ddl/data/competitions.json 镜像的生成时间，镜像更新时使用镜像，两者不可用时使用 https://where-to-study.cn/api/contest-events 备用接口。校内竞赛通知由服务器脚本从学校内部网站公开通知页提取整理。用户还可选择公开 HTTPS JSON 自定义日程源；这些公开查询均为不附带凭据或个人数据的 HTTPS GET 请求。各类别均有独立开关，所有显示数据仅供参考。\n\nUAPI provides district-level campus weather and base almanac data without GPS; Timeless may add advice. where-to-study.cn parses shuttle status and timetables from public BUPT Logistics Department notices. Contest DDL provides public events such as competitions, conferences, journal special issues, summer camps, hackathons, and pre-admission programs. The app compares generation times of the GitHub Pages primary feed and the mirror at https://where-to-study.cn/contest-ddl/data/competitions.json, using the mirror when newer; https://where-to-study.cn/api/contest-events remains a fallback if both are unavailable. School notices are extracted by a server-side script from public pages on the university’s internal website. Users may also select a public HTTPS JSON custom feed. These public-data queries are HTTPS GET requests without credentials or personal data. Each category has its own switch, and displayed data is for reference only."
                    )
                    privacySection(
                        title: "云课堂作业 / UCloud assignments",
                        body: "应用仅把密码通过 HTTPS 提交给 auth.bupt.edu.cn 完成统一认证，再用一次性票据换取内存令牌并从 apiucloud.bupt.edu.cn 读取作业。应用不读取浏览器 Cookie，不向 UCloud API 发送密码，也不把票据、Cookie、令牌或作业写入磁盘；结果最多在内存复用 10 分钟。\n\nThe password is submitted only to auth.bupt.edu.cn over HTTPS. A one-time ticket is exchanged for an in-memory token used with apiucloud.bupt.edu.cn. The app reads no browser cookies, sends no password to UCloud APIs, persists no ticket, cookie, token, or assignment, and reuses results in memory for at most ten minutes."
                    )
                    privacySection(
                        title: "QMplus 独立连接 / Independent QMplus connection",
                        body: "QMplus 与北邮教务账号独立。只有用户主动连接时，应用才在自己的官方网页窗口打开 QMplus，由用户直接完成 SSO／Microsoft MFA；应用没有 Microsoft 密码输入框，也不读取系统浏览器 Cookie。只读脚本仅返回有界课程与 Assignment／Quiz 业务快照，不返回密码、Cookie、sesskey、令牌或完整 HTML，不提交作业、开始测验或经过第三方 Worker／本项目服务器。业务快照只在当前进程内存中；iOS 17／macOS 14 及以上使用应用专属的可持久隔离 WebKit 存储，较旧的受支持系统使用非持久会话。部分失败会保留并标明上次资料；断开连接或清除本地数据会清除应用管理的会话与快照，更换北邮账号不会自动更换 QMplus 身份。官方 QMplus／Microsoft 可按自身政策处理登录信息和网络元数据。\n\nQMplus is independent of BUPT academic credentials. Only when you connect does the app open the official QMplus page in its own web view, where you complete SSO/Microsoft MFA directly. The app has no Microsoft password field and reads no system-browser cookies. Its read-only script returns only a bounded course and Assignment/Quiz business snapshot, not passwords, cookies, session keys, tokens, or full HTML; it never submits work, starts quizzes, or uses a third-party Worker or this project’s server. The snapshot stays in process memory. iOS 17/macOS 14 and later use an app-specific isolated persistent WebKit store; older supported systems use a nonpersistent session. Partial failures retain labelled prior data. Disconnecting or clearing local data removes the app-managed session and snapshot; changing BUPT credentials does not switch the QMplus identity. Official QMplus/Microsoft services may process sign-in information and network metadata under their own policies."
                    )
                    privacySection(
                        title: "系统日历、通知与小组件 / Calendar, notifications, and widgets",
                        body: "只有在你主动操作并授予权限后，应用才会把个人课程或已收藏日程写入系统日历，或安排本地课程通知；只管理带 Where To Study 标记的事件。每日课程摘要与课前提醒默认关闭，分别开启；课前提醒次数及提前分钟数仅保存在本机，不上传。收藏导入使用本机完整快照与稳定标记，重复导入会更新同一事件。课程小组件只在支持的平台提供。相关数据不上传给维护者。\n\nCalendar writes and local course notifications require your action and permission. Daily summaries and before-class reminders are separate, initially disabled choices. Before-class reminder counts and lead times stay on this device and are not uploaded. You can import personal courses or favorite-event snapshots; stable local markers update the same event on repeated imports, and only Where To Study-marked events are managed. Course widgets exist only on supported platforms. This data is not uploaded to the maintainer."
                    )
                    privacySection(
                        title: "不收集的数据与第三方元数据 / Data not collected and third-party metadata",
                        body: "本项目只运营用于整理公开班车与活动数据的固定接口，不提供用户账户、云端同步、广告、分析或行为跟踪服务，也不收集 GPS 位置、联系人、广告标识符、诊断或使用行为。北邮服务、unpkg、UAPI、Timeless、GitHub Pages、Where To Study 固定公开接口和用户选择的自定义日程服务器可能依据各自政策处理 IP 地址、请求时间等普通网络元数据。\n\nThe project operates only fixed endpoints that organize public shuttle and event data. It provides no user accounts, cloud synchronization, advertising, analytics, or behavioral tracking and does not collect GPS location, contacts, advertising identifiers, diagnostics, or usage behavior. BUPT services, unpkg, UAPI, Timeless, GitHub Pages, the fixed public Where To Study endpoints, and a user-selected custom schedule server may process ordinary network metadata such as IP address and request time under their own policies."
                    )
                    privacySection(
                        title: "独立教学云密码与课程删除 / Teaching cloud password and course deletion",
                        body: "你可为相同学号单独设置教学云平台密码，同样保存在系统 Keychain 中，仅用于教学云作业认证；未设置时使用教务密码。更换账号不会复用原账号的独立密码。课程删除记录按账号和学期保存在本机，可仅删除一次课程或本学期整门课程，刷新后仍生效，可在个人账户中恢复。它们会同步影响本地课表、空闲节次、课程小组件与提醒，不修改学校选课、作业或已导出的系统日历事件；清除本地数据时一并删除。\n\nYou can save a separate teaching cloud password for the same student ID in Keychain, used only for assignment authentication. Without it, the academic password is used. Changing accounts never reuses the previous account’s separate password. Course deletions are stored locally by account and semester, cover one occurrence or the entire course, survive refresh, and can be restored in Personal Account. They affect the local timetable, free periods, widgets, and reminders, without changing university enrollment, assignments, or exported calendar events. Clear local data also removes these records."
                    )
                    privacySection(
                        title: "保留与删除 / Retention and deletion",
                        body: "凭据与缓存保留在设备上，直到被替换、清除或随卸载移除；清除本地数据不会删除学校或第三方持有的记录。\n\nCredentials and caches stay on your device until replaced, cleared, or removed with the app. Clearing local data does not delete records held by BUPT or third parties."
                    )
                    privacySection(
                        title: "安全与联系 / Security and contact",
                        body: "请按 SECURITY.md 报告安全问题；隐私问题可在 GitHub 提交不含敏感信息的 Issue。请勿公开账号、密码、令牌、个人课表或其他敏感数据。\n\nFollow SECURITY.md for security reports. Privacy questions may be opened as non-sensitive GitHub issues. Never publish accounts, passwords, tokens, personal schedules, or other sensitive data."
                    )

                    Link(destination: Self.githubURL) {
                        Label("在 GitHub 查看完整声明 / Full policy on GitHub", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("action.open-privacy-github")
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(theme.configuration.preset == .default ? theme.background : theme.elevated)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .accessibilityIdentifier("action.dismiss-privacy-policy")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 520, idealHeight: 720)
        #endif
    }

    private func privacySection(title: String, body: String) -> some View {
        PrivacyPolicySection(title: title, content: body)
    }
}

// A separate body keeps text shaping and theme resolution lazy as well as the
// section's layout; creating the scroll container does not measure every block.
private struct PrivacyPolicySection: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.text)
            Text(content)
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// The stable screen owns the reference without observing its publications.
// Only the small presentation host observes changes, so neither the Settings
// body nor its widget previews need to update when the sheet opens/closes.
@MainActor
final class PrivacyPolicyPresentation: ObservableObject {
    @Published var isPresented = false
}

struct PrivacyPolicyPresentationHost: View {
    @ObservedObject var presentation: PrivacyPolicyPresentation

    var body: some View {
        Color.clear
            .sheet(isPresented: $presentation.isPresented) {
                PrivacyPolicyView().buttonStyle(.automatic)
            }
    }
}

struct PrivacyPolicyButton<LabelContent: View>: View {
    private let presentation: PrivacyPolicyPresentation
    private let beforePresent: @MainActor () -> Void
    private let label: LabelContent

    init(presentation: PrivacyPolicyPresentation, beforePresent: @escaping @MainActor () -> Void = {},
         @ViewBuilder label: () -> LabelContent) {
        self.presentation = presentation
        self.beforePresent = beforePresent
        self.label = label()
    }

    var body: some View {
        Button {
            guard !presentation.isPresented else { return }
            #if os(iOS) && DEBUG
            PrivacyPolicyPresentationTiming.begin()
            #endif
            AppHaptics.impact()
            beforePresent()
            presentation.isPresented = true
        } label: {
            label
        }
    }
}
