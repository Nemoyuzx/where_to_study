// 与 iOS 端 PrivacyPolicyView.swift 对应的应用内隐私声明页。
import { AppTheme } from '../common/AppTheme';
import { AppContext } from '../store/AppContext';

@ComponentV2
export struct PrivacyPolicyView {
  @Event onClose: () => void = () => {
  };

  private static readonly githubURL: string =
    'https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md';

  build() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([AppTheme.text()])
        Text('返回')
          .fontSize(16)
          .fontColor(AppTheme.text())
      }
      .width('100%')
      .padding({ left: 8, top: 12, bottom: 12 })
      .onClick(() => {
        this.onClose();
      })

      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 6 }) {
            Text('WHERE TO STUDY')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.secondaryText())
            Text('隐私声明')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.text())
            Text('生效日期：2026 年 8 月 9 日')
              .fontSize(14)
              .fontColor(AppTheme.secondaryText())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Text('Where To Study 是用于查看北邮个人课表和空教室的独立非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。')
            .fontSize(15)
            .fontColor(AppTheme.text())
            .width('100%')

          this.privacySection('账户与教务请求',
            '你输入的学号和密码保存在操作系统的受保护凭据存储中。应用在你手动获取课表或空教室时，会通过 HTTPS 将凭据发送到北邮教务服务 jwglweixin.bupt.edu.cn。保存有效凭据后，应用还可能在启动、回到前台，或平台允许的每日 07:00 左右后台任务中自动刷新当天空教室。项目维护者无法读取这些凭据。')
          this.privacySection('本地数据',
            '个人课表、空教室结果、校区和学期等设置会缓存在你的设备上，以减少重复请求。你可以在设置中使用“清除本地数据”删除应用保存的凭据、课表、空教室缓存、节假日缓存和提醒任务。')
          this.privacySection('节假日数据',
            '应用在启动、切换日历年份或缓存需要更新时，可能通过 unpkg 自动获取 holiday-calendar 数据集中的中国法定节假日和调休信息。请求只包含 CN 地区和年份，不包含你的凭据、课表或空教室数据。')
          this.privacySection('系统日历与课程提醒',
            '只有在你主动操作并授予系统权限后，应用才会向系统日历写入课程或在本地安排课程摘要通知。应用只管理带有 Where To Study 标记的日历事件，相关数据不会上传给项目维护者。')
          this.privacySection('不收集的数据',
            '本项目不运营应用后端，不包含广告、分析或行为跟踪 SDK，也不收集位置、联系人、广告标识符或使用行为。北邮教务服务和节假日数据的 CDN 可能依据各自政策处理 IP 地址、请求时间等普通网络元数据。')
          this.privacySection('保留与删除',
            '凭据和缓存会保留在你的设备上，直到被替换、在设置中清除或随应用卸载移除。清除本地数据不会删除北邮教务服务持有的记录。')
          this.privacySection('安全与联系',
            '隐私问题可以在 GitHub 提交不含敏感信息的讨论或 Issue。请勿在公开内容中提供账号、密码、令牌、个人课表或其他敏感数据。')

          Button() {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.arrow_up_right'))
                .fontSize(16)
                .fontColor([AppTheme.text()])
              Text('在 GitHub 查看项目与完整声明')
                .fontSize(14)
                .fontColor(AppTheme.text())
            }
          }
          .type(ButtonType.Normal)
          .borderRadius(6)
          .border({ width: 1, color: AppTheme.border() })
          .backgroundColor(AppTheme.background())
          .width('100%')
          .height(36)
          .onClick(() => {
            try {
              AppContext.get().openLink(PrivacyPolicyView.githubURL);
            } catch (e) {
              // 打开浏览器失败时忽略。
            }
          })
        }
        .padding(20)
        .width('100%')
        .constraintSize({ maxWidth: 720 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(AppTheme.background())
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
  }

  @Builder
  privacySection(title: string, body: string) {
    Column({ space: 8 }) {
      Divider()
        .color(AppTheme.border())
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      Text(body)
        .fontSize(14)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(20)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
