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
    if (this.model.resolvedLanguage() === AppLanguage.english) { return parts[parts.length - 1]; }
    if (this.model.resolvedLanguage() === AppLanguage.simplifiedChinese) { return parts[0]; }
    // 现有法律声明是经维护的中英双语正文；其它界面语言先完整呈现两份，
    // 不自动机翻法律含义或仅显示用户读不懂的中文半段。
    return value;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([AppTheme.text()])
        Text(this.model.text('返回'))
          .fontSize(16)
          .fontColor(AppTheme.text())
      }
      .width('100%')
      .padding({ left: 8, top: 12, bottom: 12 })
      .id('privacy_policy_close')
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
            Text(this.model.text('生效日期：') + '2026-10-05')
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
            '学号和密码保存在操作系统的受保护凭据存储中。保存有效凭据且开启自动学期检测后，启动时会自动刷新一次个人课表以校验学期号和第一周周一。你主动请求课表、空教室或作业时也会按对应用途通过 HTTPS 使用凭据。课表和空教室请求发送到 jwglweixin.bupt.edu.cn；平台允许时还可能自动刷新当天空教室。维护者无法读取凭据，设置接口也不会返回密码。\n\nCredentials stay in protected OS storage. With valid saved credentials and automatic term detection enabled, the app refreshes the personal schedule once at launch to verify the term identifier and first Monday. Credentials are also used over HTTPS for schedules, classrooms, or assignments you request. Schedule and classroom requests go to jwglweixin.bupt.edu.cn; supported platforms may refresh today\u2019s classrooms automatically. The maintainer cannot read credentials, and settings APIs never return a password.')
          this.privacySection('本地数据 / Local data',
            '课表、空教室、校区、学期和开关缓存在设备上；收藏会把完整日程快照保存在本机，不上传或跨设备同步。受支持系统的课程小组件只读取本地课表快照。“清除本地数据”会移除凭据、缓存、收藏、偏好和应用管理的提醒。\n\nSchedules, classroom results, campus, term, and preferences are cached locally. Favorites keep complete event snapshots on this device and are neither uploaded nor synchronized. Course widgets on supported systems read only a local snapshot. Clear local data removes credentials, caches, favorites, preferences, and app-managed reminders.')
          this.privacySection('成绩与考试 / Grades and exams',
            '成绩查询与课表刷新时同步的考试安排均使用已保存的教务凭据，直接通过 HTTPS 请求 jwglweixin.bupt.edu.cn。成绩仅在当前运行进程中按账号、学期与记录类型保留，不写入课表缓存；考试安排随原始课表缓存保存在本机，用于日历、小组件及已开启的每日摘要。账号切换或清除本地数据会移除相关状态。\n\nGrades and exam arrangements use your saved academic credentials over HTTPS directly with jwglweixin.bupt.edu.cn. Grades remain only in process memory, scoped to account, term, and record type. Exam arrangements are cached locally with the original schedule for the calendar, widgets, and enabled daily summaries. Switching accounts or clearing local data removes the related state.')
          this.privacySection('节假日数据 / Holiday data',
            '应用可能通过 unpkg 获取固定版本 holiday-calendar 数据；Android 在已有权限时也可能读取系统节假日日历。请求仅含 CN 与年份。iOS 只依据权威休息日数据显示“休”。\n\nThe app may retrieve pinned holiday-calendar data through unpkg; Android may read the OS holiday calendar when permitted. Requests contain only CN and year. iOS marks rest days only from authoritative rest-day data.')
          this.privacySection('天气、黄历与公开活动 / Weather, almanac, and public events',
            'UAPI 按所选校区对应行政区提供天气与基础黄历，不读取 GPS；Timeless 可补充宜忌。where-to-study.cn 从北京邮电大学后勤部公开通知解析班车状态和时刻表。公开活动优先读取 GitHub 上的 Contest DDL，where-to-study.cn 镜像仅在数据更新时间较新时使用，两者不可用时改用原有备用 API。校内竞赛通知由服务器脚本从学校内部网站公开通知页提取整理。用户还可选择公开 HTTPS JSON 自定义日程源；这些公开查询请求不附带个人数据。各类别均有独立开关，所有显示数据仅供参考。\n\nUAPI provides district-level campus weather and base almanac data without GPS; Timeless may add advice. where-to-study.cn parses shuttle status and timetables from public BUPT Logistics Department notices. Public events use Contest DDL on GitHub first; the where-to-study.cn mirror is selected only when its generated data is newer, and the existing API is a fallback if both fail. Campus notices are extracted by a server-side script from public pages on the university’s internal website. Users may also select a public HTTPS JSON custom feed. These public-data requests contain no personal data. Each category has its own switch, and displayed data is for reference only.')
          this.privacySection('云课堂作业 / UCloud assignments',
            '密码仅通过 HTTPS 提交给 auth.bupt.edu.cn，一次性票据换取内存令牌后从 apiucloud.bupt.edu.cn 读取课程与作业。应用不读取浏览器 Cookie，不向 UCloud API 发送密码；票据、Cookie 和令牌只在内存。经有界字段校验的课程、作业及获取时间可保存在应用私有缓存，先显示缓存，再由同一请求 owner 静默刷新；失败保留上次成功资料，时间不会冒充当前刷新。缓存只用原 ASSET 凭据内随机、非秘密标识绑定，不写账号、密码或其摘要，也不写 HTML；真实凭据编辑或清除本地数据会先失效旧作用域并按序删除缓存，完全相同资料重存不旋转标识。安全标识迁移或缓存写入失败不会宣称重启缓存已更新。\n\nThe password is submitted only to auth.bupt.edu.cn over HTTPS; an in-memory ticket/token permits course and assignment reads from apiucloud.bupt.edu.cn. Browser cookies are not read, and tickets, cookies and tokens remain in memory. Bounded, validated course/assignment DTOs and their fetch times may be cached in private app storage: cached data appears first, then the same request owner refreshes silently. Failure preserves last-good data and its original timestamp. The cache uses a random non-secret binding inside the original ASSET credential record, not an account, password, credential digest or HTML. Credential edits and local clearing invalidate the old scope and serially remove its cache; identical resaves preserve it. A scope migration or write failure is not reported as updated restart storage.')
          this.privacySection('QMplus 独立连接 / Independent QMplus connection',
            'QMplus 与北邮教务凭据独立。API 24 下，本应用唯一的普通 ArkWeb 持久数据区专供 QMplus；这不是命名 profile API，与系统浏览器及其它应用隔离，今后其它内嵌网页必须使用无痕模式。Cookie 由引擎管理，不导出到业务接口或普通 JSON；仅引擎及官方服务允许的 Cookie 可跨重启保留，平板、PC／二合一的会话 Cookie 可能不持久，官方可再次要求登录或 MFA。首次保存时默认预选自动填写，并保留你明确关闭的选择；开关预选本身不保存凭据或建立授权。独立登录资料仅在主动保存时进入 ASSET，并按你的选择建立匹配授权；非敏感偏好保存匹配授权标识与随机业务缓存作用域。经核验且与保存账号精确匹配的普通 SSO 步骤可在应用内静默完成，账号选择、用户名、密码及普通“保持登录”（KMSI）各最多执行一次。验证码和 MFA 由你完成；未匹配账号、未知页面、风险确认和新协议会暂停自动化，等待你选择“手动继续”，不自动点击或重放验证 POST。只读脚本仅返回经校验的有界课程与 Assignment／Quiz DTO，不返回密码、Cookie、令牌、sesskey、身份字段或 HTML，不提交作业、启动测验或经过本项目服务器。业务 DTO 及原获取时间可在应用私有缓存跨重启保留；部分失败保留上次成功资料。静默刷新先尝试有效网页会话，明确授权时才执行上述登录步骤；只有确认的验证码或 MFA 且应用处于系统前台时，才自动显示官方窗口，完成后继续同步。进入系统后台会暂停登录自动化，不抢占焦点或弹窗；未知或错误页面保留缓存并提供“手动继续”。关闭功能保留资料、网页会话和缓存，同一已授权资料重存不清理。换 QM 身份、退出或清数据先持久保存清理标记并旋转业务作用域；旧网页区已使用时，本进程禁止重新挂载，真正重启后以空白页完成 Cookie 删除／保存确认及存储用量检查，成功后才访问官方网页。保存新 ASSET 不等于旧网页会话已清除，失败保持阻断并提示重启／重试。更换北邮账号不自动更换 QMplus 身份。\n\nQMplus and BUPT credentials remain separate. On API 24, this app’s sole normal ArkWeb data area is reserved for QMplus, not a named profile API; it is isolated from system browsers and other apps, and future unrelated embedded Web must be incognito. Engine-managed cookies never enter business APIs or ordinary JSON. Only engine/server-permitted cookies survive restart; tablet, PC and 2-in-1 session cookies may not, and official login/MFA can be required again. Autofill is initially preselected for the first save and preserves an explicit Off choice. Preselection alone neither stores credentials nor grants authorization. Explicitly saved login uses ASSET and matching authorization is established according to your choice; ordinary metadata holds that authorization and a random business-cache scope. Verified ordinary SSO steps that exactly match the saved account can complete silently within the app, with account selection, username, password and ordinary Keep me signed in (KMSI) attempted at most once each. You complete CAPTCHA and MFA. Unmatched accounts, unknown pages, risk confirmations and new terms pause automation until you choose Continue manually, without automatically clicking them or replaying verification POSTs. Read-only scripts return bounded validated course and Assignment/Quiz DTOs, never credentials, cookies, tokens, sesskey, identity fields or HTML; they neither submit work, start quizzes nor use project servers. Business DTOs and original fetch times may persist privately; partial failure retains last-good data. Silent refresh tries a valid web session first and performs the login steps above only with explicit authorization. Only a confirmed CAPTCHA or MFA challenge automatically reveals the official window while the app is in the OS foreground; synchronization continues after completion. Moving to the OS background pauses login automation without taking focus or opening a window. Unknown or error pages preserve the cache and offer Continue manually. Feature Off and identical authorized resaves preserve credentials, web data and cache. QM identity changes, logout and clearing first persist a clear-pending fence and rotate the business binding. A used web area cannot remount in the same process; after a real restart, a blank page must acknowledge cookie deletion/save and verify storage usage before official navigation. Saving a new ASSET record does not prove old web data was cleared. Failures remain blocked with restart/retry guidance. Changing BUPT identity does not switch QMplus identity.')
          this.privacySection('系统密码管理器 / System password manager',
            'HarmonyOS 或您使用的系统密码管理器可能依据您在系统中的单独授权，为官方网页提供填充建议。本应用的 QMplus 自动填写开关只控制是否使用本应用独立保存的登录资料，不关闭系统自己的密码管理功能；本应用无法读取其密码库，也不会清除其中的资料。\n\nHarmonyOS or a system password manager you use may offer autofill on official pages under your separate system authorization. The QMplus autofill switch in this app controls only the separately saved login managed by this app; it does not disable system password management. The app cannot read or clear the system password vault.')
          this.privacySection('教学云平台密码与课程删除 / Teaching Cloud password and course deletion',
            '可选的教学云平台独立密码与教务密码一起受 HarmonyOS ASSET 安全存储保护，仅用于作业 DDL。未设置时使用教务密码；清除独立密码后恢复此方式。课程删除记录仅在本机按账号与学期隔离保存，支持删除单次或本学期整门课程，并可恢复；刷新课表会继续应用记录。删除不会更改学校数据、作业 DDL 或已导出的系统日历。清除本地数据也会清除独立密码和课程删除记录。\n\nThe optional Teaching Cloud password is protected with your academic password in HarmonyOS ASSET and used only for assignment deadlines. Without an override, the academic password is used. Course deletion records remain on this device, scoped to account and semester; occurrences or whole courses can be removed and restored, and removals survive refresh. School records, assignment deadlines, and previously exported calendar events are unchanged. Clear local data also removes the separate password and course deletion records.')
          this.privacySection('系统日历、通知与小组件 / Calendar, notifications, and widgets',
            '日历写入和本地课程通知需要你的操作与权限；应用只管理带 Where To Study 标记的事件。课程小组件只在支持的平台提供，相关数据不上传。\n\nCalendar writes and local course notifications require your action and permission, and only marked events are managed. Widgets exist only on supported platforms. This data is not uploaded.')
          this.privacySection('不收集的数据与第三方元数据 / Data not collected and third-party metadata',
            '应用不含广告、分析或跟踪 SDK，也不收集 GPS、联系人、广告标识符、诊断或使用行为。where-to-study.cn 与其它第三方公开服务可能按各自政策处理普通网络请求的 IP 和请求时间。\n\nThe app contains no advertising, analytics, or tracking SDKs and does not collect GPS, contacts, advertising identifiers, diagnostics, or usage behavior. where-to-study.cn and other public-data services may process ordinary IP and request-time metadata under their own policies.')
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
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .id('privacy_policy_page')
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
