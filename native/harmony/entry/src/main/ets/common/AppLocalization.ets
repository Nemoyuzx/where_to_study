// 应用内语言偏好。API 返回的课程名、竞赛名、黄历内容等不经过本地化；
// 只有代码内已知的静态 UI 与状态文案会进入此映射。
import { i18n } from '@kit.LocalizationKit';
import { AppLocalizationCatalog } from './AppLocalizationCatalog';

export enum AppLanguage {
  system = 'system',
  simplifiedChinese = 'zh-Hans',
  traditionalChinese = 'zh-Hant',
  english = 'en',
  japanese = 'ja',
  spanish = 'es',
  portuguese = 'pt',
  arabic = 'ar',
  russian = 'ru',
  turkish = 'tr',
  thai = 'th',
  malay = 'ms',
  vietnamese = 'vi',
  indonesian = 'id'
}

export class AppLanguageInfo {
  static readonly all: AppLanguage[] = [
    AppLanguage.system, AppLanguage.simplifiedChinese, AppLanguage.traditionalChinese,
    AppLanguage.english, AppLanguage.japanese, AppLanguage.spanish,
    AppLanguage.portuguese, AppLanguage.arabic, AppLanguage.russian,
    AppLanguage.turkish, AppLanguage.thai, AppLanguage.malay,
    AppLanguage.vietnamese, AppLanguage.indonesian
  ];

  static normalize(value: string | null): AppLanguage {
    for (const supported of AppLanguageInfo.all) {
      if (value === supported) { return supported; }
    }
    return AppLanguage.system;
  }

  static systemLanguage(): string {
    try {
      return i18n.System.getSystemLanguage();
    } catch (e) {
      return 'zh-Hans';
    }
  }

  static resolved(setting: AppLanguage, systemLanguage: string): AppLanguage {
    if (setting !== AppLanguage.system) {
      return setting;
    }
    const parts: string[] = systemLanguage.replace(/_/g, '-').toLowerCase().split('-');
    const primary: string = parts[0] ?? '';
    if (primary === 'zh') {
      if (parts.includes('hant')) { return AppLanguage.traditionalChinese; }
      if (parts.includes('hans')) { return AppLanguage.simplifiedChinese; }
      return parts.includes('tw') || parts.includes('hk') || parts.includes('mo') ?
        AppLanguage.traditionalChinese : AppLanguage.simplifiedChinese;
    }
    for (const supported of AppLanguageInfo.all) {
      if (supported === primary && supported !== AppLanguage.system) { return supported; }
    }
    return AppLanguage.english;
  }

  static label(setting: AppLanguage, displayLanguage: AppLanguage): string {
    if (setting === AppLanguage.system) {
      if (displayLanguage === AppLanguage.traditionalChinese) { return '跟隨系統'; }
      if (displayLanguage === AppLanguage.english) { return 'System'; }
      if (displayLanguage === AppLanguage.japanese) { return 'システムに従う'; }
      if (displayLanguage === AppLanguage.spanish) { return 'Seguir el sistema'; }
      if (displayLanguage === AppLanguage.portuguese) { return 'Seguir o sistema'; }
      if (displayLanguage === AppLanguage.arabic) { return 'حسب النظام'; }
      if (displayLanguage === AppLanguage.russian) { return 'Как в системе'; }
      if (displayLanguage === AppLanguage.turkish) { return 'Sistemi takip et'; }
      if (displayLanguage === AppLanguage.thai) { return 'ตามระบบ'; }
      if (displayLanguage === AppLanguage.malay) { return 'Ikut sistem'; }
      if (displayLanguage === AppLanguage.vietnamese) { return 'Theo hệ thống'; }
      if (displayLanguage === AppLanguage.indonesian) { return 'Ikuti sistem'; }
      return '跟随系统';
    }
    if (setting === AppLanguage.simplifiedChinese) { return '简体中文'; }
    if (setting === AppLanguage.traditionalChinese) { return '繁體中文'; }
    if (setting === AppLanguage.english) { return 'English'; }
    if (setting === AppLanguage.japanese) { return '日本語'; }
    if (setting === AppLanguage.spanish) { return 'Español'; }
    if (setting === AppLanguage.portuguese) { return 'Português'; }
    if (setting === AppLanguage.arabic) { return 'العربية'; }
    if (setting === AppLanguage.russian) { return 'Русский'; }
    if (setting === AppLanguage.turkish) { return 'Türkçe'; }
    if (setting === AppLanguage.thai) { return 'ไทย'; }
    if (setting === AppLanguage.malay) { return 'Bahasa Melayu'; }
    if (setting === AppLanguage.vietnamese) { return 'Tiếng Việt'; }
    return 'Bahasa Indonesia';
  }

  static isRightToLeft(language: AppLanguage): boolean {
    return language === AppLanguage.arabic;
  }
}

export class LocalizationValues {
  readonly key: string;
  readonly value: string;
  readonly secondKey: string;
  readonly secondValue: string;
  readonly thirdKey: string;
  readonly thirdValue: string;

  constructor(key: string, value: string, secondKey: string = '', secondValue: string = '',
    thirdKey: string = '', thirdValue: string = '') {
    this.key = key;
    this.value = value;
    this.secondKey = secondKey;
    this.secondValue = secondValue;
    this.thirdKey = thirdKey;
    this.thirdValue = thirdValue;
  }

  apply(template: string): string {
    let result: string = template.replaceAll('{' + this.key + '}', this.value);
    if (this.secondKey.length > 0) { result = result.replaceAll('{' + this.secondKey + '}', this.secondValue); }
    if (this.thirdKey.length > 0) { result = result.replaceAll('{' + this.thirdKey + '}', this.thirdValue); }
    return result;
  }
}

export class AppLocalization {
  private static readonly english: Record<string, string> = {
    '启用 QMplus': 'Enable QMplus',
    '仅适用国院': 'International School only',
    '无法保存本地偏好。': 'Unable to save local preferences.',
    '今日课程': 'Today\'s Courses',
    '今天可以自由安排': 'No classes today',
    '课程进行中': 'In progress',
    '进行中': 'In progress',
    '还有待上课程': 'Upcoming class',
    '下一节': 'Next',
    '考试时间待定': 'Exam time pending',
    '今日课程已结束': 'Classes finished for today',
    '今日无课': 'No classes today',
    '打开应用获取个人课表': 'Open the app to fetch your schedule',
    '进行中 · {time} 下课': 'In progress · Ends {time}',
    '下一节 · {time}': 'Next · {time}',
    '今日另有 {count} 门课程': '{count} more courses today',
    '课程将在 {minutes} 分钟后开始': 'Class starts in {minutes} min',
    '考试将在 {minutes} 分钟后开始': 'Exam starts in {minutes} min',
    '今日课程 · {count} 门': 'Today\'s Courses · {count}',
    '今日安排 · {count} 项': 'Today\'s Schedule · {count}',
    '进行中 · {time}': 'In progress · {time}',
    '第{week}周': 'Week {week}',
    '{count} 门': '{count} courses',
    '日视图 · 全天': 'Day View · All-day',
    '周视图 · 全天': 'Week View · All-day',
    '月视图 · 全天': 'Month View · All-day',
    '公历': 'Calendar',
    '教学': 'Teaching',
    '公历第 {week} 周': 'Calendar Week {week}',
    '第 {week} 教学周': 'Teaching Week {week}',
    '非教学周': 'Outside teaching weeks',
    '公历{week} · 教学{teaching}': 'Cal {week} · Teach {teaching}',
    '颜色主题': 'Color Theme',
    '立即应用，深浅色跟随系统。': 'Applies immediately. Light and dark follow the system.',
    '默认青绿': 'Classic Teal',
    '海洋蓝': 'Ocean Blue',
    '鸢尾紫': 'Iris Violet',
    '暖琥珀': 'Warm Amber',
    '玫瑰': 'Rose',
    '自定义': 'Custom',
    '，已选中': ', selected',
    '主色': 'Primary',
    '强调色': 'Accent',
    '选中日期': 'Selected Date',
    '请输入六位十六进制 RGB（例如 #166B5D），当前已保存主题保持不变。':
      'Enter six hexadecimal RGB digits, for example #166B5D. Your saved theme is unchanged.',
    '实时预览': 'Live Preview',
    '页面背景': 'Page Canvas',
    '课程卡片': 'Course Card',
    '课程 · 08:00–09:35': 'Course · 08:00–09:35',
    '日程详情浮层': 'Event Details Panel',
    '应用自定义颜色': 'Apply Custom Colors',
    '恢复默认': 'Restore Default',
    '无法保存颜色主题，请重试。': 'Unable to save the color theme. Please retry.',
    '生效日期：': 'Effective date: ',
    '{weekday} · 农历{lunar} · {zodiac}年': '{weekday} · Lunar {lunar} · Zodiac {zodiac}',
    '干支：{year}年 {month}月 {day}日': 'Ganzhi: {year} / {month} / {day}',
    '教学云 ': 'Teaching Cloud ',
    ' 门': ' courses',
    '课程详情': 'Course Details',
    '课程资料已更新，请返回列表。': 'Course data changed. Return to the list.',
    '该课作业尚未在本机同步；可到“作业”栏目手动刷新。':
      'Assignments for this course have not been synced here. Refresh manually in Assignments.',
    '当前缓存没有可确认归属该课的作业条目。':
      'No assignment in the current cache can be reliably attributed to this course.',
    '查看作业栏目': 'Open Assignments',
    '该课程尚未确认为当前学期，未自动读取其作业或测验详情。':
      'This course is not verified as current, so its assignment and quiz details were not fetched.',
    '打开 QMplus 官方课程页': 'Open Official QMplus Course',
    '教学云': 'Teaching Cloud',
    '待交 ': 'Pending ',
    '已交 ': 'Submitted ',
    '（北京时间）': ' (Beijing time)',
    '以下换算为北京时间；原网页伦敦时间说明保持原文。':
      'Times below are converted to Beijing time; original London wording is unchanged.',
    '当前学期': 'Current term',
    '其它学期': 'Other term',
    '学期未确认': 'Term unconfirmed',
    '已获取 ': 'Fetched ',
    '网络与流量': 'Network & Data',
    '使用移动网络改善数据获取': 'Use Mobile Data to Improve Fetching',
    '默认关闭。Wi-Fi 读取失败时，仅对可安全重试的只读请求尝试一次移动网络；可能产生流量费用。':
      'Off by default. If a Wi-Fi read fails, the app tries mobile data once only for safely repeatable read-only requests. Data charges may apply.',
    '不会通过移动网络重发密码或修改请求；QMplus 官方登录网页不在此功能范围内。':
      'Passwords and modifying requests are not retried over mobile data. Official QMplus sign-in pages are not covered.',
    '无法保存移动网络设置，请重试。': 'Could not save the mobile-data setting. Please retry.',
    '移动网络辅助已在本次会话中关闭，但设置未保存；下次启动请检查开关。':
      'Mobile-data assistance is off for this session, but the setting was not saved. Check the switch next time you launch the app.',
    '考试查询': 'Exams',
    '作业 DDL': 'Assignments',
    '按学期查询教务考试安排。': 'Query exam arrangements by term.',
    '直接查询教学云课程作业，按截止时间排序。': 'Assignments from UCloud, sorted by deadline.',
    '点击刷新以查询，切换页面保留上次结果。': 'Tap Refresh to query. Switching pages keeps your results.',
    '刷新作业': 'Refresh Assignments',
    '打开教学云平台': 'Open Teaching Cloud Platform',
    '前往个人账户': 'Open Personal Account',
    '较新镜像数据': 'Newer mirror data',
    'Contest DDL 较新镜像数据': 'Newer Contest DDL mirror data',
    'Contest DDL 备用 API': 'Contest DDL backup API',
    '本次使用 Contest DDL 镜像数据': 'Using Contest DDL mirror data',
    '搜索课程或作业': 'Search courses or assignments',
    '暂无匹配的课程作业 DDL。': 'No matching assignment deadlines.',
    '刷新考试': 'Refresh Exams',
    '正在查询考试…': 'Loading exams…',
    '考场：': 'Room: ',
    '座位：': 'Seat: ',
    '状态：': 'Status: ',
    '截止时间：': 'Deadline: ',
    '更新时间：': 'Updated: ',
    '加载更多': 'Load More',
    '示例模式不查询真实考试。': 'Demo mode does not query personal exams.',
    '示例模式不查询真实作业。': 'Demo mode does not query personal assignments.',
    '成绩查询': 'Grades',
    '成绩仅在本次运行中保留，直接向学校教务系统查询。': 'Grades are fetched directly from the university and kept only for this session.',
    '请先在账户设置中保存教务账号和密码。': 'Save your academic account and password in account settings first.',
    '前往账户设置': 'Account Settings',
    '全部学期': 'All Terms',
    '学期': 'Term',
    '最好成绩': 'Best Results',
    '首次成绩': 'First Attempts',
    '全部记录': 'All Records',
    '正在查询成绩…': 'Loading grades…',
    '刷新成绩': 'Refresh Grades',
    '成绩查询失败，请稍后刷新。': 'Unable to load grades. Please refresh later.',
    '正在显示此前查询结果。': 'Showing previously fetched results.',
    '平均学分绩点：': 'Average GPA: ',
    '所选学期暂无已公布成绩。': 'No published grades for the selected term.',
    '成绩：': 'Grade: ',
    '学分：': 'Credits: ',
    '课程代码：': 'Course code: ',
    '未公布': 'Not published',
    '考试': 'Exam',
    '时间待定': 'Time pending',
    '示例模式不查询真实成绩。': 'Demo mode does not query personal grades.',
    '刷新个人课表时同步考试安排。': 'Exam arrangements sync when you refresh your schedule.',
    '考试刷新失败，正在显示此前安排。': 'Exam refresh failed. Showing previously fetched arrangements.',
    '考试安排暂时无法获取。': 'Exam arrangements are temporarily unavailable.',
    '本学期暂无考试安排。': 'No exam arrangements for this term.',
    '考试安排已同步。': 'Exam arrangements synced.',
    '另有考试日期待定：': 'Exam dates pending: ',
    '查看全部学期': 'View All Terms',
    '成绩标识：': 'Grade status: ',
    '空教室': 'Empty Rooms',
    '联动查询': 'Linked Query',
    '天气获取失败': 'Unable to load weather',
    '数据：UAPI': 'Data: UAPI',
    '获取空教室信息': 'Fetch Empty Rooms',
    '正在获取当天空教室…': 'Fetching today\'s empty rooms…',
    '使用个人课表排除已有课程': 'Exclude Personal Schedule Conflicts',
    '选中空闲': 'Select Free Slots',
    '清空': 'Clear',
    '查询概览': 'Query Summary',
    '查询条件': 'Query Options',
    '节次筛选': 'Period Filter',
    '当天课程': 'Today\'s Courses',
    '教学楼': 'Buildings',
    '空教室结果': 'Empty Room Results',
    '个人空闲节次': 'Free Periods',
    '匹配教室': 'Matching Rooms',
    '未选择': 'None selected',
    '数据源：内置示例数据 · ': 'Source: built-in demo · ',
    '数据源：移动教务实时接口 · ': 'Source: live academic API · ',
    '休': 'Rest',
    '班': 'Work',
    '试': 'Exam',
    '地点未标注': 'Location not provided',
    '座位未知': 'Capacity unknown',
    '降水': 'Precipitation',
    '教学日历': 'Calendar',
    '课程': 'Courses',
    '当前课程': 'Current Courses',
    '教学云当前课程': 'Current Teaching Cloud Courses',
    'QMplus 当前课程': 'Current QMplus Courses',
    '连接 QMplus': 'Connect QMplus',
    '连接QMplus': 'Connect QMplus',
    '重新同步 QMplus': 'Sync QMplus Again',
    '重新同步': 'Sync Again',
    '同步课程': 'Sync Courses',
    '正在同步…': 'Syncing…',
    '退出并清除 QMplus 会话': 'Sign Out and Clear QMplus Session',
    '退出并清除 QMplus 会话及已保存登录资料': 'Sign Out and Delete Saved QMplus Login',
    'QMplus 使用独立的官方网页；仅在您主动保存时，Microsoft 登录资料才进入本机安全存储。MFA 仍须本人完成。':
      'QMplus uses a separate official web page. Microsoft login details enter local secure storage only if you choose to save them. You still complete MFA yourself.',
    '已在本机安全保存 QMplus 登录资料。': 'QMplus login details are saved securely on this device.',
    '尚未保存 QMplus 登录资料。': 'No QMplus login details are saved.',
    'QMplus Microsoft 登录邮箱': 'QMplus Microsoft sign-in email',
    'QMplus 密码（仅在本机安全保存）': 'QMplus password (stored securely on this device only)',
    '安全保存 QMplus 登录资料': 'Save QMplus Login Securely',
    '允许官方登录页自动填写（默认关闭）': 'Allow Autofill on Official Sign-in Pages (Off by Default)',
    '当前构建尚未验证官方登录表单，自动填写暂不可用；请在网页中手动登录。不会自动处理 MFA 或提交登录。':
      'The official sign-in form is not yet verified in this build, so autofill is unavailable. Sign in manually; MFA and sign-in submission are never automated.',
    '仅在已核验的官方登录表单尝试一次自动填写和正常登录；账号选择、MFA、验证码及其它确认仍须手动完成。':
      'The app attempts one autofill and normal sign-in only on verified official forms. Account selection, MFA, CAPTCHA and other confirmations remain manual.',
    '仅在已核验的官方登录表单尝试自动填写；其它步骤请手动完成。':
      'Autofill is attempted only on verified official sign-in forms. Complete other steps manually.',
    '请在官方网页手动选择登录账户。': 'Choose the sign-in account manually on the official page.',
    '当前官方账号与保存的账号不一致，请手动登录。':
      'The current official account does not match the saved account. Sign in manually.',
    '此官方登录步骤需要您手动完成；应用不会重试或处理 MFA、验证码及确认页面。':
      'Complete this official sign-in step manually. The app will not retry or handle MFA, CAPTCHA or confirmation pages.',
    '此官方页面无法安全启用自动填写，请手动登录。':
      'Autofill cannot be used safely on this official page. Sign in manually.',
    '账号已提交到官方页面；如出现其他验证，请手动完成。':
      'The account was submitted to the official page. Complete any further checks manually.',
    '密码已提交到官方页面；MFA 与其他确认请由您手动完成。':
      'The password was submitted to the official page. Complete MFA and other confirmations manually.',
    '当前构建尚未验证官方登录表单，自动填写暂不可用；请手动完成登录。':
      'Autofill is unavailable until the official sign-in form is verified. Please sign in manually.',
    '删除已保存的 QMplus 登录资料': 'Delete Saved QMplus Login',
    '仅在官方网页完成 SSO/MFA；只有您主动保存时，本机系统安全存储才保存独立的 QMplus 登录资料。':
      'Complete SSO/MFA on the official site. Separate QMplus login details are kept in local system secure storage only if you choose to save them.',
    '将删除保存的账号、密码、个人课表、空教室缓存、自定义日程设置、收藏、QMplus 会话和独立保存的登录资料及其它设置。此操作无法撤销。':
      'This deletes saved accounts and passwords, timetables, room caches, custom schedules, favorites, the QMplus session, separately saved QMplus login details, and other settings. This cannot be undone.',
    '无法读取 QMplus 登录资料，自动填写已关闭。': 'QMplus login details could not be read. Autofill is off.',
    '系统无法准备 QMplus 安全存储，请稍后重试。':
      'System secure storage could not be prepared for QMplus. Try again later.',
    '无法确认已撤销 QMplus 自动填写；本次运行已停用，重启后请检查。':
      'The QMplus autofill revocation could not be confirmed. It is off for this run; check it after restart.',
    '请填写有效的 QMplus 登录账号及密码。': 'Enter a valid QMplus sign-in email and password.',
    '无法保存 QMplus 登录资料，自动填写保持关闭。': 'QMplus login details could not be saved. Autofill remains off.',
    '请先安全保存 QMplus 登录账号及密码。': 'Save your QMplus sign-in email and password securely first.',
    '无法保存 QMplus 自动填写授权，已保持关闭。': 'QMplus autofill authorization could not be saved. It remains off.',
    'QMplus 自动填写已关闭，但保存的密码未能确认删除，请重试。':
      'QMplus autofill is off, but deletion of the saved password could not be confirmed. Try again.',
    '无法确认已撤销 QMplus 自动填写或删除密码；本次运行已停用，重启后请检查。':
      'Neither QMplus autofill revocation nor password deletion could be confirmed. It is off for this run; check after restart.',
    '在独立的官方网页完成 QMplus SSO/MFA；不向本应用输入或保存 Microsoft 密码。':
      'Complete QMplus SSO/MFA in a separate official web view. This app never asks for or saves your Microsoft password.',
    '将删除保存的账号、密码、个人课表、空教室缓存、自定义日程设置、收藏、QMplus 会话和其它设置。此操作无法撤销。':
      'This removes saved accounts, passwords, timetables, room caches, custom schedules, favorites, the QMplus session and other settings. This cannot be undone.',
    '仅在官方网页完成 SSO/MFA；应用不读取或保存 Microsoft 密码。':
      'Complete SSO/MFA on the official site. This app never reads or saves your Microsoft password.',
    '通过官方网页完成 SSO/MFA；仅同步当前课程已发布作业与测验。':
      'Complete SSO/MFA on the official site. Only published assignments and quizzes from current courses are synced.',
    '第三方来源：QMplus 官方网页；时间以课程页面为准。':
      'Third-party source: official QMplus pages. Check each course page for definitive times.',
    '以下结构化时间使用 UTC；原网页时间说明保持原文。':
      'Structured times below use UTC; original website time descriptions are shown unchanged.',
    '示例模式不展示或连接真实 QMplus 数据。':
      'Demo mode does not display or connect to real QMplus data.',
    '关闭时间：': 'Closes: ',
    '详情受限，不能确认全部时间。': 'Details are restricted; not all times can be verified.',
    '详情暂不可用，显示已核实时间。': 'Details are unavailable; showing verified times only.',
    '打开 QMplus 官方活动页': 'Open Official QMplus Activity',
    '示例模式不查询真实课程。': 'Demo mode does not access real courses.',
    '教学云课程目录暂时不可用。': 'The Teaching Cloud course directory is unavailable.',
    '暂无可显示的教学云当前课程。': 'No current Teaching Cloud courses to display.',
    '暂无已确认的当前学期 QMplus 课程。': 'No verified current-term QMplus courses.',
    '其它或学期未确认的课程：': 'Other courses or courses with an unknown term: ',
    '部分课程或活动无法读取，以下为已核实的结果。':
      'Some courses or activities could not be read. Showing verified results only.',
    '本次仅部分同步成功，继续显示上次完整资料；时间仍以上次同步为准，仅供对照。':
      'This sync was partial. Showing the last complete data and its original timestamp for reference only.',
    '已核实活动数量：': 'Verified activities: ',
    '截止时间未公布': 'Deadline not published',
    '开放时间：': 'Opens: ',
    '最终截止：': 'Final cutoff: ',
    '限时：': 'Time limit: ',
    ' 秒': ' sec',
    '测验': 'Quiz',
    '刷新': 'Refresh',
    '上次同步：': 'Last sync: ',
    '请先在官方 QMplus 网页完成登录。': 'Sign in on the official QMplus page first.',
    'QMplus 同步失败。': 'QMplus sync failed.',
    'QMplus 同步已超时，请稍后重试。': 'QMplus sync timed out. Try again later.',
    'QMplus 同步脚本未能安全加载。': 'The QMplus sync script could not be loaded safely.',
    'QMplus 同步脚本无法在官方页面运行。': 'The QMplus sync script could not run on the official page.',
    'QMplus 同步未能启动。': 'QMplus sync could not start.',
    'QMplus 页面已离开官方课程区域。': 'The page left the official QMplus course area.',
    'QMplus 浏览器会话未能清除，请稍后重试。':
      'The QMplus browser session could not be cleared. Try again later.',
    '官方登录页面暂时无法加载，请检查网络后重试。':
      'The official sign-in page could not load. Check your connection and try again.',
    '设置': 'Settings',
    '查询': 'Query',
    '班车': 'Shuttle',
    '事件': 'Events',
    '成绩': 'Grades',
    '班车查询': 'Shuttle Bus',
    '重要事件': 'Important Events',
    '班车与重要事件查询': 'Shuttle & Important Events',
    '今天': 'Today',
    '明日': 'Tomorrow',
    '日': 'Day',
    '周': 'Week',
    '月': 'Month',
    '年': 'Year',
    '视图': 'View',
    '一': 'Mon',
    '二': 'Tue',
    '三': 'Wed',
    '四': 'Thu',
    '五': 'Fri',
    '六': 'Sat',
    '七': 'Sun',
    '周一': 'Mon',
    '周二': 'Tue',
    '周三': 'Wed',
    '周四': 'Thu',
    '周五': 'Fri',
    '周六': 'Sat',
    '周日': 'Sun',
    '星期一': 'Monday',
    '星期二': 'Tuesday',
    '星期三': 'Wednesday',
    '星期四': 'Thursday',
    '星期五': 'Friday',
    '星期六': 'Saturday',
    '星期日': 'Sunday',
    '全天': 'All-day',
    '暂无课程': 'No courses',
    '删除': 'Delete',
    '恢复': 'Restore',
    '已删除课程': 'Deleted courses',
    '暂无已删除课程': 'No deleted courses',
    '整门课程': 'Whole course',
    '选择删除范围': 'Choose deletion scope',
    '仅删除本次': 'Delete this occurrence',
    '删除本学期整门课程': 'Delete this course for the semester',
    '仅删除本次课程？': 'Delete only this occurrence?',
    '删除本学期整门课程？': 'Delete this course for the entire semester?',
    '确认删除': 'Confirm deletion',
    '课程删除记录': 'Course deletion records',
    '本地课程删除记录格式不正确。': 'The local course deletion records are invalid.',
    '课程修改未保存，请重试。': 'The course change was not saved. Please try again.',
    '课程删除记录已恢复。': 'The course deletion was restored.',
    '课程已从个人课表删除，可在设置中恢复。': 'Course removed from your schedule. Restore it in Settings.',
    '恢复后将重新计入个人课表、空闲节次、卡片和课程提醒。':
      'Restored courses appear again in your schedule, free periods, widgets, and course reminders.',
    '仅修改本机个人课表，可在设置中恢复。不会修改教务数据、作业 DDL 或已导出的系统日历。':
      'Only changes your local schedule; restore in Settings. Academic records, assignment deadlines, and previously exported calendar events are unchanged.',
    '无课': 'No courses',
    '无课程': 'No courses',
    '整点': 'Hours',
    '课程节次': 'Periods',
    '教师未标注': 'Instructor not provided',
    '教师：': 'Instructor: ',
    '完成': 'Done',
    '跳转到': 'Open in',
    '颜色越深表示当天课程越多': 'Darker dates have more courses or deadlines',
    '颜色越深表示当天日程越多': 'Darker dates have more courses or deadlines',
    '获取/刷新个人课表': 'Fetch / Refresh Schedule',
    '正在获取…': 'Fetching…',
    '导入系统日历': 'Add to System Calendar',
    '导入已收藏日程': 'Import Favorite Events',
    '正在导入已收藏日程…': 'Importing favorite events…',
    '暂无已收藏日程。': 'There are no favorite events to import.',
    '正在导入…': 'Importing…',
    '课程作业 DDL': 'Course Assignment Deadlines',
    '作业': 'Assignment',
    '校内': 'Campus',
    '当天暂无课程作业 DDL': 'No assignment deadlines for this day',
    '第三方来源：北京邮电大学云课堂': 'Third-party source: BUPT UCloud',
    '黄历信息': 'Almanac',
    '正在获取黄历与宜忌…': 'Loading almanac…',
    '黄历获取失败。': 'Unable to load the almanac.',
    '点击重试': 'Tap to retry',
    '暂无黄历信息': 'No almanac information',
    '民俗信息仅供参考 · 第三方来源：UAPI': 'Folklore is for reference only · Source: UAPI',
    '宜忌：Timeless API': 'Advice: Timeless API',
    '宜': 'Good',
    '忌': 'Avoid',
    'DDL · 竞赛 / 夏令营 / 黑客松': 'Deadlines · Contests / Camps / Hackathons',
    'DDL · 公开活动与校内通知': 'Deadlines · Public Events & Campus Notices',
    '当天暂无已启用类别的 DDL': 'No enabled deadlines for this day',
    '本次使用备用 API': 'Using the backup API',
    '正在获取当天 DDL…': 'Loading deadlines…',
    'DDL 获取失败。': 'Unable to load deadlines.',
    '暂无 DDL 信息': 'No deadline information',
    '第三方来源：Contest DDL': 'Third-party source: Contest DDL',
    '备用 API': 'Backup API',
    '校内竞赛通知': 'Campus Contest Notice',
    '校内竞赛通知由脚本从学校内部网站公开通知页提取整理，仅供参考。':
      'Campus contest notices are extracted by a script from public notices on an internal school website and are for reference only.',
    '学科竞赛': 'Competition',
    '学术会议': 'Conference',
    '期刊专题': 'Journal Special Issue',
    '夏令营': 'Summer Camp',
    '黑客松': 'Hackathon',
    '预推免': 'Pre-admission',
    '自定义日程': 'Custom Schedule',
    '自定义日程来源：': 'Custom schedule source: ',
    '自定义日程不符合 v1 接口规范。':
      'The custom schedule does not conform to the v1 feed contract.',
    '自定义日程只允许公开、无凭据的 HTTPS URL。':
      'Custom schedules require a public credential-free HTTPS URL.',
    '自定义日程接口版本必须为 1。': 'The custom schedule feed version must be 1.',
    '自定义日程数据格式不正确。': 'The custom schedule JSON is invalid.',
    '自定义日程日期格式不正确。': 'The custom schedule date is invalid.',
    '自定义日程更新时间格式不正确。': 'The custom schedule updated_at value is invalid.',
    '自定义日程条目超过 5000 项。': 'The custom schedule contains more than 5,000 items.',
    '自定义日程来源主页必须使用安全的 HTTPS URL。':
      'The custom schedule homepage must be a safe HTTPS URL.',
    '自定义日程来源名称无效。': 'The custom schedule source name is invalid.',
    '自定义日程获取失败。': 'Unable to load the custom schedule.',
    '请先填写有效的 HTTPS 自定义日程地址': 'Enter a valid HTTPS custom schedule URL first',
    '自定义日程只允许公开、无凭据的 HTTPS URL':
      'Custom schedules require a public credential-free HTTPS URL',
    '示例数据 · 不连接北邮教务服务': 'Demo data · No connection to BUPT services',
    '显示数据仅供参考，请以实际情况为准。':
      'Displayed data is for reference only; rely on official information.',
    '内置示例模式已开启，不会连接教务服务或读写真实用户数据。':
      'Built-in demo mode is on. It does not connect to school services or access real user data.',
    '返回真实数据': 'Return to Real Data',
    '无需教务账号即可浏览内置虚构课表、空教室和教学日历。':
      'Browse fictional schedules, rooms, and calendars without a school account.',
    '浏览内置示例数据': 'Browse Demo Data',
    '语言': 'Language',
    '选择语言': 'Choose Language',
    '返回': 'Back',
    '跟随系统': 'System',
    '简体中文': 'Simplified Chinese',
    '个人账户': 'Account',
    '教务账号': 'School Account',
    '密码': 'Password',
    '教务密码': 'Academic password',
    '改用教务密码': 'Use academic password instead',
    '用于移动教务登录和查询课表、成绩及考试安排；可能与统一身份认证密码不同。部分账号的初始密码可能是八位出生日期（YYYYMMDD），请以本人实际设置为准。':
      'Used to sign in to mobile academic services for timetables, grades and exams. It may differ from your unified identity password. For some accounts, the initial password may be the eight-digit birth date (YYYYMMDD); use your actual account settings.',
    '用于课程作业 DDL 查询，通常是统一身份认证密码；未单独设置时使用教务密码。已保存的独立密码留空不变；修改后请保存设置。':
      'Used for assignment deadlines and usually matches the unified identity password. If unset, the academic password is used. Leave a saved separate password blank to keep it; save settings after making changes.',
    '教学云平台密码': 'Teaching Cloud password',
    '教学云登录失败，请检查设置中的教学云平台密码；未设置时使用教务密码。若官方页面要求验证码，请先完成验证。':
      'Teaching Cloud sign-in failed. Check the Teaching Cloud password in Settings; without an override, the academic password is used. Complete verification on the official site if requested.',
    '独立密码已安全保存，留空保持不变': 'Separate password is securely saved; leave blank to keep it',
    '未设置独立密码时使用教务密码': 'Uses the academic password when no separate password is set',
    '仅用于作业 DDL；与教务密码不同时填写，保存后生效。':
      'Only for assignment deadlines. Enter it if different from your academic password, then save.',
    '使用教务密码': 'Use academic password',
    '保存后将清除独立密码并使用教务密码': 'Saving will remove the separate password and use the academic password',
    '密码已安全保存，留空保持不变': 'Password is securely saved; leave blank to keep it',
    '默认校区': 'Default Campus',
    '西土城': 'Xitucheng',
    '沙河': 'Shahe',
    '保存设置': 'Save Settings',
    '系统安全存储不可用，账号密码未能保存，请稍后重试。':
      'Secure storage is unavailable. Your account and password were not saved. Try again later.',
    '账号和密码仅保存于本机，并由 HarmonyOS ASSET 安全存储保护。':
      'Your account and password stay on this device and are protected by HarmonyOS ASSET.',
    '学期设置': 'Semester',
    '自动检测当前学期': 'Detect Current Semester Automatically',
    '学期编号': 'Semester ID',
    '第一周周一（YYYY-MM-DD）': 'First Monday (YYYY-MM-DD)',
    '启动或获取/刷新课表后，会自动应用教务返回的学期与开学日期。':
      'At launch or after a schedule refresh, the semester and start date returned by the school service are applied automatically.',
    '关闭自动检测后，将使用手动填写的学期信息。':
      'Manual semester values are used when automatic detection is off.',
    '保存学期设置': 'Save Semester',
    '日期详情与生活信息': 'Date Details & Daily Information',
    '校区天气': 'Campus Weather',
    '黄历与宜忌': 'Almanac & Advice',
    '学科竞赛 DDL': 'Competition Deadlines',
    '学术会议 DDL': 'Conference Deadlines',
    '学术会议/期刊专题 DDL': 'Conference / Journal Special Issue Deadlines',
    '夏令营 DDL': 'Summer Camp Deadlines',
    '夏令营/预推免 DDL': 'Summer Camp / Pre-admission Deadlines',
    '黑客松 DDL': 'Hackathon Deadlines',
    '自定义日程 HTTPS 地址': 'Custom Schedule HTTPS URL',
    '保存自定义日程地址': 'Save Custom Schedule URL',
    '显示自定义日程': 'Show Custom Schedule',
    '收藏管理': 'Favorite Management',
    '返回设置': 'Back to Settings',
    '暂无收藏日程': 'No Favorite Schedules',
    '在日程详情右侧点击星标后，即使关闭来源或上游删除条目，收藏仍会保存在本机。':
      'Tap the star in event details to keep a local copy even if its source is disabled or removes it.',
    '收藏': 'Favorite',
    '取消收藏': 'Remove Favorite',
    '自定义日程地址已保存': 'Custom schedule URL saved',
    '无法保存自定义日程地址': 'Unable to save the custom schedule URL',
    '无法保存自定义日程开关': 'Unable to save the custom schedule switch',
    '无法保存收藏': 'Unable to save favorite',
    '无法保存语言设置': 'Unable to save the language setting',
    '班车刷新失败，继续显示上次获取的数据。': 'The shuttle refresh failed. Showing the previously fetched data.',
    '数据生成时间：': 'Source generated at: ',
    '本机获取时间：': 'Fetched on this device: ',
    '无法删除收藏': 'Unable to remove favorite',
    '收藏已达 500 条上限，请先取消部分收藏。':
      'The 500-favorite limit has been reached. Remove a favorite before adding another.',
    '天气、黄历和 DDL 来自第三方公开服务；校内竞赛通知由脚本从学校内部网站公开通知页提取整理，各卡片底部会标明具体来源。':
      'Weather, almanac, and deadlines use public third-party services. Campus notices are script-extracted from public notices on an internal school website; each card identifies its source.',
    '课程提醒': 'Course Reminders',
    '每日课程摘要': 'Daily course summary',
    '提醒时间（北京时间）': 'Reminder time (Beijing time)',
    '仅在当天有课时通知；课表更新或账号变更后会自动重排。':
      'Only notify on class days; reminders are rescheduled after schedule or account changes.',
    '本地数据': 'Local Data',
    '个人课表、空教室缓存、节假日缓存、账号与偏好均只保存在本机。':
      'Schedules, room and holiday caches, account, and preferences stay on this device.',
    '个人课表、空教室缓存、节假日缓存、自定义日程设置、收藏、账号与偏好均只保存在本机。':
      'Schedules, room and holiday caches, custom schedule settings, favorites, account, and preferences stay on this device.',
    '清除本地数据': 'Clear Local Data',
    '清除全部本地数据？': 'Clear all local data?',
    '将删除保存的账号、密码、个人课表、空教室缓存、自定义日程设置、收藏和其它设置。此操作无法撤销。':
      'This removes saved credentials, schedules, classroom caches, custom schedule settings, favorites, and other settings. This cannot be undone.',
    '将删除保存的账号、密码、个人课表、空教室缓存和设置。此操作无法撤销。':
      'This deletes the saved account, password, schedule, room cache, and settings. It cannot be undone.',
    '取消': 'Cancel',
    '确认清除': 'Clear',
    '关于本应用': 'About',
    '北邮课表与空教室查询的独立非官方客户端，不由北京邮电大学运营。':
      'An independent unofficial BUPT schedule and empty-room client, not operated by BUPT.',
    'APP 备案：琼ICP备2026012322号-2A': 'App filing: 琼ICP备2026012322号-2A',
    'GitHub 项目主页': 'GitHub Project',
    '隐私说明': 'Privacy Notice',
    '隐私政策提示': 'Privacy Policy Notice',
    '欢迎使用 Where To Study。请在使用前阅读并同意隐私政策，了解教务账号、课表、系统日历、天气及公开活动数据的处理方式。':
      'Welcome to Where To Study. Before using the app, read and accept the Privacy Policy to understand how school accounts, schedules, calendars, weather, and public-event data are handled.',
    '阅读完整隐私政策': 'Read the Full Privacy Policy',
    '阅读隐私政策': 'Read the Privacy Policy',
    '同意状态仅保存在本机，不会上传。':
      'Your consent choice is stored only on this device and is never uploaded.',
    '你已拒绝隐私政策，无法进入应用主功能。你仍可阅读政策并重新选择。':
      'You declined the Privacy Policy, so the app\'s main features are unavailable. You may still read the policy and reconsider.',
    '无法在本机保存同意状态，请稍后重试。':
      'Unable to save your consent on this device. Try again later.',
    '拒绝': 'Decline',
    '同意并继续': 'Accept and Continue',
    '正在保存…': 'Saving…',
    '正在读取隐私设置…': 'Loading privacy settings…',
    '桌面小组件': 'Home Screen Card',
    '显示课程地点': 'Show Course Location',
    '显示任课教师': 'Show Instructor',
    '显示课程数量': 'Number of Courses',
    '样式预览 · 示例内容': 'Style Preview · Demo Content',
    '紧凑': 'Compact',
    '标准': 'Standard',
    '展开': 'Expanded',
    '正在同步云课堂作业…': 'Syncing UCloud assignments…',
    '今日校区班车': 'Today\'s Campus Shuttle',
    '信息查询': 'Information Search',
    '今日班车按时刻表运行': 'Today\'s Shuttle Is Running as Scheduled',
    '今日没有计划班次': 'No Scheduled Departures Today',
    '今日共 {routes} 个方向、{departures} 个计划班次':
      '{routes} routes · {departures} scheduled departures today',
    '刷新班车信息': 'Refresh Shuttle Information',
    '刷新重要事件': 'Refresh Important Events',
    '当前展示最近一次成功同步的缓存': 'Showing the last successfully synchronized timetable',
    '后勤部通知 · ': 'Logistics notice · ',
    '查看班车通知原文': 'View the Original Shuttle Notice',
    '查看数据来源': 'View Data Source',
    '正在读取后勤部最新通知与当前生效时刻表。':
      'Reading the latest logistics notice and the currently active timetable.',
    '班车信息暂不可用': 'Shuttle Information Is Unavailable',
    '第三方来源：北京邮电大学后勤部公开通知，由 Where To Study 服务解析整理，仅供参考，请以官方原文为准。':
      'Third-party source: public notices from BUPT Logistics, parsed by Where To Study. ' +
      'For reference only; the official notice takes precedence.',
    '当前执行': 'In Service',
    '尚未开始': 'Not Started',
    ' 起': ' onward',
    '历史时段': 'Historical Schedule',
    '时段待确认': 'Schedule Pending',
    '数据最新': 'Up to Date',
    '缓存数据': 'Cached Data',
    '最新通知尚未完成结构化识别，以下为上一份可安全展示的时刻表，仅供对照。':
      'The latest notice is not yet safely structured. The previous verified timetable is shown for reference only.',
    '法定节假日班车安排以学校通知为准，请提前五分钟候车。':
      'Holiday service follows official notices. Please arrive five minutes early.',
    '今日为法定节假日，班车不一定运行；请以学校放假安排为准，放假期间无班车。':
      'Today is a public holiday. Shuttles may not run; follow the university holiday schedule. There is no shuttle service during the holiday break.',
    '完整班车时刻表': 'Full Shuttle Timetable',
    '当前生效': 'Active now',
    '即将生效': 'Upcoming',
    '已结束时段': 'Past period',
    '日期待确认': 'Dates unconfirmed',
    '截至': 'Until',
    '起': 'onward',
    '法定节假日，班车安排以学校通知为准': 'Public holiday: follow the university shuttle notices',
    '无计划班次': 'No scheduled departures',
    '发车地点：': 'Departure: ',
    '今日暂无计划班车': 'No Scheduled Shuttle Today',
    '下一班': 'Next',
    '计划班次': 'Scheduled Service',
    '搜索名称、主办方、类型或日期': 'Search name, organizer, type, or date',
    '搜索名称、主办方、分类、地点或来源':
      'Search name, organizer, category, location, or source',
    '全部': 'All',
    '全部分类': 'All Categories',
    '校内竞赛': 'Campus Contest',
    '显示已结束或归档事件': 'Show Ended or Archived Events',
    '没有符合条件的重要事件': 'No matching important events',
    '请调整搜索关键词或分类筛选。': 'Try another keyword or category.',
    '正在读取最新班车信息': 'Loading the latest shuttle information',
    '正在读取重要事件': 'Loading important events',
    '请稍候…': 'Please wait…',
    '数据暂时无法读取。': 'Data is temporarily unavailable.',
    '重新加载': 'Reload',
    '今日暂无生效的班车时刻表': 'No Effective Shuttle Timetable Today',
    '不会使用未来或历史时刻表代替今日安排，请以后勤部最新通知为准。':
      'Future or historical timetables are never substituted for today. Check the latest official notice.',
    '今日无生效时刻表': 'No Effective Timetable Today',
    '班车信息暂时无法读取。': 'Shuttle information is temporarily unavailable.',
    '重要事件暂时无法读取。': 'Important events are temporarily unavailable.',
    '班车数据格式不正确。': 'The shuttle data format is invalid.',
    '班车数据中没有有效通知。': 'The shuttle feed contains no valid notices.',
    '无法连接服务器，请检查网络后重试。':
      'Unable to connect to the server. Check your network and try again.',
    '请求地址不符合安全策略。': 'The request URL does not satisfy the security policy.',
    '响应过大。': 'The response is too large.',
    'DDL 数据格式不正确。': 'The deadline data format is invalid.',
    '校内竞赛通知格式不正确。': 'The campus contest notice data format is invalid.',
    '第三方来源：北京邮电大学后勤部公开通知；由 Where To Study 服务端每小时整理，结果仅供参考。':
      'Third-party source: public BUPT Logistics notices, processed hourly by Where To Study for reference only.',
    '第三方来源：Contest DDL 公开活动与校内竞赛通知；校内通知由脚本从学校内部网站公开通知页提取整理。':
      'Third-party sources: Contest DDL and campus contest notices. Campus notices are script-extracted from public pages on an internal school website.',
    '第三方来源：Contest DDL 主源、较新镜像及备用 API；校内通知由脚本从学校内部网站公开通知页提取整理。':
      'Third-party sources: Contest DDL primary, newer mirror, and backup API. Campus notices are script-extracted from public pages on an internal school website.',
    '课程作业获取失败。': 'Unable to load course assignments.',
    '正在展示内置示例课表，未连接北邮服务':
      'Showing the built-in demo schedule; no BUPT service connection',
    '正在展示内置示例空教室，未连接北邮服务':
      'Showing built-in demo rooms; no BUPT service connection',
    '示例模式不会保存账户或设置': 'Demo mode does not save accounts or settings',
    '设置已保存': 'Settings saved',
    '学期设置已保存': 'Semester settings saved',
    '示例模式不会申请通知权限': 'Demo mode does not request notification permission',
    '正在确认通知权限…': 'Checking notification permission…',
    '每日课程摘要已关闭': 'Daily course summary is off',
    '课前提醒': 'Before-class reminders',
    '提前分钟': 'Minutes before',
    '编辑提醒': 'Edit reminders',
    '提醒次数': 'Reminder count',
    '减少提醒次数': 'Fewer reminders',
    '增加提醒次数': 'More reminders',
    '提醒': 'Reminder',
    '分钟': 'min',
    '保存提醒': 'Save reminders',
    '请输入 1–5 个不重复的整数，每个为 1–1440 分钟。':
      'Enter 1–5 distinct whole numbers, each from 1 to 1440 minutes.',
    '按北京时间，在课程或考试开始前提醒；默认提前 10 分钟。':
      'Remind before classes or exams in Beijing time; 10 minutes before by default.',
    '系统最多保留近期 30 条提醒；打开应用时自动补充后续安排。':
      'Up to 30 upcoming reminders are kept. Open the app to schedule later reminders.',
    '课程提醒已关闭': 'Course reminders are off',
    '通知权限未开启，未安排课程提醒': 'Notifications are disabled; no course reminders were scheduled',
    '课程提醒已开启，获取课表后自动安排': 'Course reminders are on and will be scheduled after fetching the schedule',
    '课程提醒已开启，当前课表没有待通知课程': 'Course reminders are on; there are no upcoming reminders',
    '账号已更改，获取课表后将重新安排提醒': 'The account changed; reminders will be rescheduled after fetching the schedule',
    '通知权限未开启，未安排课程摘要': 'Notifications are disabled; no course summary was scheduled',
    '每日课程摘要已开启，获取课表后自动安排':
      'Daily course summary is on and will be scheduled after fetching the schedule',
    '每日课程摘要已开启，当前课表没有待通知课程':
      'Daily course summary is on; the current schedule has no upcoming class days',
    '示例模式已模拟开启每日课程摘要，未申请通知权限':
      'Daily course summaries are simulated in demo mode; no notification permission was requested',
    '示例模式已模拟关闭每日课程摘要':
      'Daily course summaries are disabled in demo mode',
    '示例模式不读写真实本地数据': 'Demo mode does not access real local data',
    '正在导入系统日历…': 'Importing into the system calendar…',
    '课表中没有可导入的课程日期': 'No course dates are available to import',
    '当天空教室已更新': 'Today\'s empty rooms are up to date',
    '账号已更改，获取课表后将重新安排摘要':
      'The account changed; summaries will be rescheduled after fetching the schedule',
    '本地数据已清除': 'Local data cleared',
    '仅在已核验的官方登录页自动选择精确匹配的已保存账号，并填写账号和密码，各步骤最多一次。未匹配的账号选择、MFA、验证码、保持登录、风险及协议确认仍须本人操作。': 'Only verified official sign-in pages may select the exact saved account and fill the username and password, with each step attempted at most once. Unmatched account choices, MFA, CAPTCHA, staying signed in, risk and terms confirmations still require your action.',
    '关闭“启用 QMplus”只暂停连接和同步，保留登录资料、会话及课程缓存。关闭自动填写、删除登录资料或退出并清除数据，请使用对应操作。': 'Turning off “Enable QMplus” only pauses connection and sync; saved credentials, the session and course cache are retained. Use the separate controls to turn off autofill, delete credentials, or disconnect and clear data.'
  };

  static text(source: string, setting: AppLanguage, systemLanguage: string): string {
    const language: AppLanguage = AppLanguageInfo.resolved(setting, systemLanguage);
    if (language === AppLanguage.simplifiedChinese) {
      return source;
    }
    if (language !== AppLanguage.english) {
      return AppLocalizationCatalog.text(source, language) ?? source;
    }
    const exact: string | undefined = AppLocalization.english[source];
    if (exact !== undefined) {
      return exact;
    }
    if (source.endsWith(' 门课')) {
      const count: string = source.substring(0, source.length - 3);
      return count + (count === '1' ? ' course' : ' courses');
    }
    if (source.endsWith(' 门')) {
      const count: string = source.substring(0, source.length - 2);
      return count + (count === '1' ? ' course' : ' courses');
    }
    if (source.endsWith('视图')) {
      return AppLocalization.text(source.substring(0, source.length - 2), setting,
        systemLanguage) + ' View';
    }
    if (source.startsWith('第 ') && source.endsWith(' 节')) {
      return 'Period ' + source.substring(2, source.length - 2);
    }
    if (source.startsWith('第') && source.endsWith('节')) {
      return 'Period ' + source.substring(1, source.length - 1);
    }
    if (source.startsWith('第 ') && source.includes(' 节 ')) {
      const split: number = source.indexOf(' 节 ');
      return 'Period ' + source.substring(2, split) + source.substring(split + 2);
    }
    if (source.endsWith(' 座')) {
      return source.substring(0, source.length - 2) + ' seats';
    }
    if (source.startsWith('教师：')) {
      return 'Instructor: ' + source.substring(3);
    }
    if (source.startsWith('课程摘要安排失败：')) {
      return 'Unable to schedule course summaries: ' +
        source.substring('课程摘要安排失败：'.length);
    }
    if (source.startsWith('课程提醒安排失败：')) {
      return 'Unable to schedule course reminders: ' + source.substring('课程提醒安排失败：'.length);
    }
    if (source.startsWith('已安排 ') && source.endsWith(' 条课程提醒')) {
      return source.substring('已安排 '.length, source.length - ' 条课程提醒'.length) + ' course reminders scheduled';
    }
    if (source.startsWith('已安排 ') && source.endsWith(' 条课程提醒，部分提醒暂时未能安排')) {
      return source.substring('已安排 '.length,
        source.length - ' 条课程提醒，部分提醒暂时未能安排'.length) +
        ' course reminders scheduled; some reminders could not be scheduled';
    }
    if (source.startsWith('自定义日程获取失败：')) {
      return 'Unable to load the custom schedule: ' +
        source.substring('自定义日程获取失败：'.length);
    }
    if (source.startsWith('班车服务返回 HTTP ')) {
      return 'The shuttle service returned HTTP ' +
        source.substring('班车服务返回 HTTP '.length).replace('。', '.');
    }
    if (source.startsWith('系统安全存储操作失败（')) {
      return 'Secure storage failed (' +
        source.substring('系统安全存储操作失败（'.length).replace('）。', ').');
    }
    if (source.startsWith('域名解析失败（网络错误 ')) {
      const end: number = source.indexOf('）');
      const code: string = end > 0 ?
        source.substring('域名解析失败（网络错误 '.length, end) : 'unknown';
      return 'DNS resolution failed (network error ' + code +
        '). Check DNS, proxy, or campus-network sign-in and try again.';
    }
    if (source.startsWith('连接服务器超时（网络错误 ')) {
      const end: number = source.indexOf('）');
      const code: string = end > 0 ?
        source.substring('连接服务器超时（网络错误 '.length, end) : 'unknown';
      return 'The server connection timed out (network error ' + code +
        '). Switch networks or try again later.';
    }
    if (source.startsWith('安全连接校验失败（网络错误 ')) {
      const end: number = source.indexOf('）');
      const code: string = end > 0 ?
        source.substring('安全连接校验失败（网络错误 '.length, end) : 'unknown';
      return 'Secure connection validation failed (network error ' + code +
        '). Disable the network proxy, complete campus-network sign-in, or switch networks.';
    }
    if (source.startsWith('网络请求配置异常（错误 ')) {
      const end: number = source.indexOf('）');
      const code: string = end > 0 ?
        source.substring('网络请求配置异常（错误 '.length, end) : 'unknown';
      return 'The network request configuration is invalid (error ' + code +
        '). Please report this to the developer.';
    }
    if (source.startsWith('无法连接服务器（网络错误 ')) {
      const end: number = source.indexOf('）');
      const code: string = end > 0 ?
        source.substring('无法连接服务器（网络错误 '.length, end) : 'unknown';
      return 'Unable to connect to the server (network error ' + code +
        '). Switch networks or complete campus-network sign-in and try again.';
    }
    if (source === '无法连接服务器（未知网络错误），请切换网络或完成校园网认证后重试。') {
      return 'Unable to connect to the server (unknown network error). Switch networks or ' +
        'complete campus-network sign-in and try again.';
    }
    if (source.startsWith('公开活动 DDL 不可用')) {
      return 'Public event deadlines are temporarily unavailable.';
    }
    if (source.startsWith('已安排未来 ') && source.endsWith(' 个有课日的课程摘要')) {
      return 'Course summaries scheduled for ' + source.substring('已安排未来 '.length,
        source.length - ' 个有课日的课程摘要'.length) + ' upcoming class days';
    }
    if (source.startsWith('收藏日程同步完成：')) {
      return 'Favorite-event sync complete: ' +
        source.substring('收藏日程同步完成：'.length)
          .replace('新增 ', 'added ')
          .replace('，更新 ', ', updated ')
          .replace('，删除 ', ', deleted ')
          .replace('，已存在 ', ', unchanged ');
    }
    if (source.startsWith('示例模式已模拟导入 ') && source.endsWith(' 条收藏日程，未写入系统日历')) {
      return 'Sample mode simulated ' + source.substring('示例模式已模拟导入 '.length,
        source.length - ' 条收藏日程，未写入系统日历'.length) +
        ' favorite events without writing to the system calendar';
    }
    if (source.startsWith('本地课表读取失败：')) {
      return 'Unable to read the local schedule: ' +
        source.substring('本地课表读取失败：'.length);
    }
    if (source.startsWith('本地空教室读取失败：')) {
      return 'Unable to read the local room cache: ' +
        source.substring('本地空教室读取失败：'.length);
    }
    if (source.endsWith(' 月')) {
      return 'Month ' + source.substring(0, source.length - 2);
    }
    return source;
  }

  static format(source: string, values: LocalizationValues, setting: AppLanguage,
    systemLanguage: string): string {
    return values.apply(AppLocalization.text(source, setting, systemLanguage));
  }
}
