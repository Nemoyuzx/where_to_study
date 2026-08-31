// 应用内语言偏好。API 返回的课程名、竞赛名、黄历内容等不经过本地化；
// 只有代码内已知的静态 UI 与状态文案会进入此映射。
import { i18n } from '@kit.LocalizationKit';

export enum AppLanguage {
  system = 'system',
  simplifiedChinese = 'zh-Hans',
  english = 'en'
}

export class AppLanguageInfo {
  static readonly all: AppLanguage[] = [
    AppLanguage.system, AppLanguage.simplifiedChinese, AppLanguage.english
  ];

  static normalize(value: string | null): AppLanguage {
    if (value === AppLanguage.simplifiedChinese) {
      return AppLanguage.simplifiedChinese;
    }
    if (value === AppLanguage.english) {
      return AppLanguage.english;
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
    return systemLanguage.toLowerCase().startsWith('zh') ?
      AppLanguage.simplifiedChinese : AppLanguage.english;
  }

  static label(setting: AppLanguage, displayLanguage: AppLanguage): string {
    if (displayLanguage === AppLanguage.english) {
      if (setting === AppLanguage.system) {
        return 'System';
      }
      if (setting === AppLanguage.simplifiedChinese) {
        return 'Simplified Chinese';
      }
      return 'English';
    }
    if (setting === AppLanguage.system) {
      return '跟随系统';
    }
    if (setting === AppLanguage.simplifiedChinese) {
      return '简体中文';
    }
    return 'English';
  }
}

export class AppLocalization {
  private static readonly english: Record<string, string> = {
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
    '设置': 'Settings',
    '查询': 'Query',
    '班车查询': 'Shuttle Bus',
    '重要事件': 'Important Events',
    '班车与重要事件查询': 'Shuttle & Important Events',
    '今天': 'Today',
    '明日': 'Tomorrow',
    '日': 'Day',
    '周': 'Week',
    '月': 'Month',
    '年': 'Year',
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
    '跟随系统': 'System',
    '简体中文': 'Simplified Chinese',
    '个人账户': 'Account',
    '教务账号': 'School Account',
    '密码': 'Password',
    '密码已安全保存，留空保持不变': 'Password is securely saved; leave blank to keep it',
    '默认校区': 'Default Campus',
    '西土城': 'Xitucheng',
    '沙河': 'Shahe',
    '保存设置': 'Save Settings',
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
    '夏令营 DDL': 'Summer Camp Deadlines',
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
    '无法删除收藏': 'Unable to remove favorite',
    '天气、黄历和 DDL 来自第三方公开服务；校内竞赛通知由脚本从学校内部网站公开通知页提取整理，各卡片底部会标明具体来源。':
      'Weather, almanac, and deadlines use public third-party services. Campus notices are script-extracted from public notices on an internal school website; each card identifies its source.',
    '课程提醒': 'Course Reminders',
    '每天 07:30 发送当日课程摘要': 'Send Today\'s Course Summary at 07:30',
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
    'GitHub 项目主页': 'GitHub Project',
    '隐私说明': 'Privacy Notice',
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
    '本地数据已清除': 'Local data cleared'
  };

  static text(source: string, setting: AppLanguage, systemLanguage: string): string {
    if (AppLanguageInfo.resolved(setting, systemLanguage) !== AppLanguage.english) {
      return source;
    }
    const exact: string | undefined = AppLocalization.english[source];
    if (exact !== undefined) {
      return exact;
    }
    if (source.endsWith(' 门课')) {
      return source.substring(0, source.length - 3) + ' courses';
    }
    if (source.endsWith(' 门')) {
      return source.substring(0, source.length - 2) + ' courses';
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
    if (source.startsWith('自定义日程获取失败：')) {
      return 'Unable to load the custom schedule: ' +
        source.substring('自定义日程获取失败：'.length);
    }
    if (source.startsWith('班车服务返回 HTTP ')) {
      return 'The shuttle service returned HTTP ' +
        source.substring('班车服务返回 HTTP '.length).replace('。', '.');
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
}
