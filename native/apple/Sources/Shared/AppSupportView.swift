import SwiftUI

struct AppSupportView: View {
    @Environment(\.dismiss) private var dismiss

    private static let emailAddress = "2099905168@qq.com"
    private static let emailURL = URL(string: "mailto:2099905168@qq.com")!
    private static let issuesURL = URL(string: "https://github.com/Nemoyuzx/where_to_study/issues")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WHERE TO STUDY")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("帮助与支持")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.text)
                            .accessibilityIdentifier("screen.app-support")
                        Text("此页面的联系方式和常见问题可离线查看。")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("联系维护者")
                            .font(.headline)
                        Text("项目维护者：Nemoyuzx")
                            .font(.callout)
                        Text(verbatim: Self.emailAddress)
                            .font(.callout)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("support.email-address")
                        Link(destination: Self.emailURL) {
                            Label("通过电子邮件联系", systemImage: "envelope")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("action.contact-support-email")
                        Text("如未配置邮件应用，可复制以上地址到你使用的邮箱。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Link(destination: Self.issuesURL) {
                            Label("在 GitHub 反馈问题", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("action.open-support-github")
                        Text("反馈时请说明应用版本、系统版本、操作步骤和错误提示。请勿发送密码、令牌或包含个人信息的课表截图。")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(AppTheme.text)

                    Text("常见问题")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.text)

                    supportSection(
                        title: "个人课表获取失败怎么办？",
                        body: "请在设置中核对学号、教务密码和学期设置，再点击“获取/刷新个人课表”。确认网络可用；如果学校教务系统暂不可用，请稍后重试。"
                    )
                    supportSection(
                        title: "空教室查询失败或结果为空怎么办？",
                        body: "空教室仅查询当天数据。请确认所选校区、教学楼和节次；使用个人课表参与筛选时，请先刷新课表。教务系统维护或网络异常时，请稍后重试。"
                    )
                    supportSection(
                        title: "没有教务账号，可以体验吗？",
                        body: "可以。在“设置 → 关于本应用”点击“浏览内置示例数据”，无需学号或密码即可查看示例课表与空教室。示例模式不会连接教务服务，也不会读写真实用户数据。"
                    )
                    supportSection(
                        title: "如何清除本地数据？",
                        body: "在“设置 → 本地数据”点击“清除本地数据”并确认，会删除本机保存的凭据、课表、缓存与收藏，并恢复本地设置。此操作无法撤销，也不会删除学校或其他服务持有的数据。"
                    )
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("action.dismiss-app-support")
                }
            }
        }
        .tint(AppTheme.primary)
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 520, idealHeight: 720)
        #endif
    }

    private func supportSection(title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
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
