import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private static let githubURL = URL(
        string: "https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md"
    )!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WHERE TO STUDY")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("隐私声明 / Privacy Policy")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.text)
                            .accessibilityIdentifier("screen.privacy-policy")
                        Text("生效日期 / Effective date: 2026-08-24")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Text("Where To Study 是用于查看北京邮电大学个人课表、空教室及相关学习信息的独立非官方客户端，不由学校运营，也不代表学校官方立场。\n\nWhere To Study is an independent, unofficial client for BUPT schedules, empty classrooms, and related study information. It is not operated by or affiliated with BUPT.")
                        .foregroundStyle(AppTheme.text)

                    privacySection(
                        title: "账户与教务请求 / Account and academic requests",
                        body: "学号和密码保存在操作系统的受保护凭据存储中，仅在你请求课表、空教室或作业时按对应用途通过 HTTPS 使用。课表和空教室请求发送到 jwglweixin.bupt.edu.cn；平台允许时还可能自动刷新当天空教室。维护者无法读取凭据，设置接口也不会返回密码。\n\nCredentials stay in protected OS storage and are used over HTTPS only for requested schedules, classrooms, or assignments. Schedule and classroom requests go to jwglweixin.bupt.edu.cn; supported platforms may refresh today’s classrooms automatically. The maintainer cannot read credentials, and settings APIs never return a password."
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
                        title: "天气、黄历与公开活动 / Weather, almanac, and public events",
                        body: "UAPI 按所选校区对应行政区提供天气与基础黄历，不读取 GPS；Timeless 可补充宜忌。Contest DDL 提供竞赛、夏令营和黑客松，校内竞赛通知由服务器脚本从学校内部网站公开通知页提取整理。用户还可选择公开 HTTPS JSON 自定义日程源；请求不附带个人数据，客户端拒绝含凭据、本机/私网字面量、重定向或超大响应的地址。各类别均有独立开关，所有显示数据仅供参考。\n\nUAPI provides district-level campus weather and base almanac data without GPS; Timeless may add advice. Contest DDL provides competitions, summer camps, and hackathons. School notices are extracted by a server-side script from public pages on the university’s internal website. Users may also select a public HTTPS JSON custom feed. Requests contain no personal data, and credential-bearing, local/private literal, redirecting, or oversized endpoints are rejected. Each category has its own switch, and displayed data is for reference only."
                    )
                    privacySection(
                        title: "云课堂作业 / UCloud assignments",
                        body: "应用仅把密码通过 HTTPS 提交给 auth.bupt.edu.cn 完成统一认证，再用一次性票据换取内存令牌并从 apiucloud.bupt.edu.cn 读取作业。应用不读取浏览器 Cookie，不向 UCloud API 发送密码，也不把票据、Cookie、令牌或作业写入磁盘；结果最多在内存复用 10 分钟。\n\nThe password is submitted only to auth.bupt.edu.cn over HTTPS. A one-time ticket is exchanged for an in-memory token used with apiucloud.bupt.edu.cn. The app reads no browser cookies, sends no password to UCloud APIs, persists no ticket, cookie, token, or assignment, and reuses results in memory for at most ten minutes."
                    )
                    privacySection(
                        title: "系统日历、通知与小组件 / Calendar, notifications, and widgets",
                        body: "只有在你主动操作并授予权限后，应用才会写入系统日历或安排本地课程通知；只管理带 Where To Study 标记的事件。课程小组件只在支持的平台提供。相关数据不上传给维护者。\n\nCalendar writes and local course notifications require your action and permission, and only marked events are managed. Course widgets exist only on supported platforms. This data is not uploaded to the maintainer."
                    )
                    privacySection(
                        title: "不收集的数据与第三方元数据 / Data not collected and third-party metadata",
                        body: "项目不运营应用后端，不含广告、分析或行为跟踪 SDK，也不收集 GPS、联系人、广告标识符、诊断或使用行为。所连接的第三方服务可能按各自政策处理 IP 和请求时间等普通网络元数据。\n\nThe project operates no app backend and collects no GPS, contacts, advertising identifiers, diagnostics, or usage behavior. Connected third parties may process ordinary network metadata such as IP address and request time under their own policies."
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
            .background(AppTheme.background)
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
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text(body)
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
