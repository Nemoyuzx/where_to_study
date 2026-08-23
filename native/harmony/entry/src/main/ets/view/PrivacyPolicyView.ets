// 与 iOS 端 PrivacyPolicyView.swift 对应的应用内隐私声明页。
import { AppTheme } from '../common/AppTheme';
import { AppContext } from '../store/AppContext';
import { AppModel } from '../model/AppModel';
import { AppLanguage } from '../common/AppLocalization';

@ComponentV2
export struct PrivacyPolicyView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Event onClose: () => void = () => {
  };

  private static readonly githubURL: string =
    'https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md';

  private policyText(value: string): string {
    const separator: string = value.includes('\n\n') ? '\n\n' : ' / ';
    const parts: string[] = value.split(separator);
    if (parts.length < 2) {
      return this.model.text(value);
    }
    return this.model.resolvedLanguage() === AppLanguage.english ? parts[parts.length - 1] : parts[0];
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([AppTheme.text()])
        Text(this.model.resolvedLanguage() === AppLanguage.english ? 'Back' : '返回')
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
            Text(this.policyText('隐私声明 / Privacy Policy'))
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.text())
            Text(this.model.resolvedLanguage() === AppLanguage.english ?
              'Effective date: 2026-08-23' : '生效日期：2026-08-23')
              .fontSize(14)
              .fontColor(AppTheme.secondaryText())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Text(this.policyText('Where To Study 是用于查看北京邮电大学个人课表、空教室及相关学习信息的独立非官方客户端，不由学校运营，也不代表学校官方立场。\n\nWhere To Study is an independent, unofficial client for BUPT schedules, empty classrooms, and related study information. It is not operated by or affiliated with BUPT.'))
            .fontSize(15)
            .fontColor(AppTheme.text())
            .width('100%')

          this.privacySection('账户与教务请求 / Account and academic requests',
            '学号和密码保存在操作系统的受保护凭据存储中，仅在你请求课表、空教室或作业时按对应用途通过 HTTPS 使用。维护者无法读取凭据，设置接口也不会返回密码。\n\nCredentials stay in protected OS storage and are used over HTTPS only for requested schedules, classrooms, or assignments. The maintainer cannot read credentials, and settings APIs never return a password.')
          this.privacySection('本地数据 / Local data',
            '课表、空教室、校区、学期和开关缓存在设备上；受支持系统的课程小组件只读取本地课表快照。“清除本地数据”会移除凭据、缓存、偏好和应用管理的提醒。\n\nSchedules, classroom results, campus, term, and preferences are cached locally. Course widgets on supported systems read only a local snapshot. Clear local data removes credentials, caches, preferences, and app-managed reminders.')
          this.privacySection('节假日数据 / Holiday data',
            '应用可能通过 unpkg 获取固定版本 holiday-calendar 数据；Android 在已有权限时也可能读取系统节假日日历。请求仅含 CN 与年份。iOS 只依据权威休息日数据显示“休”。\n\nThe app may retrieve pinned holiday-calendar data through unpkg; Android may read the OS holiday calendar when permitted. Requests contain only CN and year. iOS marks rest days only from authoritative rest-day data.')
          this.privacySection('天气、黄历与公开活动 / Weather, almanac, and public events',
            'UAPI 按校区行政区提供天气与基础黄历，不读取 GPS；Timeless 可补充宜忌。Contest DDL 提供竞赛、夏令营和黑客松；校内竞赛通知由服务器脚本从学校内部网站公开通知页提取整理。各类别有独立开关。固定 HTTP API 仅接收无凭据 GET，拒绝重定向且不含个人数据。所有显示数据仅供参考。\n\nUAPI provides district-level weather and base almanac data without GPS; Timeless may add advice. Contest DDL provides public events. School notices are extracted by a server-side script from public pages on the university’s internal website. Each category has its own switch. Fixed HTTP APIs receive credential-free GET requests with no personal data and reject redirects. Displayed data is for reference only.')
          this.privacySection('云课堂作业 / UCloud assignments',
            '密码仅通过 HTTPS 提交给 auth.bupt.edu.cn，一次性票据换取内存令牌后从 apiucloud.bupt.edu.cn 读取作业。应用不读取浏览器 Cookie，不向 UCloud API 发送密码，也不把票据、Cookie、令牌或作业写入磁盘；结果最多在内存复用 10 分钟。\n\nThe password is submitted only to auth.bupt.edu.cn over HTTPS. An in-memory token is used with apiucloud.bupt.edu.cn. No browser cookie, ticket, token, or assignment is persisted, and results are reused in memory for at most ten minutes.')
          this.privacySection('系统日历、通知与小组件 / Calendar, notifications, and widgets',
            '日历写入和本地课程通知需要你的操作与权限；应用只管理带 Where To Study 标记的事件。课程小组件只在支持的平台提供，相关数据不上传。\n\nCalendar writes and local course notifications require your action and permission, and only marked events are managed. Widgets exist only on supported platforms. This data is not uploaded.')
          this.privacySection('不收集的数据与第三方元数据 / Data not collected and third-party metadata',
            '项目不运营应用后端，不含广告、分析或跟踪 SDK，也不收集 GPS、联系人、广告标识符、诊断或使用行为。第三方可能按各自政策处理 IP 和请求时间。\n\nThe project operates no app backend and collects no GPS, contacts, advertising identifiers, diagnostics, or usage behavior. Third parties may process ordinary IP and request-time metadata.')
          this.privacySection('保留与删除 / Retention and deletion',
            '凭据与缓存保留在设备上，直到被替换、清除或随卸载移除；清除本地数据不会删除学校或第三方持有的记录。\n\nCredentials and caches stay on your device until replaced, cleared, or removed with the app. Clearing local data does not delete third-party records.')
          this.privacySection('安全与联系 / Security and contact',
            '请按 SECURITY.md 报告安全问题；隐私问题可在 GitHub 提交不含敏感信息的 Issue。请勿公开账号、密码、令牌或个人课表。\n\nFollow SECURITY.md for security reports. Open only non-sensitive privacy issues on GitHub, and never publish credentials, tokens, or personal schedules.')

          Button() {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.arrow_up_right'))
                .fontSize(16)
                .fontColor([AppTheme.text()])
              Text(this.policyText('在 GitHub 查看完整声明 / Full policy on GitHub'))
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
      Text(this.policyText(title))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      Text(this.policyText(body))
        .fontSize(14)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(20)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
