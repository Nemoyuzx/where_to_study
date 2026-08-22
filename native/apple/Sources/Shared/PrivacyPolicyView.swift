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
                        Text("隐私声明")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.text)
                            .accessibilityIdentifier("screen.privacy-policy")
                        Text("生效日期：2026 年 8 月 22 日")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Text("Where To Study 是用于查看北邮个人课表和空教室的独立非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。")
                        .foregroundStyle(AppTheme.text)

                    privacySection(
                        title: "账户与教务请求",
                        body: "你输入的学号和密码保存在操作系统的受保护凭据存储中。应用在你手动获取课表或空教室时，会通过 HTTPS 将凭据发送到北邮教务服务 jwglweixin.bupt.edu.cn。保存有效凭据后，应用还可能在启动、回到前台，或平台允许的每日 07:00 左右后台任务中自动刷新当天空教室。项目维护者无法读取这些凭据。"
                    )
                    privacySection(
                        title: "本地数据",
                        body: "个人课表、空教室结果、校区和学期等设置会缓存在你的设备上，以减少重复请求。你可以在设置中使用“清除本地数据”删除应用保存的凭据、课表、空教室缓存、节假日缓存和提醒任务。"
                    )
                    privacySection(
                        title: "节假日数据",
                        body: "应用在启动、切换日历年份或缓存需要更新时，可能通过 unpkg 自动获取 holiday-calendar 数据集中的中国法定节假日和调休信息。请求只包含 CN 地区和年份，不包含你的凭据、课表或空教室数据。"
                    )
                    privacySection(
                        title: "天气、黄历与公开 DDL",
                        body: "应用会通过 UAPI 获取所选校区所在行政区的今日、明日天气和所选日期的基础黄历，并可能通过 Timeless API 补充“宜/忌”。启用对应类别时，应用会从 Contest DDL 的 GitHub Pages 主源下载公开竞赛、夏令营与黑客松数据并在本地按日期筛选；主源不可用时可能尝试固定的 HTTP 备用 API。备用请求只向指定 IP 发送不含凭据、Cookie、token、课表、教室或作业数据的 GET，并拒绝重定向。所有相关功能均可在设置中关闭。"
                    )
                    privacySection(
                        title: "云课堂作业",
                        body: "查看日期详情中的课程作业时，应用会从系统安全存储临时读取已保存的教务账号和密码，仅通过 HTTPS 提交给 auth.bupt.edu.cn 完成统一认证，再用一次性票据换取内存中的云课堂令牌并读取课程作业。应用不会读取浏览器 Cookie 或 token，不会把密码发送给 ucloud.bupt.edu.cn 或 apiucloud.bupt.edu.cn，也不会把认证票据、Cookie、令牌或作业写入磁盘；用于跨日期查询的全量结果最多复用 10 分钟，已显示结果只保留在当前进程内，并在切换账号或清除本地数据时失效。"
                    )
                    privacySection(
                        title: "系统日历与课程提醒",
                        body: "只有在你主动操作并授予系统权限后，应用才会向系统日历写入课程或在本地安排课程摘要通知。应用只管理带有 Where To Study 标记的日历事件，相关数据不会上传给项目维护者。"
                    )
                    privacySection(
                        title: "不收集的数据",
                        body: "本项目不运营应用后端，不包含广告、分析或行为跟踪 SDK，也不收集位置、联系人、广告标识符或使用行为。北邮教务服务、节假日数据 CDN、UAPI、Timeless、GitHub Pages 与可选 DDL 备用服务可能依据各自政策处理 IP 地址、请求时间等普通网络元数据。"
                    )
                    privacySection(
                        title: "保留与删除",
                        body: "凭据和缓存会保留在你的设备上，直到被替换、在设置中清除或随应用卸载移除。清除本地数据不会删除北邮教务服务持有的记录。"
                    )
                    privacySection(
                        title: "安全与联系",
                        body: "隐私问题可以在 GitHub 提交不含敏感信息的讨论或 Issue。请勿在公开内容中提供账号、密码、令牌、个人课表或其他敏感数据。"
                    )

                    Link(destination: Self.githubURL) {
                        Label("在 GitHub 查看项目与完整声明", systemImage: "arrow.up.right.square")
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
