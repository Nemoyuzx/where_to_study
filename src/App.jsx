import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import {
  AlertTriangle,
  BellRing,
  Building2,
  CalendarDays,
  CalendarPlus,
  CalendarRange,
  CheckCircle2,
  ClipboardList,
  Cloud,
  CloudFog,
  CloudLightning,
  CloudRain,
  CloudSnow,
  Clock3,
  ChevronDown,
  ExternalLink,
  Home,
  HardDrive,
  Info,
  KeyRound,
  Loader2,
  MapPin,
  Code2,
  RefreshCw,
  Search,
  Settings,
  ShieldCheck,
  Sun,
  TentTree,
  Trash2,
  Trophy,
  X,
} from 'lucide-react'
import {
  accountHasSavedPassword,
  addDays,
  buildCalendarDayMap,
  buildMiniMonthDays,
  buildMonthDays,
    buildingsForCampus,
    calendarMonthExpansion,
    calendarMonthDragProgress,
    calendarMonthExpansionTarget,
    calendarSwipeDirection,
  CALENDAR_END_HOUR,
  CALENDAR_START_HOUR,
  CALENDAR_VIEWS,
  CALENDAR_VISIBLE_MINUTES,
  CALENDAR_WEEKDAYS,
  contractTimestamp,
  courseTimeBounds,
  dateFromString,
  deadlinePreheatPlan,
  DEFAULT_SETTINGS,
  displayBuildingName,
  FALLBACK_SLOTS,
  fallbackHolidayItems,
  formatCalendarTitle,
  formatCourseDate,
  formatShortDate,
  formatTeachingWeek,
  expandedMonthGridMetrics,
  getCampusClassrooms,
  getWeekState,
  hasCalendarItemType,
  isValidAccountScope,
  isValidTermId,
  isValidTermStartDate,
  localDateString,
  suggestTermForDate,
  termMatchesCurrentPeriod,
  msUntilNextShanghaiMidnight,
  normalizeClassroomsCache,
  normalizeError,
  parseTimeMinutes,
  requestBody,
  resolvedUiLanguage,
  savedCredentialSnapshot,
  savedSettingsToState,
  settingsToPayload,
  shanghaiDateString,
  shiftDate,
  slotsToRanges,
  startOfWeekMonday,
  summarizeMonthEntries,
  yearCourseOpacity,
} from './planner-domain.js'
import './App.css'

const NAV_ITEMS = [
  { id: 'planner', label: '空教室', Icon: Home },
  { id: 'calendar', label: '教学日历', Icon: CalendarRange },
  { id: 'settings', label: '设置', Icon: Settings },
]

const EN_TEXT = Object.freeze({
  '空教室': 'Empty Classrooms',
  '教学日历': 'Teaching Calendar',
  '设置': 'Settings',
  '联动查询': 'Linked Search',
  '应用导航': 'App navigation',
  '日历视图': 'Calendar view',
  '日': 'Day',
  '周': 'Week',
  '月': 'Month',
  '年': 'Year',
  '今天': 'Today',
  '上一段': 'Previous period',
  '下一段': 'Next period',
  '全天': 'All day',
  '全天日程': 'All-day events',
  '关闭全天日程': 'Close all-day events',
  '打开所选日期': 'Open selected date',
  '查看日': 'Day',
  '查看周': 'Week',
  '查看月': 'Month',
  '查询条件': 'Search options',
  '查询校区': 'Search campus',
  '正在获取当天空教室…': 'Loading today’s empty classrooms…',
  '获取空教室信息': 'Load empty classrooms',
  '数据源': 'Source',
  '当天课程': 'Today’s courses',
  '个人空闲节次': 'Free periods',
  '匹配教室': 'Matching rooms',
  '节次筛选': 'Period filters',
  '使用个人课表排除已有课程': 'Exclude occupied periods using my schedule',
  '选中空闲': 'Select free periods',
  '清空': 'Clear',
  '个人课表占用': 'Occupied by your schedule',
  '个人课程时间，已纳入筛选': 'Course period, included in filtering',
  '个人空闲，可筛选教室': 'Free period, available for classroom search',
  '未选择': 'None selected',
  '暂无课程': 'No courses',
  '教师未标注': 'Teacher unavailable',
  '地点未标注': 'Location unavailable',
  '教学楼': 'Teaching buildings',
  '暂无教学楼': 'No teaching buildings',
  '空教室结果': 'Empty classroom results',
  '未选择教学楼': 'Select a teaching building',
  '未选择节次': 'Select at least one period',
  '座位未知': 'Capacity unknown',
  '暂无匹配空教室': 'No matching empty classrooms',
  '获取/刷新个人课表': 'Load / refresh my schedule',
  '导入苹果日历': 'Import into Apple Calendar',
  '收起月历': 'Collapse month',
  '展开月历': 'Expand month',
  '月历': 'Month calendar',
  '无课程': 'No courses',
  '当天没有课程': 'No courses today',
  '信息未标注': 'Details unavailable',
  '时间待定': 'Time TBD',
  '课程名称未标注': 'Course name unavailable',
  '课程作业 DDL': 'Assignment deadlines',
  '正在同步云课堂作业…': 'Syncing UCloud assignments…',
  '点击重试': 'Tap to retry',
  '当天没有课程作业截止': 'No assignment deadlines today',
  '第三方来源': 'Third-party source',
  '北京邮电大学云邮教学空间': 'BUPT UCloud',
  '竞赛与活动 DDL': 'Competition and event deadlines',
  '正在更新实时 DDL…': 'Updating live deadlines…',
  '当天没有已启用类型的报名或提交截止': 'No enabled registration or submission deadlines today',
  '学科竞赛': 'Academic competitions',
  '校内竞赛通知': 'School competition notices',
  '夏令营': 'Summer camps',
  '黑客松': 'Hackathons',
  '校区天气': 'Campus weather',
  '今日与明日': 'Today and tomorrow',
  '正在更新天气…': 'Updating weather…',
  '今日': 'Today',
  '明日': 'Tomorrow',
  '降水': 'Precipitation',
  '数据：UAPI': 'Data: UAPI',
  '黄历信息': 'Chinese almanac',
  '正在查询…': 'Loading…',
  '农历': 'Lunar',
  '岁次': 'Year pillar',
  '月柱': 'Month pillar',
  '日柱': 'Day pillar',
  '宜：': 'Suitable: ',
  '忌：': 'Avoid: ',
  '暂无数据': 'No data',
  '民俗信息仅供参考 · 数据：': 'Folk information is for reference only · Data: ',
  '个人账号': 'Account',
  '学号': 'Student ID',
  '请输入教务学号': 'Enter your academic-system student ID',
  '教务密码': 'Academic-system password',
  '已安全保存，留空保持不变': 'Saved securely; leave blank to keep it',
  '输入后保存到系统凭据存储': 'Saved in the operating system credential store',
  '默认校区': 'Default campus',
  '保存设置': 'Save settings',
  '已保存': 'Saved',
  '学期设置': 'Term settings',
  '自动检测当前学期': 'Detect the current term automatically',
  '学期编号': 'Term ID',
  '第一周周一': 'Monday of week 1',
  '获取/刷新课表后会自动应用教务返回的学期与开学日期。': 'Loading your schedule automatically applies the term and start date returned by the academic system.',
  '已关闭自动检测，将使用上方手动填写的学期信息。': 'Automatic detection is off; the term values above will be used.',
  '按当前日期填写': 'Suggest from today',
  '✓ 与当前学期一致': '✓ Matches the current term',
  '当前设置与检测结果不同': 'Current values differ from the detected term',
  '保存学期设置': 'Save term settings',
  '课程提醒': 'Course reminders',
  '每天 07:30 发送当日课程摘要': 'Send today’s course summary at 07:30',
  '仅在当天有课时发送；课表更新或账号变更后会自动重排。': 'Sent only on days with courses; rescheduled after account or schedule changes.',
  '生活信息与 DDL': 'Daily information and deadlines',
  '在空教室联动查询上方显示默认折叠的今日、明日天气。': 'Show a collapsed today/tomorrow weather card above linked classroom search.',
  '在月视图日期详情中显示农历、干支与宜忌。': 'Show lunar date, pillars, and suitable/avoid advice in month details.',
  '在统一 DDL 卡片中显示 Contest DDL 收录的公开学科竞赛截止日期。': 'Show public academic competition deadlines from Contest DDL.',
  '由脚本从学校内部网站公开通知页提取整理，并在统一 DDL 卡片中显示。': 'Show notices extracted by script from public pages on the university’s internal website.',
  '在统一 DDL 卡片中显示夏令营截止日期。': 'Show summer-camp deadlines in the combined deadline card.',
  '在统一 DDL 卡片中显示黑客松截止日期。': 'Show hackathon deadlines in the combined deadline card.',
  '天气、黄历与 DDL 卡片底部会分别标明第三方数据来源；学科竞赛和脚本提取的校内竞赛通知由独立开关控制。': 'Weather, almanac, and deadline cards identify their third-party sources. Academic competitions and script-extracted school notices have separate switches.',
  '显示数据仅供参考，请以实际情况为准。': 'Displayed data is for reference only; rely on official information.',
  '本地数据': 'Local data',
  '清除已保存的教务账户与密码、个人课表、空教室和节假日缓存，并恢复本地设置。': 'Remove saved academic credentials, schedules, classroom and holiday caches, and reset local preferences.',
  '清除本地数据': 'Clear local data',
  '清除全部本地数据？': 'Clear all local data?',
  '将删除保存的账号、密码、个人课表、空教室缓存和设置。此操作无法撤销。': 'This removes saved credentials, schedules, classroom caches, and settings. This cannot be undone.',
  '取消': 'Cancel',
  '确认清除': 'Clear now',
  '关于本应用': 'About',
  'Where To Study 是独立开发的非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。': 'Where To Study is an independently developed, unofficial client. It is not operated by BUPT and does not represent the university.',
  '隐私说明': 'Privacy policy',
  'GitHub 项目': 'GitHub project',
  '界面语言': 'Interface language',
  '跟随系统': 'System default',
  '简体中文': 'Simplified Chinese',
  'English': 'English',
  '休': 'Off',
  '班': 'Work',
  '作': 'A',
  '赛': 'C',
  '试': 'Exam',
  '已生成日历文件并打开苹果日历：': 'Calendar file created and opened in Apple Calendar: ',
  '移动教务实时接口': 'Mobile academic system live API',
  'Jraaay 公共实时数据': 'Jraaay public live data',
  '微信教务实时接口': 'WeChat academic system live API',
  '数据参考提示': 'Data disclaimer',
  '校内竞赛通知由脚本从学校内部网站公开通知页提取整理，仅供参考。': 'School competition notices are extracted by script from public pages on the university’s internal website and are for reference only.',
  '备用：': 'Backup: ',
  '校内：': 'School: ',
  '竞赛通知 API': 'School notice API',
  '（本次已使用备用源）': ' (backup source used)',
  'UAPI 农历': 'UAPI Lunar Calendar',
  'Timeless 万年历': 'Timeless Calendar',
  '黄历宜忌': 'Almanac advice',
  '云课堂作业截止': 'UCloud assignment deadlines',
  '竞赛与活动截止': 'Competition and event deadlines',
  '请先在设置中保存教务账号和密码。': 'Save your academic-system account and password in Settings first.',
  '自动获取当天空教室失败。': 'Automatic loading of today’s empty classrooms failed.',
  '空教室更新的账号作用域无效，已拒绝显示。': 'The empty-classroom result used an invalid account scope and was rejected.',
  '窗口已隐藏，应用仍在系统托盘运行。': 'The window is hidden; the app is still running in the system tray.',
})

function translator(language) {
  return (text, values = {}) => {
    const template = language === 'en' ? (EN_TEXT[text] || text) : text
    return Object.entries(values).reduce(
      (result, [key, value]) => result.replaceAll(`{${key}}`, String(value)),
      template,
    )
  }
}

const BROWSER_PREVIEW_ENABLED = import.meta.env.DEV
const PROJECT_URL = 'https://github.com/Nemoyuzx/where_to_study'
const DEADLINE_PREFETCH_RETRY_MS = 30 * 1000
const DEADLINE_SOURCE_REFRESH_MS = 5 * 60 * 1000 + 1000
const PRIVACY_POLICY_URL = 'https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md'
const PRIVACY_SECTIONS = [
  {
    title: '账户与教务请求 / Account and academic requests',
    body: '学号和密码保存在操作系统的受保护凭据存储中，仅在你请求课表、空教室或作业时按对应用途通过 HTTPS 使用。课表和空教室请求发送到 jwglweixin.bupt.edu.cn；平台允许时还可能自动刷新当天空教室。维护者无法读取凭据，设置接口也不会返回密码。\n\nCredentials stay in protected OS storage and are used over HTTPS only for requested schedules, classrooms, or assignments. Schedule and classroom requests go to jwglweixin.bupt.edu.cn; supported platforms may refresh today’s classrooms automatically. The maintainer cannot read credentials, and settings APIs never return a password.',
  },
  {
    title: '本地数据 / Local data',
    body: '课表、空教室、校区、学期和功能开关缓存在设备上；受支持系统上的课程小组件只读取本地课表快照。“清除本地数据”会移除凭据、缓存、偏好和应用管理的提醒。\n\nSchedules, classroom results, campus, term, and preferences are cached locally. Course widgets on supported systems read only a local schedule snapshot. “Clear local data” removes credentials, caches, preferences, and app-managed reminders.',
  },
  {
    title: '节假日数据 / Holiday data',
    body: '应用可能通过 unpkg 获取固定版本 holiday-calendar 的中国法定节假日和调休数据；Android 在已有权限时也可能读取系统节假日日历。请求仅含 CN 与年份。iOS 只依据权威休息日数据显示“休”，不会把所有节日名称都当作休息日。\n\nThe app may retrieve pinned holiday-calendar data through unpkg; Android may also read the OS holiday calendar when permitted. Requests contain only CN and year. iOS marks rest days only from authoritative rest-day data, not from every festival name.',
  },
  {
    title: '天气、黄历与公开活动 / Weather, almanac, and public events',
    body: 'UAPI 按所选校区对应行政区提供天气与基础黄历，不读取 GPS；Timeless 可补充宜忌。Contest DDL 提供竞赛、夏令营和黑客松，校内竞赛通知由服务器脚本从学校内部网站公开通知页提取整理。各类别均有独立开关。固定 HTTP API 仅接收无凭据 GET，拒绝重定向且不含个人数据。所有显示数据仅供参考。\n\nUAPI provides district-level campus weather and base almanac data without GPS; Timeless may add advice. Contest DDL provides competitions, summer camps, and hackathons. School notices are extracted by a server-side script from public pages on the university’s internal website. Each category has its own switch. Fixed HTTP APIs receive only credential-free GET requests with no personal data and reject redirects. Displayed data is for reference only.',
  },
  {
    title: '云课堂作业 / UCloud assignments',
    body: '应用仅把密码通过 HTTPS 提交给 auth.bupt.edu.cn 完成统一认证，再用一次性票据换取内存令牌并从 apiucloud.bupt.edu.cn 读取作业。应用不读取浏览器 Cookie，不向 UCloud API 发送密码，也不把票据、Cookie、令牌或作业写入磁盘；结果最多在内存复用 10 分钟。\n\nThe password is submitted only to auth.bupt.edu.cn over HTTPS. A one-time ticket is exchanged for an in-memory token used with apiucloud.bupt.edu.cn. The app reads no browser cookies, sends no password to UCloud APIs, persists no ticket, cookie, token, or assignment, and reuses results in memory for at most ten minutes.',
  },
  {
    title: '系统日历、通知与小组件 / Calendar, notifications, and widgets',
    body: '只有在你主动操作并授予权限后，应用才会写入系统日历或安排本地课程通知；只管理带 Where To Study 标记的事件。课程小组件只在支持的平台提供。相关数据不上传给维护者。\n\nCalendar writes and local course notifications require your action and permission, and only marked events are managed. Course widgets exist only on supported platforms. This data is not uploaded to the maintainer.',
  },
  {
    title: '不收集的数据与第三方元数据 / Data not collected and third-party metadata',
    body: '项目不运营应用后端，不含广告、分析或行为跟踪 SDK，也不收集 GPS、联系人、广告标识符、诊断或使用行为。所连接的第三方服务可能按各自政策处理 IP 和请求时间等普通网络元数据。\n\nThe project operates no app backend and collects no GPS, contacts, advertising identifiers, diagnostics, or usage behavior. Connected third parties may process ordinary network metadata such as IP address and request time under their own policies.',
  },
  {
    title: '保留与删除 / Retention and deletion',
    body: '凭据与缓存保留在设备上，直到被替换、清除或随卸载移除；清除本地数据不会删除学校或第三方持有的记录。\n\nCredentials and caches stay on your device until replaced, cleared, or removed with the app. Clearing local data does not delete records held by BUPT or third parties.',
  },
  {
    title: '安全与联系 / Security and contact',
    body: '请按 SECURITY.md 报告安全问题；隐私问题可在 GitHub 提交不含敏感信息的 Issue。请勿公开账号、密码、令牌、个人课表或其他敏感数据。\n\nFollow SECURITY.md for security reports. Privacy questions may be opened as non-sensitive GitHub issues. Never publish accounts, passwords, tokens, personal schedules, or other sensitive data.',
  },
]

function PrivacyPolicyDialog({ onClose }) {
  const closeButtonRef = useRef(null)
  const dialogRef = useRef(null)

  useEffect(() => {
    const closeOnEscape = (event) => {
      if (event.key === 'Escape') onClose()
    }
    const trapFocus = (event) => {
      // Keep keyboard focus inside the dialog (Windows Tab navigation).
      if (event.key !== 'Tab' || !dialogRef.current) return
      const focusable = dialogRef.current.querySelectorAll(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
      )
      if (!focusable.length) return
      const first = focusable[0]
      const last = focusable[focusable.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }
    window.addEventListener('keydown', closeOnEscape)
    window.addEventListener('keydown', trapFocus)
    closeButtonRef.current?.focus()
    return () => {
      window.removeEventListener('keydown', closeOnEscape)
      window.removeEventListener('keydown', trapFocus)
    }
  }, [onClose])

  return (
    <div
      className="privacy-dialog-backdrop"
      onMouseDown={(event) => {
        if (event.button !== 0) return
        if (event.target === event.currentTarget) onClose()
      }}
    >
      <section
        ref={dialogRef}
        className="privacy-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="privacy-dialog-title"
      >
        <header className="privacy-dialog-header">
          <div>
            <p className="eyebrow">Where To Study</p>
            <h2 id="privacy-dialog-title">隐私声明 / Privacy Policy</h2>
            <span>生效日期 / Effective date: 2026-08-23</span>
          </div>
          <button ref={closeButtonRef} type="button" onClick={onClose} aria-label="关闭隐私声明" title="关闭">
            <X size={20} />
          </button>
        </header>

        <div className="privacy-dialog-body">
          <p>Where To Study 是用于查看北京邮电大学个人课表、空教室及相关学习信息的独立非官方客户端，不由学校运营，也不代表学校官方立场。<br /><br />Where To Study is an independent, unofficial client for BUPT schedules, empty classrooms, and related study information. It is not operated by or affiliated with BUPT.</p>
          {PRIVACY_SECTIONS.map((section) => (
            <section key={section.title}>
              <h3>{section.title}</h3>
              {section.body.split('\n\n').map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
            </section>
          ))}
        </div>

        <footer className="privacy-dialog-footer">
          <a href={PRIVACY_POLICY_URL} target="_blank" rel="noreferrer">
            在 GitHub 查看完整声明 / Full policy on GitHub
            <ExternalLink size={16} />
          </a>
        </footer>
      </section>
    </div>
  )
}

function hasTauriRuntime() {
  return typeof window !== 'undefined' && Boolean(window.__TAURI_INTERNALS__?.invoke)
}

function browserPreviewCommand(name, payload = {}) {
  const year = payload.year || new Date().getFullYear()
  if (name === 'get_metadata') {
    return {
      campuses: [{ id: '01', name: '西土城' }, { id: '04', name: '沙河' }],
      slots: FALLBACK_SLOTS,
      default_term_id: DEFAULT_SETTINGS.termId,
      default_term_start_date: DEFAULT_SETTINGS.termStartDate,
      supports_calendar_import: false,
    }
  }
  if (name === 'load_saved_settings') {
    return {
      account: DEFAULT_SETTINGS.account,
      has_saved_password: false,
      term_id: DEFAULT_SETTINGS.termId,
      term_start_date: DEFAULT_SETTINGS.termStartDate,
      campus_id: DEFAULT_SETTINGS.campusId,
      default_min_seats: DEFAULT_SETTINGS.defaultMinSeats,
      ui_language: DEFAULT_SETTINGS.uiLanguage,
      daily_course_notifications_enabled: DEFAULT_SETTINGS.dailyCourseNotificationsEnabled,
      automatic_term_detection_enabled: DEFAULT_SETTINGS.automaticTermDetectionEnabled,
      weather_enabled: DEFAULT_SETTINGS.weatherEnabled,
      almanac_enabled: DEFAULT_SETTINGS.almanacEnabled,
      competition_deadlines_enabled: DEFAULT_SETTINGS.competitionDeadlinesEnabled,
      school_contest_notices_enabled: DEFAULT_SETTINGS.schoolContestNoticesEnabled,
      summer_camp_deadlines_enabled: DEFAULT_SETTINGS.summerCampDeadlinesEnabled,
      hackathon_deadlines_enabled: DEFAULT_SETTINGS.hackathonDeadlinesEnabled,
    }
  }
  if (name === 'save_saved_settings') {
    return {
      account: payload.account || '',
      has_saved_password: Boolean(payload.password),
      term_id: payload.term_id || DEFAULT_SETTINGS.termId,
      term_start_date: payload.term_start_date || DEFAULT_SETTINGS.termStartDate,
      campus_id: payload.campus_id || DEFAULT_SETTINGS.campusId,
      default_min_seats: Number(payload.default_min_seats) || 0,
      ui_language: payload.ui_language || 'system',
      daily_course_notifications_enabled: Boolean(payload.daily_course_notifications_enabled),
      automatic_term_detection_enabled: Boolean(payload.automatic_term_detection_enabled),
      weather_enabled: Boolean(payload.weather_enabled),
      almanac_enabled: Boolean(payload.almanac_enabled),
      competition_deadlines_enabled: Boolean(payload.competition_deadlines_enabled),
      school_contest_notices_enabled: Boolean(payload.school_contest_notices_enabled),
      summer_camp_deadlines_enabled: Boolean(payload.summer_camp_deadlines_enabled),
      hackathon_deadlines_enabled: Boolean(payload.hackathon_deadlines_enabled),
    }
  }
  if (
    name === 'load_saved_schedule'
    || name === 'load_saved_schedule_for_scope'
    || name === 'load_saved_classrooms'
    || name === 'load_saved_classrooms_for_scope'
  ) {
    return null
  }
  if (name === 'fetch_holidays') {
    return {
      year,
      source: 'browser-preview',
      fetched_at: contractTimestamp(),
      items: fallbackHolidayItems(year),
    }
  }
  if (name === 'fetch_classrooms') {
    return {
      cache_version: 2,
      target_date: localDateString(),
      fetched_at: contractTimestamp(),
      realtime: true,
      provider: 'browser-preview',
      campuses: [
        {
          campus_id: '01',
          campus_name: '西土城',
          target_date: localDateString(),
          fetched_at: contractTimestamp(),
          realtime: true,
          provider: 'browser-preview',
          rooms: [],
        },
        {
          campus_id: '04',
          campus_name: '沙河',
          target_date: localDateString(),
          fetched_at: contractTimestamp(),
          realtime: true,
          provider: 'browser-preview',
          rooms: [],
        },
      ],
    }
  }
  if (name === 'fetch_schedule') {
    return {
      term_id: DEFAULT_SETTINGS.termId,
      term_start_date: DEFAULT_SETTINGS.termStartDate,
      fetched_at: contractTimestamp(),
      courses: [],
    }
  }
  if (name === 'import_schedule_to_calendar') {
    throw new Error('手机浏览器预览不支持导入苹果日历，请在 macOS App 中使用。')
  }
  if (name === 'fetch_weather') {
    const campusId = payload.campus_id || '01'
    const campusName = campusId === '04' ? '沙河' : '西土城'
    const district = campusId === '04' ? '昌平区' : '海淀区'
    const today = localDateString()
    const tomorrow = addDays(today, 1)
    return {
      campus_id: campusId,
      campus_name: campusName,
      district,
      current_weather: '多云',
      current_temperature: 27,
      report_time: '刚刚发布',
      source: 'https://uapis.cn',
      days: [
        { date: today, weekday: '今天', weather_day: '多云', weather_night: '雷阵雨', temp_max: 32, temp_min: 23, precipitation_probability: 40 },
        { date: tomorrow, weekday: '明天', weather_day: '晴', weather_night: '多云', temp_max: 33, temp_min: 22, precipitation_probability: 10 },
      ],
    }
  }
  if (name === 'fetch_almanac') {
    return {
      date: payload.date,
      weekday: '星期六',
      lunar_date: '七月初十',
      ganzhi_year: '丙午',
      ganzhi_month: '丙申',
      ganzhi_day: '戊辰',
      zodiac: '马',
      solar_term: null,
      lunar_festival: null,
      solar_festival: null,
      yi: '祭祀 祈福 出行',
      ji: '嫁娶 掘井',
      source: 'https://uapis.cn',
    }
  }
  if (name === 'fetch_deadlines') {
    return {
      date: payload.date,
      fetched_at: contractTimestamp(),
      source: 'https://nemoyuzx.github.io/contest-ddl/data/competitions.json',
      used_backup: false,
      items: [
        { id: 'preview-competition', name: '大学生创新竞赛', event_type: 'competition', source_type: 'contest_ddl', primary_deadline: `${payload.date}T18:00:00+08:00`, organizer: '示例组委会', official_url: 'https://nemoyuzx.github.io/contest-ddl/' },
        { id: 'preview-school-notice', name: '校内学科竞赛通知示例', event_type: 'competition', source_type: 'school_notice', primary_deadline: `${payload.date}T20:00:00+08:00`, organizer: '北京邮电大学教学云平台 · 校内截止', official_url: 'https://ucloud.bupt.edu.cn/#/consulting?tab=1' },
        { id: 'preview-hackathon', name: '校园黑客松', event_type: 'hackathon', source_type: 'contest_ddl', primary_deadline: `${payload.date}T23:59:59+08:00`, organizer: null, official_url: 'https://nemoyuzx.github.io/contest-ddl/' },
      ],
    }
  }
  if (name === 'fetch_deadline_calendar') {
    const startDate = payload.start_date
    const secondDate = addDays(startDate, 1)
    return {
      start_date: startDate,
      end_date: payload.end_date,
      fetched_at: contractTimestamp(),
      source: 'https://nemoyuzx.github.io/contest-ddl/data/competitions.json',
      used_backup: false,
      items: [
        { id: 'preview-school-notice-range', name: '校内学科竞赛通知示例', event_type: 'competition', source_type: 'school_notice', primary_deadline: `${startDate}T20:00:00+08:00`, organizer: '北京邮电大学教学云平台 · 校内截止', official_url: 'https://ucloud.bupt.edu.cn/#/consulting?tab=1' },
        { id: 'preview-school-notice-range-2', name: '校内创新项目通知示例', event_type: 'competition', source_type: 'school_notice', primary_deadline: `${startDate}T21:00:00+08:00`, organizer: '北京邮电大学教学云平台 · 校内截止', official_url: 'https://ucloud.bupt.edu.cn/#/consulting?tab=1' },
        { id: 'preview-competition-range', name: '大学生创新竞赛', event_type: 'competition', source_type: 'contest_ddl', primary_deadline: `${secondDate}T18:00:00+08:00`, organizer: '示例组委会', official_url: 'https://nemoyuzx.github.io/contest-ddl/' },
      ],
    }
  }
  if (name === 'fetch_assignments') {
    return {
      date: payload.date,
      source: 'https://ucloud.bupt.edu.cn/uclass/',
      items: [],
      unavailable_reason: '浏览器预览不连接个人云课堂作业。',
    }
  }
  if (name === 'fetch_assignment_calendar') {
    return {
      start_date: payload.start_date,
      end_date: payload.end_date,
      source: 'https://ucloud.bupt.edu.cn/uclass/',
      items: [
        { id: 'preview-assignment-range', title: '课程作业示例', course_name: '示例课程', deadline: `${payload.start_date}T23:59:00+08:00`, status: '未提交' },
      ],
    }
  }
  if (name === 'clear_local_data') {
    return true
  }
  if (name === 'set_interface_language') {
    return true
  }
  return null
}

function PlannerSummary({ dayCoursesCount, freeSlotsCount, matchingRoomsCount, className = '', t }) {
  return (
    <section className={`summary-band ${className}`.trim()}>
      <div>
        <span>{t('当天课程')}</span>
        <strong>{dayCoursesCount}</strong>
      </div>
      <div>
        <span>{t('个人空闲节次')}</span>
        <strong>{freeSlotsCount}</strong>
      </div>
      <div>
        <span>{t('匹配教室')}</span>
        <strong>{matchingRoomsCount}</strong>
      </div>
    </section>
  )
}

function WeatherGlyph({ weather, size = 22 }) {
  const text = String(weather || '')
  if (/雷/.test(text)) return <CloudLightning size={size} />
  if (/雪|冰|冻/.test(text)) return <CloudSnow size={size} />
  if (/雨/.test(text)) return <CloudRain size={size} />
  if (/雾|霾|沙|尘/.test(text)) return <CloudFog size={size} />
  if (/多云|阴/.test(text)) return <Cloud size={size} />
  return <Sun size={size} />
}

function WeatherStrip({ weather, loading, error, onRetry, language, t }) {
  const [expanded, setExpanded] = useState(false)

  return (
    <section className="weather-strip" aria-label={t('校区天气')}>
      <button
        type="button"
        className="weather-strip-toggle"
        aria-expanded={expanded}
        aria-controls="weather-strip-details"
        onClick={() => setExpanded((value) => !value)}
      >
        <WeatherGlyph weather={weather?.current_weather} size={20} />
        <div className="weather-strip-heading">
          <span>{t('校区天气')}</span>
          <strong>{weather ? `${weather.campus_name} · ${weather.district}` : t('今日与明日')}</strong>
        </div>
        {weather ? <small>{weather.current_weather} {weather.current_temperature}° · {weather.report_time}</small> : null}
        <ChevronDown className="weather-strip-chevron" size={18} aria-hidden="true" />
      </button>
      {expanded ? (
        <div className="weather-strip-details" id="weather-strip-details">
          {loading ? (
            <div className="weather-strip-state"><Loader2 className="spin" size={18} /> {t('正在更新天气…')}</div>
          ) : error ? (
            <button type="button" className="weather-strip-state weather-retry" onClick={onRetry}>
              <AlertTriangle size={17} /> {t(error)} · {t('点击重试')}
            </button>
          ) : (
            <div className="weather-days">
              {(weather?.days || []).map((day, index) => (
                <article key={day.date}>
                  <WeatherGlyph weather={day.weather_day} />
                  <div>
                    <strong>{index === 0 ? t('今日') : t('明日')} · {formatShortDate(day.date)}</strong>
                    <span>{day.weather_day}{day.weather_night !== day.weather_day ? `${language === 'en' ? ' to ' : '转'}${day.weather_night}` : ''}</span>
                  </div>
                  <b>{day.temp_min}° / {day.temp_max}°</b>
                  {day.precipitation_probability != null ? <small>{t('降水')} {day.precipitation_probability}%</small> : null}
                </article>
              ))}
            </div>
          )}
          <a href="https://uapis.cn/docs/api-reference/get-misc-weather" target="_blank" rel="noreferrer">{t('数据：UAPI')}</a>
        </div>
      ) : null}
    </section>
  )
}

function SelectedDaySchedule({ date, weekState, slotMeta, language, t }) {
  return (
    <section className="panel selected-day-schedule">
      <div className="panel-title selected-day-title">
        <CalendarDays size={18} />
        <div>
          <h2>{formatUiCourseDate(date, language)}</h2>
          <span>{formatUiTeachingWeek(weekState.weekNumber, language)} · {language === 'en' ? `${weekState.dayCourses.length} courses` : `${weekState.dayCourses.length} 门课`}</span>
        </div>
      </div>
      <div className="selected-day-course-list">
        {weekState.dayCourses.length ? weekState.dayCourses.map((course) => {
          const bounds = courseTimeBounds(course, slotMeta)
          return (
            <article key={`${date}-${course.id}`}>
              <time>{bounds.start}</time>
              <div>
                <strong><CourseName course={course} t={t} /></strong>
                <span>{bounds.start}-{bounds.end} · {course.room || t('地点未标注')}</span>
              </div>
            </article>
          )
        }) : <div className="empty-state">{t('当天没有课程')}</div>}
      </div>
    </section>
  )
}

function AlmanacCard({ date, almanac, loading, error, onRetry, t }) {
  const festival = [almanac?.solar_term, almanac?.lunar_festival, almanac?.solar_festival]
    .filter(Boolean)
    .join(' · ')
  return (
    <section className="panel almanac-card" aria-label={`${date} ${t('黄历信息')}`}>
      <div className="panel-title">
        <CalendarRange size={18} />
        <h2>{t('黄历信息')}</h2>
      </div>
      {loading ? (
        <div className="almanac-state"><Loader2 className="spin" size={18} /> {t('正在查询…')}</div>
      ) : error ? (
        <button type="button" className="almanac-state almanac-retry" onClick={onRetry}>
          <AlertTriangle size={17} /> {t(error)} · {t('点击重试')}
        </button>
      ) : almanac ? (
        <div className="almanac-content">
          <div className="almanac-date">
            <span>{almanac.weekday}</span>
            <strong>{t('农历')} {almanac.lunar_date}</strong>
            {festival ? <small>{festival}</small> : null}
          </div>
          <div className="almanac-grid">
            <div><span>{t('岁次')}</span><strong>{almanac.ganzhi_year}年 · 肖{almanac.zodiac}</strong></div>
            <div><span>{t('月柱')}</span><strong>{almanac.ganzhi_month}月</strong></div>
            <div><span>{t('日柱')}</span><strong>{almanac.ganzhi_day}日</strong></div>
          </div>
          <div className="almanac-advice" aria-label={t('黄历宜忌')}>
            <div className="almanac-yi"><strong>{t('宜：')}</strong><span>{almanac.yi || t('暂无数据')}</span></div>
            <div className="almanac-ji"><strong>{t('忌：')}</strong><span>{almanac.ji || t('暂无数据')}</span></div>
          </div>
        </div>
      ) : null}
      <p>
        {t('民俗信息仅供参考 · 数据：')}
        <a href="https://uapis.cn/docs/api-reference/get-misc-lunartime" target="_blank" rel="noreferrer">{t('UAPI 农历')}</a>
        {' · '}
        <a href="https://api.timelessq.com/docs/api-15277838" target="_blank" rel="noreferrer">{t('Timeless 万年历')}</a>
      </p>
    </section>
  )
}

const DEADLINE_TYPE_META = {
  competition: { label: '学科竞赛', Icon: Trophy },
  summer_camp: { label: '夏令营', Icon: TentTree },
  hackathon: { label: '黑客松', Icon: Code2 },
}

function deadlineClock(value, fallback = '时间待定') {
  const match = String(value || '').match(/^\d{4}-\d{2}-\d{2}T(\d{2}:\d{2})/)
  return match?.[1] || fallback
}

function datesInRange(startDate, endDate) {
  const dates = []
  let current = startDate
  while (current <= endDate && dates.length < 370) {
    dates.push(current)
    current = addDays(current, 1)
  }
  return dates
}

function datePart(value) {
  return String(value || '').slice(0, 10)
}

function formatUiCalendarTitle(dateString, view, language) {
  if (language !== 'en') return formatCalendarTitle(dateString, view)
  const date = dateFromString(dateString)
  if (view === 'year') return String(date.getFullYear())
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric',
    month: view === 'day' ? 'short' : 'long',
    ...(view === 'day' ? { day: 'numeric' } : {}),
  }).format(date)
}

function formatUiCourseDate(dateString, language) {
  if (language !== 'en') return formatCourseDate(dateString)
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  }).format(dateFromString(dateString))
}

function formatUiTeachingWeek(weekNumber, language) {
  if (language !== 'en') return formatTeachingWeek(weekNumber)
  return weekNumber > 0 ? `Teaching week ${weekNumber}` : 'Outside teaching weeks'
}

function AssignmentDeadlineCard({ date, response, loading, error, onRetry, t }) {
  return (
    <section className="panel assignment-deadline-card" aria-label={`${date} ${t('云课堂作业截止')}`}>
      <div className="panel-title">
        <ClipboardList size={18} />
        <h2>{t('课程作业 DDL')}</h2>
      </div>
      {loading ? (
        <div className="deadline-state"><Loader2 className="spin" size={18} /> {t('正在同步云课堂作业…')}</div>
      ) : error ? (
        <button type="button" className="deadline-state deadline-retry" onClick={onRetry}>
          <AlertTriangle size={17} /> {t(error)} · {t('点击重试')}
        </button>
      ) : response?.items?.length ? (
        <div className="deadline-list">
          {response.items.map((item) => (
            <article key={item.id}>
              <div>
                <strong>{item.title}</strong>
                <span>{item.course_name || t('课程名称未标注')}{item.status ? ` · ${item.status}` : ''}</span>
              </div>
              <time>{deadlineClock(item.deadline, t('时间待定'))}</time>
            </article>
          ))}
        </div>
      ) : (
        <div className="deadline-empty">{response?.unavailable_reason || t('当天没有课程作业截止')}</div>
      )}
      <p>{t('第三方来源')}：<a href="https://ucloud.bupt.edu.cn/uclass/" target="_blank" rel="noreferrer">{t('北京邮电大学云邮教学空间')}</a></p>
    </section>
  )
}

function ContestDeadlineCard({ date, response, loading, error, enabledTypes, onRetry, t }) {
  const items = (response?.items || []).filter((item) => (
    item.source_type === 'school_notice'
      ? enabledTypes.school_notice
      : enabledTypes[item.event_type]
  ))
  return (
    <section className="panel contest-deadline-card" aria-label={`${date} ${t('竞赛与活动截止')}`}>
      <div className="panel-title">
        <Trophy size={18} />
        <h2>{t('竞赛与活动 DDL')}</h2>
      </div>
      {loading ? (
        <div className="deadline-state"><Loader2 className="spin" size={18} /> {t('正在更新实时 DDL…')}</div>
      ) : error ? (
        <button type="button" className="deadline-state deadline-retry" onClick={onRetry}>
          <AlertTriangle size={17} /> {t(error)} · {t('点击重试')}
        </button>
      ) : items.length ? (
        <div className="deadline-list">
          {items.map((item) => {
            const meta = item.source_type === 'school_notice'
              ? { label: t('校内竞赛通知'), Icon: Trophy }
              : DEADLINE_TYPE_META[item.event_type] || DEADLINE_TYPE_META.competition
            const ItemIcon = meta.Icon
            const body = (
              <>
                <ItemIcon size={17} />
                <div>
                  <strong>{item.name}</strong>
                  <span>{t(meta.label)}{item.organizer ? ` · ${item.organizer}` : ''}</span>
                </div>
                <time>{deadlineClock(item.primary_deadline, t('时间待定'))}</time>
              </>
            )
            return item.official_url ? (
              <a key={item.id} href={item.official_url} target="_blank" rel="noreferrer">{body}</a>
            ) : <article key={item.id}>{body}</article>
          })}
        </div>
      ) : (
        <div className="deadline-empty">{t('当天没有已启用类型的报名或提交截止')}</div>
      )}
      <p>
        {t('校内竞赛通知由脚本从学校内部网站公开通知页提取整理，仅供参考。')}{' '}
        {t('第三方来源')}：
        <a href="https://nemoyuzx.github.io/contest-ddl/" target="_blank" rel="noreferrer">Contest DDL</a>
        {' · '}{t('备用：')}
        <a href="http://101.201.29.29/api/contest-events" target="_blank" rel="noreferrer">contest-events API</a>
        {' · '}{t('校内：')}
        <a href="http://101.201.29.29/api/contest-notices" target="_blank" rel="noreferrer">{t('竞赛通知 API')}</a>
        {response?.used_backup ? t('（本次已使用备用源）') : ''}
      </p>
    </section>
  )
}

function CourseName({ course, t }) {
  return (
    <span className="course-name-with-badge">
      {course.is_exam ? <em className="course-exam-badge">{t('试')}</em> : null}
      <span>{course.name}</span>
    </span>
  )
}

async function command(name, payload) {
  if (!hasTauriRuntime()) {
    if (!BROWSER_PREVIEW_ENABLED) {
      throw new Error('应用后端未连接，请从安装后的桌面应用启动。')
    }
    return browserPreviewCommand(name, payload)
  }

  try {
    if (payload === undefined) return await invoke(name)
    return await invoke(name, { payload })
  } catch (error) {
    const commandError = new Error(normalizeError(error))
    commandError.accountScopeCleared = Boolean(error?.account_scope_cleared)
    throw commandError
  }
}

function App() {
  const [activePage, setActivePage] = useState('planner')
  const [metadata, setMetadata] = useState({
    campuses: [],
    slots: FALLBACK_SLOTS,
    supports_calendar_import: false,
  })
  const [settings, setSettings] = useState(() => ({ ...DEFAULT_SETTINGS }))
  const uiLanguage = resolvedUiLanguage(settings.uiLanguage, navigator.languages?.[0] || navigator.language)
  const t = useMemo(() => translator(uiLanguage), [uiLanguage])
  const uiWeekdayLabels = uiLanguage === 'en'
    ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    : CALENDAR_WEEKDAYS
  const [queryCampusId, setQueryCampusId] = useState(DEFAULT_SETTINGS.campusId)
  const [calendarDate, setCalendarDate] = useState(localDateString())
  const [calendarView, setCalendarView] = useState('week')
  const [calendarMotion, setCalendarMotion] = useState('')
  const [monthExpanded, setMonthExpanded] = useState(true)
  const [calendarAgendaDialog, setCalendarAgendaDialog] = useState(null)
  const [compactCalendarLayout, setCompactCalendarLayout] = useState(
    () => window.matchMedia('(max-width: 720px)').matches,
  )
  const [schedule, setSchedule] = useState(null)
  const [classroomsCache, setClassroomsCache] = useState(null)
  const [classroomsCacheLoaded, setClassroomsCacheLoaded] = useState(false)
  const [selectedSlots, setSelectedSlots] = useState([])
  const [selectedBuildings, setSelectedBuildings] = useState([])
  const [minSeats, setMinSeats] = useState(0)
  const [usePersonalSchedule, setUsePersonalSchedule] = useState(true)
  const [calendarPopover, setCalendarPopover] = useState(null)
  const [holidayDataByYear, setHolidayDataByYear] = useState(() => ({
    2026: {
      year: 2026,
      source: 'fallback',
      fetched_at: '',
      items: fallbackHolidayItems(2026),
    },
  }))
  const [now, setNow] = useState(() => new Date())
  const [loadingTasks, setLoadingTasks] = useState([])
  const [error, setError] = useState('')
  const [settingsSaved, setSettingsSaved] = useState(false)
  const [settingsSaving, setSettingsSaving] = useState(false)
  const [settingsLoaded, setSettingsLoaded] = useState(false)
  const [calendarImportedPath, setCalendarImportedPath] = useState('')
  const [clearConfirmationOpen, setClearConfirmationOpen] = useState(false)
  const [privacyPolicyOpen, setPrivacyPolicyOpen] = useState(false)
  const [weather, setWeather] = useState(null)
  const [weatherLoading, setWeatherLoading] = useState(false)
  const [weatherError, setWeatherError] = useState('')
  const [almanacByDate, setAlmanacByDate] = useState({})
  const [almanacLoadingDate, setAlmanacLoadingDate] = useState('')
  const [almanacErrorByDate, setAlmanacErrorByDate] = useState({})
  const [deadlinesByDate, setDeadlinesByDate] = useState({})
  const [deadlinesLoadingDate, setDeadlinesLoadingDate] = useState('')
  const [deadlinesErrorByDate, setDeadlinesErrorByDate] = useState({})
  const [assignmentsByDate, setAssignmentsByDate] = useState({})
  const [assignmentsLoadingDate, setAssignmentsLoadingDate] = useState('')
  const [assignmentsErrorByDate, setAssignmentsErrorByDate] = useState({})
  const autoFetchedClassroomsDate = useRef('')
  const calendarPopoverRef = useRef(null)
  const calendarGestureRef = useRef(null)
  const calendarTransitionHostRef = useRef(null)
  const calendarAnimatedSurfaceRef = useRef(null)
  const calendarOutgoingSurfaceRef = useRef(null)
  const calendarMotionTimerRef = useRef(null)
  const monthExpansionTimerRef = useRef(null)
  const suppressCalendarClickUntilRef = useRef(0)
  const pageContentRef = useRef(null)
  const requestedHolidayYears = useRef(new Set())
  const savedCredentialState = useRef({ account: '', hasSavedPassword: false })
  const credentialStateRevision = useRef(0)
  const localDataClearRevision = useRef(0)
  const privacyTriggerRef = useRef(null)
  const yearClickTimerRef = useRef(null)
  const clearCancelButtonRef = useRef(null)
  const weatherRevisionRef = useRef(0)
  const almanacRevisionRef = useRef(0)
  const deadlinesRevisionRef = useRef(0)
  const assignmentsRevisionRef = useRef(0)
  const requestedCalendarSupplementRanges = useRef(new Set())
  const deadlineCoveredDatesRef = useRef(new Set())
  const deadlinePreheatPromiseRef = useRef(null)
  const deadlinePreheatTimerRef = useRef(null)
  const deadlinePreheatEnabledRef = useRef(false)
  const deadlineSourceReadyRef = useRef(false)

  const calendarSupplementRange = useMemo(() => {
    if (calendarView === 'day') return { startDate: calendarDate, endDate: calendarDate }
    if (calendarView === 'week') {
      const startDate = startOfWeekMonday(calendarDate)
      return { startDate, endDate: addDays(startDate, 6) }
    }
    if (calendarView === 'month') {
      const days = buildMonthDays(calendarDate)
      return { startDate: days[0], endDate: days[days.length - 1] }
    }
    const year = dateFromString(calendarDate).getFullYear()
    return { startDate: `${year}-01-01`, endDate: `${year}-12-31` }
  }, [calendarDate, calendarView])

  useEffect(() => {
    document.documentElement.lang = uiLanguage === 'en' ? 'en' : 'zh-Hans'
    void command('set_interface_language', uiLanguage).catch(() => {})
  }, [uiLanguage])

  useEffect(() => {
    const page = pageContentRef.current
    if (!page) return undefined
    page.addEventListener('touchmove', updateCalendarSwipe, { passive: false })
    return () => {
      page.removeEventListener('touchmove', updateCalendarSwipe)
      page.classList.remove('calendar-gesture-locked')
    }
  }, [activePage])

  // Trackpad/mouse-wheel horizontal swipe navigation for desktop WebView2
  // (Windows). macOS touchpads also produce horizontal wheel events.
  useEffect(() => {
    const page = pageContentRef.current
    if (!page) return undefined

    let wheelAccumulator = 0
    let wheelTimer = null
    const WHEEL_THRESHOLD = 120
    const WHEEL_RESET_MS = 400

    function handleCalendarWheel(event) {
      // Only handle horizontal wheel events (trackpad horizontal swipe)
      if (Math.abs(event.deltaX) < Math.abs(event.deltaY) * 1.5) return
      // Don't intercept when interacting with form elements
      if (event.target.closest('input, select, textarea, a')) return
      // Don't intercept when popover is open
      if (calendarPopover) return

      wheelAccumulator += event.deltaX
      window.clearTimeout(wheelTimer)

      if (Math.abs(wheelAccumulator) >= WHEEL_THRESHOLD) {
        const direction = wheelAccumulator > 0 ? 1 : -1
        wheelAccumulator = 0
        suppressCalendarClickUntilRef.current = Date.now() + 400
        moveCalendar(direction)
      }

      wheelTimer = window.setTimeout(() => {
        wheelAccumulator = 0
      }, WHEEL_RESET_MS)
    }

    // Only add wheel listener when on calendar page
    if (activePage === 'calendar') {
      page.addEventListener('wheel', handleCalendarWheel, { passive: true })
    }

    return () => {
      page.removeEventListener('wheel', handleCalendarWheel)
      window.clearTimeout(wheelTimer)
    }
  }, [activePage, calendarView, calendarPopover])
  const todayDate = shanghaiDateString(now)
  const todayYear = todayDate.slice(0, 4)
  const loading = loadingTasks[loadingTasks.length - 1] || ''

  useEffect(() => {
    const query = window.matchMedia('(max-width: 720px)')
    const updateLayout = () => setCompactCalendarLayout(query.matches)
    updateLayout()
    query.addEventListener('change', updateLayout)
    return () => query.removeEventListener('change', updateLayout)
  }, [])

  useEffect(() => {
    pageContentRef.current?.scrollTo({ top: 0, left: 0, behavior: 'auto' })
  }, [activePage])

  useLayoutEffect(() => {
    if (activePage !== 'calendar' || calendarView !== 'month' || !compactCalendarLayout) {
      return undefined
    }
    const clearAvailableHeight = () => {
      const page = pageContentRef.current
      page?.style.removeProperty('--month-expanded-height')
      page?.style.removeProperty('--month-expanded-row-height')
    }
    const updateAvailableHeight = () => {
      const page = pageContentRef.current
      const surface = calendarAnimatedSurfaceRef.current
      if (!page || !surface) return
      const pageBounds = page.getBoundingClientRect()
      const surfaceBounds = surface.getBoundingClientRect()
      const mainBounds = surface.closest('.teaching-calendar-main')?.getBoundingClientRect()
      const trailingSpace = Math.max(0, (mainBounds?.bottom || surfaceBounds.bottom) - surfaceBounds.bottom)
      const pageBottomPadding = Number.parseFloat(getComputedStyle(page).paddingBottom) || 0
      const available = Math.max(
        320,
        Math.min(
          page.clientHeight - pageBottomPadding,
          pageBounds.bottom - pageBottomPadding - surfaceBounds.top - trailingSpace,
        ),
      )
      const handleHeight = 28
      const monthMetrics = expandedMonthGridMetrics(Math.max(0, available - handleHeight))
      const collapsedHeight = 368
      page.style.setProperty(
        '--month-expanded-height',
        `${Math.max(collapsedHeight, monthMetrics.height + handleHeight)}px`,
      )
      page.style.setProperty('--month-expanded-row-height', `${monthMetrics.rowHeight}px`)
    }
    updateAvailableHeight()
    let resizeFrame = 0
    const handleResize = () => {
      window.cancelAnimationFrame(resizeFrame)
      resizeFrame = window.requestAnimationFrame(updateAvailableHeight)
    }
    window.addEventListener('resize', handleResize)
    return () => {
      window.removeEventListener('resize', handleResize)
      window.cancelAnimationFrame(resizeFrame)
      clearAvailableHeight()
    }
  }, [activePage, calendarDate, calendarMotion, calendarView, compactCalendarLayout])

  useEffect(() => () => {
    window.clearTimeout(monthExpansionTimerRef.current)
    window.clearTimeout(yearClickTimerRef.current)
    deadlinePreheatEnabledRef.current = false
    window.clearTimeout(deadlinePreheatTimerRef.current)
  }, [])

  useEffect(() => {
    if (clearConfirmationOpen) {
      clearCancelButtonRef.current?.focus()
    }
  }, [clearConfirmationOpen])

  useEffect(() => {
    command('get_metadata')
      .then((data) => {
        setMetadata(data)
        setSettings((current) => ({
          ...current,
          termId: current.termId || data.default_term_id,
          termStartDate: current.termStartDate || data.default_term_start_date,
          campusId: current.campusId || data.campuses[0]?.id || '01',
        }))
      })
      .catch(() => {
        setMetadata({
          campuses: [{ id: '01', name: '西土城' }],
          slots: FALLBACK_SLOTS,
          supports_calendar_import: false,
        })
      })
  }, [])

  useEffect(() => {
    let cancelled = false
    const revision = credentialStateRevision.current
    const clearRevision = localDataClearRevision.current

    command('load_saved_settings')
      .then((data) => {
        if (cancelled) return
        if (clearRevision !== localDataClearRevision.current) {
          setSettingsLoaded(true)
          return
        }
        const nextSettings = savedSettingsToState(data)
        const savedCredential = savedCredentialSnapshot(nextSettings)
        savedCredentialState.current = savedCredential
        if (revision === credentialStateRevision.current) {
          setSettings(nextSettings)
          setQueryCampusId(nextSettings.campusId)
          setMinSeats(Number(nextSettings.defaultMinSeats) || 0)
        } else {
          setSettings((current) => ({
            ...current,
            hasSavedPassword: accountHasSavedPassword(current.account, savedCredential),
          }))
        }
        setSettingsLoaded(true)
      })
      .catch((loadError) => {
        if (!cancelled) {
          setError(loadError.message)
          setSettingsLoaded(true)
        }
      })

    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    return () => {
      window.clearTimeout(calendarMotionTimerRef.current)
      calendarOutgoingSurfaceRef.current?.remove()
    }
  }, [])

  useEffect(() => {
    if (!hasTauriRuntime()) return undefined

    let unlistenNavigate = null
    let unlistenHideNotice = null

    listen('tray:navigate', (event) => {
      if (['planner', 'calendar', 'settings'].includes(event.payload)) {
        setActivePage(event.payload)
      }
    }).then((dispose) => {
      unlistenNavigate = dispose
    })

    listen('tray:hide-notice', (event) => {
      setError(String(event.payload || '窗口已隐藏，应用仍在系统托盘运行。'))
    }).then((dispose) => {
      unlistenHideNotice = dispose
    })

    return () => {
      if (unlistenNavigate) unlistenNavigate()
      if (unlistenHideNotice) unlistenHideNotice()
    }
  }, [])

  useEffect(() => {
    if (!hasTauriRuntime()) return undefined

    let unlistenFetched = null
    let unlistenError = null

    listen('classrooms:auto-fetched', (event) => {
      const accountScope = event.payload?.account_scope
      if (!isValidAccountScope(accountScope)) {
        setClassroomsCache(null)
        setError('空教室更新的账号作用域无效，已拒绝显示。')
        return
      }
      const accountDataRevision = localDataClearRevision.current
      command('load_saved_classrooms_for_scope', { account_scope: accountScope })
        .then((data) => {
          if (accountDataRevision !== localDataClearRevision.current) return
          const nextCache = normalizeClassroomsCache(data)
          if (nextCache) setClassroomsCache(nextCache)
        })
        .catch(() => {
          if (accountDataRevision === localDataClearRevision.current) {
            setClassroomsCache(null)
          }
        })
    }).then((dispose) => {
      unlistenFetched = dispose
    })

    listen('classrooms:auto-fetch-error', (event) => {
      const message = typeof event.payload === 'string' ? event.payload : '自动获取当天空教室失败。'
      setError(message)
    }).then((dispose) => {
      unlistenError = dispose
    })

    return () => {
      if (unlistenFetched) unlistenFetched()
      if (unlistenError) unlistenError()
    }
  }, [])

  useEffect(() => {
    const timer = window.setTimeout(
      () => setNow(new Date()),
      msUntilNextShanghaiMidnight(),
    )
    return () => window.clearTimeout(timer)
  }, [todayDate])

  useEffect(() => {
    if (!settings.weatherEnabled) {
      weatherRevisionRef.current += 1
      setWeather(null)
      setWeatherLoading(false)
      setWeatherError('')
      return undefined
    }
    void loadWeather(queryCampusId)
    return () => {
      weatherRevisionRef.current += 1
    }
  }, [queryCampusId, settings.weatherEnabled, todayDate])

  useEffect(() => {
    if (activePage !== 'calendar' || calendarView !== 'month' || !settings.almanacEnabled) return undefined
    void loadAlmanac(calendarDate)
    return () => {
      almanacRevisionRef.current += 1
    }
  }, [activePage, calendarDate, calendarView, settings.almanacEnabled])

  useEffect(() => {
    const plan = settingsLoaded
      ? deadlinePreheatPlan(settings, `${todayYear}-01-01`)
      : null
    deadlinePreheatEnabledRef.current = Boolean(plan)
    window.clearTimeout(deadlinePreheatTimerRef.current)
    if (!plan) return undefined

    void preheatDeadlineCalendar(plan)
    return () => window.clearTimeout(deadlinePreheatTimerRef.current)
  }, [
    settings.competitionDeadlinesEnabled,
    settings.hackathonDeadlinesEnabled,
    settings.schoolContestNoticesEnabled,
    settings.summerCampDeadlinesEnabled,
    settingsLoaded,
    todayYear,
  ])

  useEffect(() => {
    if (activePage !== 'calendar' || !settingsLoaded) return
    const anyDeadlineTypeEnabled = settings.competitionDeadlinesEnabled
      || settings.schoolContestNoticesEnabled
      || settings.summerCampDeadlinesEnabled
      || settings.hackathonDeadlinesEnabled
    void loadCalendarSupplements(
      calendarSupplementRange.startDate,
      calendarSupplementRange.endDate,
      anyDeadlineTypeEnabled,
    )
  }, [
    activePage,
    calendarSupplementRange.endDate,
    calendarSupplementRange.startDate,
    settingsLoaded,
    settings.competitionDeadlinesEnabled,
    settings.hackathonDeadlinesEnabled,
    settings.schoolContestNoticesEnabled,
    settings.summerCampDeadlinesEnabled,
  ])

  useEffect(() => {
    const todayVisible = calendarView === 'day'
      ? calendarDate === todayDate
      : calendarView === 'week'
        && startOfWeekMonday(calendarDate) === startOfWeekMonday(todayDate)
    if (activePage !== 'calendar' || !todayVisible) {
      return undefined
    }

    setNow(new Date())
    const timer = window.setInterval(() => setNow(new Date()), 60000)
    return () => window.clearInterval(timer)
  }, [activePage, calendarDate, calendarView, todayDate])

  useEffect(() => {
    if (!calendarPopover) return undefined

    const closePopover = (event) => {
      // Only a primary (left) click outside should dismiss; right-click
      // (context menu) and middle-click must not close the popover.
      if (event.button !== 0) return
      if (calendarPopoverRef.current?.contains(event.target)) {
        return
      }
      setCalendarPopover(null)
    }

    window.addEventListener('pointerdown', closePopover)
    return () => window.removeEventListener('pointerdown', closePopover)
  }, [calendarPopover])

  const slotMeta = metadata.slots?.length ? metadata.slots : FALLBACK_SLOTS
  const courses = useMemo(() => (schedule ? schedule.courses : []), [schedule])
  const activeTermStartDate = schedule?.term_start_date || settings.termStartDate
  const calendarHolidayItems = useMemo(
    () => Object.values(holidayDataByYear).flatMap((data) => data.items || []),
    [holidayDataByYear],
  )
  const calendarDayMap = useMemo(
    () => buildCalendarDayMap(calendarHolidayItems),
    [calendarHolidayItems],
  )
  const calendarItemsFor = (dateString) => calendarDayMap.get(dateString) || []
  const schoolNoticeItemsFor = (dateString) => settings.schoolContestNoticesEnabled
    ? (deadlinesByDate[dateString]?.items || []).filter((item) => item.source_type === 'school_notice')
    : []
  const supplementalEntriesFor = (dateString) => [
    ...(assignmentsByDate[dateString]?.items || []).map((item) => ({
      key: `assignment-${item.id}-${item.deadline}`,
      type: 'assignment',
      label: item.title,
      subtitle: item.course_name || '',
      time: deadlineClock(item.deadline, t('时间待定')),
    })),
    ...schoolNoticeItemsFor(dateString).map((item) => ({
      key: `school-notice-${item.id}-${item.primary_deadline}`,
      type: 'school-notice',
      label: item.name,
      subtitle: item.organizer || '',
      time: deadlineClock(item.primary_deadline, t('时间待定')),
      url: item.official_url || '',
    })),
  ]
  const allDayEntriesFor = (dateString) => [
    ...calendarItemsFor(dateString).map((item) => ({
      key: `calendar-${item.type}-${item.name}`,
      type: item.type,
      label: `${t(item.type === 'holiday' ? '休' : '班')} ${item.name}`,
      subtitle: '',
      time: '',
    })),
    ...supplementalEntriesFor(dateString),
  ]
  const plannerWeekState = useMemo(
    () => getWeekState(courses, activeTermStartDate, todayDate),
    [courses, activeTermStartDate, todayDate],
  )
  const classrooms = useMemo(
    () => getCampusClassrooms(classroomsCache, queryCampusId),
    [classroomsCache, queryCampusId],
  )
  const calendarWeekState = useMemo(
    () => getWeekState(courses, activeTermStartDate, calendarDate),
    [courses, activeTermStartDate, calendarDate],
  )
  const busySlots = useMemo(
    () => (usePersonalSchedule ? plannerWeekState.busySlots : []),
    [usePersonalSchedule, plannerWeekState.busySlots],
  )
  const freeSlots = useMemo(
    () => slotMeta.map((slot) => slot.index).filter((slot) => !busySlots.includes(slot)),
    [busySlots, slotMeta],
  )
  const buildings = useMemo(() => {
    const configuredBuildings = buildingsForCampus(queryCampusId)
    if (configuredBuildings.length) return configuredBuildings
    const names = [...new Set((classrooms?.rooms || []).map((room) => room.building))]
    return names.sort((a, b) => a.localeCompare(b, 'zh-Hans-CN'))
  }, [classrooms, queryCampusId])
  const filteredRooms = useMemo(() => {
    return (classrooms?.rooms || [])
      .filter((room) => !selectedBuildings.length || selectedBuildings.includes(room.building))
      .filter((room) => !room.size || room.size >= minSeats)
      .filter((room) => selectedSlots.length > 0 && selectedSlots.every((slot) => room.available_slots.includes(slot)))
      .sort((a, b) => a.building.localeCompare(b.building, 'zh-Hans-CN') || a.room.localeCompare(b.room, 'zh-Hans-CN'))
  }, [classrooms, minSeats, selectedBuildings, selectedSlots])
  const selectedRanges = slotsToRanges(selectedSlots, slotMeta)
  const needsBuildingSelection = buildings.length > 0 && selectedBuildings.length === 0
  const needsSlotSelection = selectedBuildings.length > 0 && selectedSlots.length === 0
  const calendarHours = useMemo(
    () => Array.from({ length: CALENDAR_END_HOUR - CALENDAR_START_HOUR + 1 }, (_, index) => CALENDAR_START_HOUR + index),
    [],
  )
  const visibleCalendarDays = useMemo(() => {
    if (calendarView === 'day') return [calendarDate]
    if (calendarView === 'week') {
      const start = startOfWeekMonday(calendarDate)
      return Array.from({ length: 7 }, (_, index) => addDays(start, index))
    }
    if (calendarView === 'month') return buildMonthDays(calendarDate)
    return []
  }, [calendarDate, calendarView])
  const visibleHolidayYears = useMemo(() => {
    const dates = calendarView === 'year' ? [calendarDate] : visibleCalendarDays
    return [...new Set(dates.map((dateString) => dateFromString(dateString).getFullYear()))]
  }, [calendarDate, calendarView, visibleCalendarDays])
  const calendarYearMonths = useMemo(() => {
    const year = dateFromString(calendarDate).getFullYear()
    return Array.from({ length: 12 }, (_, monthIndex) => ({
      monthIndex,
      label: uiLanguage === 'en'
        ? new Intl.DateTimeFormat('en-US', { month: 'long' }).format(new Date(year, monthIndex, 1))
        : `${monthIndex + 1}月`,
      days: buildMiniMonthDays(year, monthIndex),
    }))
  }, [calendarDate, uiLanguage])
  const calendarDetailCourse = calendarWeekState.dayCourses[0] || null
  const calendarHeaderTitle = calendarView === 'week'
    ? `${formatUiCalendarTitle(calendarDate, calendarView, uiLanguage)} · ${formatUiTeachingWeek(calendarWeekState.weekNumber, uiLanguage)}`
    : formatUiCalendarTitle(calendarDate, calendarView, uiLanguage)
  const visibleAllDayItems = useMemo(
    () => visibleCalendarDays.reduce(
      (count, dateString) => count
        + (calendarDayMap.get(dateString) || []).length
        + (assignmentsByDate[dateString]?.items || []).length
        + (settings.schoolContestNoticesEnabled
          ? (deadlinesByDate[dateString]?.items || []).filter((item) => item.source_type === 'school_notice').length
          : 0),
      0,
    ),
    [assignmentsByDate, calendarDayMap, deadlinesByDate, settings.schoolContestNoticesEnabled, visibleCalendarDays],
  )
  const calendarPopoverState = useMemo(() => (
    calendarPopover
      ? getWeekState(courses, activeTermStartDate, calendarPopover.date)
      : null
  ), [activeTermStartDate, calendarPopover, courses])
  const currentTimeLine = useMemo(() => {
    // Show the time line when today is visible: day view always, week view
    // when the current week includes today (matches the native clients).
    const todayVisible = calendarView === 'day'
      ? calendarDate === todayDate
      : calendarView === 'week' && visibleCalendarDays.includes(todayDate)
    if (!todayVisible) return null
    const minutes = now.getHours() * 60 + now.getMinutes()
    const visibleStart = CALENDAR_START_HOUR * 60
    const visibleEnd = CALENDAR_END_HOUR * 60
    if (minutes < visibleStart || minutes > visibleEnd) return null
    return {
      label: `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`,
      top: ((minutes - visibleStart) / (visibleEnd - visibleStart)) * 100,
    }
  }, [calendarDate, calendarView, now, todayDate, visibleCalendarDays])

  useEffect(() => {
    visibleHolidayYears.forEach((year) => {
      if (requestedHolidayYears.current.has(year)) return
      requestedHolidayYears.current.add(year)

      command('fetch_holidays', { year })
        .then((data) => {
          setHolidayDataByYear((current) => ({
            ...current,
            [data.year]: data,
          }))
        })
        .catch(() => {
          setHolidayDataByYear((current) => {
            if (current[year]) return current
            return {
              ...current,
              [year]: {
                year,
                source: 'fallback',
                fetched_at: '',
                items: fallbackHolidayItems(year),
              },
            }
          })
        })
    })
  }, [visibleHolidayYears])

  useEffect(() => {
    let cancelled = false
    const accountDataRevision = localDataClearRevision.current

    command('load_saved_classrooms')
      .then((data) => {
        if (cancelled || accountDataRevision !== localDataClearRevision.current) return
        const nextCache = normalizeClassroomsCache(data)
        if (nextCache && nextCache.target_date === todayDate) {
          setClassroomsCache(nextCache)
        }
      })
      .catch((loadError) => {
        if (!cancelled && accountDataRevision === localDataClearRevision.current) {
          setError(loadError.message)
        }
      })
      .finally(() => {
        if (!cancelled) setClassroomsCacheLoaded(true)
      })

    return () => {
      cancelled = true
    }
  }, [todayDate])

  useEffect(() => {
    if (settingsSaving || !settingsLoaded || !classroomsCacheLoaded || autoFetchedClassroomsDate.current === todayDate) {
      return
    }
    if (classroomsCache?.target_date === todayDate) {
      autoFetchedClassroomsDate.current = todayDate
      return
    }
    if (!settings.account.trim() || !settings.hasSavedPassword) return

    autoFetchedClassroomsDate.current = todayDate
    void loadClassrooms().then((succeeded) => {
      // Allow a later retry when the fetch fails.
      if (!succeeded) autoFetchedClassroomsDate.current = ''
    })
  }, [classroomsCache, classroomsCacheLoaded, settings.account, settings.hasSavedPassword, settingsLoaded, settingsSaving, todayDate])

  useEffect(() => {
    let cancelled = false
    const accountDataRevision = localDataClearRevision.current

    command('load_saved_schedule')
      .then((data) => {
        if (!cancelled && accountDataRevision === localDataClearRevision.current && data) {
          setSchedule(data)
        }
      })
      .catch((loadError) => {
        if (!cancelled && accountDataRevision === localDataClearRevision.current) {
          setError(loadError.message)
        }
      })

    return () => {
      cancelled = true
    }
  }, [])

  function updateSetting(field, value) {
    setSettingsSaved(false)
    if (field === 'account' || field === 'password') {
      credentialStateRevision.current += 1
    }
    setSettings((current) => {
      const next = { ...current, [field]: value }
      if (field === 'account') {
        const saved = savedCredentialState.current
        next.hasSavedPassword = accountHasSavedPassword(value, saved)
      }
      return next
    })
  }

  async function saveCurrentSettings() {
    if (settingsSaving || !settingsLoaded) return
    setError('')
    setSettingsSaved(false)
    setSettingsSaving(true)
    const revision = credentialStateRevision.current
    const clearRevision = localDataClearRevision.current
    const previousSavedCredential = { ...savedCredentialState.current }

    try {
      const data = await command('save_saved_settings', settingsToPayload(settings))
      const nextSettings = savedSettingsToState(data, settings)
      if (clearRevision !== localDataClearRevision.current) return
      const savedCredential = savedCredentialSnapshot(nextSettings)
      const accountChanged = previousSavedCredential.account !== savedCredential.account
      savedCredentialState.current = savedCredential
      if (accountChanged) {
        localDataClearRevision.current += 1
        clearAccountScopedViewState()
      }
      if (revision !== credentialStateRevision.current) {
        setSettings((current) => ({
          ...current,
          hasSavedPassword: accountHasSavedPassword(current.account, savedCredential),
        }))
        return
      }
      setSettings(nextSettings)
      setMinSeats(Number(nextSettings.defaultMinSeats) || 0)
      setSelectedBuildings([])
      setSettingsSaved(true)
    } catch (saveError) {
      if (saveError.accountScopeCleared) {
        credentialStateRevision.current += 1
        localDataClearRevision.current += 1
        clearAccountScopedViewState()
        try {
          const persisted = await command('load_saved_settings')
          const recoveredSettings = savedSettingsToState(persisted)
          savedCredentialState.current = savedCredentialSnapshot(recoveredSettings)
          setSettings(recoveredSettings)
          setMinSeats(Number(recoveredSettings.defaultMinSeats) || 0)
        } catch {
          savedCredentialState.current = { account: '', hasSavedPassword: false }
          setSettings({ ...DEFAULT_SETTINGS })
          setMinSeats(0)
        }
      }
      setError(saveError.message)
    } finally {
      setSettingsSaving(false)
    }
  }

  function toggleSlot(slotIndex) {
    setSelectedSlots((current) => (
      current.includes(slotIndex)
        ? current.filter((slot) => slot !== slotIndex)
        : [...current, slotIndex].sort((a, b) => a - b)
    ))
  }

  function toggleBuilding(building) {
    setSelectedBuildings((current) => (
      current.includes(building)
        ? current.filter((item) => item !== building)
        : [...current, building]
    ))
  }

  function togglePersonalSchedule() {
    const nextValue = !usePersonalSchedule
    setUsePersonalSchedule(nextValue)
    if (nextValue) {
      setSelectedSlots((current) => current.filter((slot) => !plannerWeekState.busySlots.includes(slot)))
    } else {
      setSelectedSlots((current) => (
        [...new Set([...current, ...plannerWeekState.busySlots])].sort((a, b) => a - b)
      ))
    }
  }

  function chooseCalendarDate(dateString) {
    if (Date.now() < suppressCalendarClickUntilRef.current) return
    setCalendarDate(dateString)
    setCalendarPopover(null)
  }

  function chooseCalendarDateFromInput(event) {
    const dateString = event.target.value
    if (!dateString || Number.isNaN(dateFromString(dateString).getTime())) {
      event.target.value = calendarDate
      return
    }
    chooseCalendarDate(dateString)
  }

  function stageCalendarTransition(motion) {
    const host = calendarTransitionHostRef.current
    const source = calendarAnimatedSurfaceRef.current
    calendarOutgoingSurfaceRef.current?.remove()
    calendarOutgoingSurfaceRef.current = null
    if (!host || !source || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return

    const outgoing = source.cloneNode(true)
    outgoing.classList.remove('calendar-motion-next', 'calendar-motion-previous')
    outgoing.classList.add('calendar-motion-outgoing', `calendar-motion-exit-${motion}`)
    outgoing.setAttribute('aria-hidden', 'true')
    outgoing.inert = true
    outgoing.querySelectorAll('[id]').forEach((element) => element.removeAttribute('id'))
    outgoing.querySelectorAll('button, input, select, textarea, a').forEach((element) => {
      element.tabIndex = -1
    })
    outgoing.style.height = `${source.offsetHeight}px`
    host.append(outgoing)
    outgoing.scrollTop = source.scrollTop
    outgoing.scrollLeft = source.scrollLeft
    calendarOutgoingSurfaceRef.current = outgoing
  }

  function startCalendarMotion(motion) {
    stageCalendarTransition(motion)
    setCalendarMotion(motion)
    window.clearTimeout(calendarMotionTimerRef.current)
    calendarMotionTimerRef.current = window.setTimeout(() => {
      setCalendarMotion('')
      calendarOutgoingSurfaceRef.current?.remove()
      calendarOutgoingSurfaceRef.current = null
    }, 300)
  }

  function moveCalendar(direction) {
    setCalendarPopover(null)
    startCalendarMotion(direction > 0 ? 'next' : 'previous')
    setCalendarDate((current) => shiftDate(current, calendarView, direction))
  }

  function beginCalendarSwipe(event) {
    if (calendarView === 'year' || event.touches.length !== 1) return
    const touch = event.touches[0]
    calendarGestureRef.current = {
      x: touch.clientX,
      y: touch.clientY,
      axis: null,
      view: calendarView,
      monthExpanded,
      scrollTop: pageContentRef.current?.scrollTop || 0,
      scrollLocked: false,
      blocked: Boolean(event.target.closest('input, select, textarea, a, .time-all-day-overflow')),
    }
  }

  // Pointer-based swipe for the day/week calendar: lets Windows/macOS mouse
  // users drag horizontally to page the calendar, matching the touch gesture.
  function beginCalendarPointerSwipe(event) {
    if (calendarView === 'year' || event.isPrimary === false) return
    if (event.pointerType === 'mouse' && event.button !== 0) return
    if (event.target.closest('input, select, textarea, a')) return
    if (event.target.closest('.time-all-day-overflow')) return
    if (event.target.closest('.time-course-block')) return

    calendarGestureRef.current = {
      x: event.clientX,
      y: event.clientY,
      axis: null,
      view: calendarView,
      monthExpanded,
      scrollTop: pageContentRef.current?.scrollTop || 0,
      scrollLocked: false,
      blocked: false,
      pointerId: event.pointerId,
      pointerTarget: event.currentTarget,
    }
    try {
      event.currentTarget.setPointerCapture(event.pointerId)
    } catch {
      // Pointer capture is optional in older embedded WebViews.
    }
  }

  function updateCalendarPointerSwipe(event) {
    const start = calendarGestureRef.current
    if (!start || start.view === 'month' || start.pointerId !== event.pointerId) return
    const deltaX = event.clientX - start.x
    const deltaY = event.clientY - start.y
    if (!start.axis && Math.max(Math.abs(deltaX), Math.abs(deltaY)) >= 8) {
      if (Math.abs(deltaX) > Math.abs(deltaY) * 1.12) start.axis = 'horizontal'
      else if (Math.abs(deltaY) > Math.abs(deltaX) * 1.12) start.axis = 'vertical'
    }

    if (start.axis === 'horizontal') {
      lockCalendarVerticalScroll(start)
      event.preventDefault()
    }
  }

  function finishCalendarPointerSwipe(event) {
    const start = calendarGestureRef.current
    if (!start || start.view === 'month' || start.pointerId !== event.pointerId) return
    calendarGestureRef.current = null
    unlockCalendarVerticalScroll(start)
    try {
      start.pointerTarget.releasePointerCapture(event.pointerId)
    } catch {
      // The browser may release capture before pointerup.
    }

    if (start.axis !== 'horizontal') return
    const deltaX = event.clientX - start.x
    const deltaY = event.clientY - start.y
    const direction = calendarSwipeDirection(deltaX, deltaY)
    if (!direction) return
    suppressCalendarClickUntilRef.current = Date.now() + 400
    moveCalendar(direction)
  }

  function cancelCalendarPointerSwipe(event) {
    const start = calendarGestureRef.current
    if (!start || start.view === 'month' || start.pointerId !== event.pointerId) return
    calendarGestureRef.current = null
    unlockCalendarVerticalScroll(start)
  }

  function lockCalendarVerticalScroll(start) {
    if (!start || start.scrollLocked) return
    start.scrollLocked = true
    pageContentRef.current?.classList.add('calendar-gesture-locked')
  }

  function unlockCalendarVerticalScroll(start) {
    if (!start?.scrollLocked) return
    pageContentRef.current?.classList.remove('calendar-gesture-locked')
    start.scrollLocked = false
  }

  function monthLength(styles, property, fallback) {
    const value = Number.parseFloat(styles.getPropertyValue(property))
    return Number.isFinite(value) && value > 0 ? value : fallback
  }

  function monthDragGeometry(surface) {
    const styles = window.getComputedStyle(surface)
    const collapsedHeight = monthLength(styles, '--month-collapsed-height', 440)
    const expandedHeight = Math.max(
      collapsedHeight,
      monthLength(styles, '--month-expanded-height', 776),
    )
    const collapsedRowHeight = monthLength(styles, '--month-collapsed-row-height', 62)
    const expandedRowHeight = Math.max(
      collapsedRowHeight,
      monthLength(styles, '--month-expanded-row-height', 118),
    )
    const travelDistance = Math.max(1, expandedHeight - collapsedHeight)
    const currentHeight = surface.getBoundingClientRect().height
    const currentProgress = Math.max(
      0,
      Math.min(1, (currentHeight - collapsedHeight) / travelDistance),
    )
    return {
      surface,
      collapsedHeight,
      expandedHeight,
      collapsedRowHeight,
      expandedRowHeight,
      travelDistance,
      currentProgress,
    }
  }

  function applyMonthDragVisual(geometry, progress) {
    const normalized = Math.max(0, Math.min(1, progress))
    const height = geometry.collapsedHeight
      + (geometry.expandedHeight - geometry.collapsedHeight) * normalized
    const rowHeight = geometry.collapsedRowHeight
      + (geometry.expandedRowHeight - geometry.collapsedRowHeight) * normalized
    const { surface } = geometry
    surface.classList.remove('month-settling')
    surface.classList.add('month-dragging')
    surface.style.height = `${height}px`
    surface.style.maxHeight = `${height}px`
    surface.style.setProperty('--month-live-row-height', `${rowHeight}px`)
    surface.style.setProperty('--month-drag-progress', String(normalized))
    surface.style.setProperty('--month-handle-left-angle', `${-24 * normalized}deg`)
    surface.style.setProperty('--month-handle-right-angle', `${24 * normalized}deg`)
    surface.style.setProperty('--month-handle-offset-y', `${2 * normalized}px`)
  }

  function clearMonthDragVisual(surface) {
    if (!surface) return
    surface.classList.remove('month-dragging', 'month-settling')
    surface.style.removeProperty('height')
    surface.style.removeProperty('max-height')
    surface.style.removeProperty('--month-live-row-height')
    surface.style.removeProperty('--month-drag-progress')
    surface.style.removeProperty('--month-handle-left-angle')
    surface.style.removeProperty('--month-handle-right-angle')
    surface.style.removeProperty('--month-handle-offset-y')
  }

  function settleMonthDrag(geometry, progress, expanded) {
    const normalized = Math.max(0, Math.min(1, progress))
    const targetProgress = expanded ? 1 : 0
    const currentHeight = geometry.collapsedHeight
      + (geometry.expandedHeight - geometry.collapsedHeight) * normalized
    const targetHeight = expanded ? geometry.expandedHeight : geometry.collapsedHeight
    const currentRowHeight = geometry.collapsedRowHeight
      + (geometry.expandedRowHeight - geometry.collapsedRowHeight) * normalized
    const targetRowHeight = expanded
      ? geometry.expandedRowHeight
      : geometry.collapsedRowHeight
    const { surface } = geometry

    window.clearTimeout(monthExpansionTimerRef.current)
    surface.classList.remove('month-dragging')
    surface.classList.add('month-settling')
    surface.style.height = `${currentHeight}px`
    surface.style.maxHeight = `${currentHeight}px`
    surface.style.setProperty('--month-live-row-height', `${currentRowHeight}px`)
    surface.style.setProperty('--month-drag-progress', String(normalized))
    surface.style.setProperty('--month-handle-left-angle', `${-24 * normalized}deg`)
    surface.style.setProperty('--month-handle-right-angle', `${24 * normalized}deg`)
    surface.style.setProperty('--month-handle-offset-y', `${2 * normalized}px`)
    void surface.offsetHeight
    setMonthExpanded(expanded)

    window.requestAnimationFrame(() => {
      if (!surface.isConnected) return
      surface.style.height = `${targetHeight}px`
      surface.style.maxHeight = `${targetHeight}px`
      surface.style.setProperty('--month-live-row-height', `${targetRowHeight}px`)
      surface.style.setProperty('--month-drag-progress', String(targetProgress))
      surface.style.setProperty('--month-handle-left-angle', `${-24 * targetProgress}deg`)
      surface.style.setProperty('--month-handle-right-angle', `${24 * targetProgress}deg`)
      surface.style.setProperty('--month-handle-offset-y', `${2 * targetProgress}px`)
      monthExpansionTimerRef.current = window.setTimeout(() => {
        clearMonthDragVisual(surface)
      }, 300)
    })
  }

  function beginMonthPointerSwipe(event) {
    if (!compactCalendarLayout || calendarView !== 'month' || event.isPrimary === false) return
    if (event.pointerType === 'mouse' && event.button !== 0) return
    const target = event.target instanceof Element ? event.target : null
    if (target?.closest('input, select, textarea, a')) return
    if (target?.closest('.month-expansion-handle, .month-expansion-accessibility-action')) return

    const surface = event.currentTarget
    window.clearTimeout(monthExpansionTimerRef.current)
    const geometry = monthDragGeometry(surface)
    applyMonthDragVisual(geometry, geometry.currentProgress)
    calendarGestureRef.current = {
      x: event.clientX,
      y: event.clientY,
      axis: null,
      view: 'month',
      monthExpanded,
      geometry,
      progress: geometry.currentProgress,
      velocityY: 0,
      lastY: event.clientY,
      lastTime: event.timeStamp,
      scrollLocked: false,
      pointerId: event.pointerId,
      pointerTarget: surface,
    }
    try {
      surface.setPointerCapture(event.pointerId)
    } catch {
      // Pointer capture is optional in older embedded WebViews.
    }
  }

  function updateMonthPointerSwipe(event) {
    const start = calendarGestureRef.current
    if (!start || start.view !== 'month' || start.pointerId !== event.pointerId) return
    const deltaX = event.clientX - start.x
    const deltaY = event.clientY - start.y
    if (!start.axis && Math.max(Math.abs(deltaX), Math.abs(deltaY)) >= 8) {
      if (Math.abs(deltaX) > Math.abs(deltaY) * 1.12) start.axis = 'horizontal'
      else if (Math.abs(deltaY) > Math.abs(deltaX) * 1.12) start.axis = 'vertical'
    }

    if (start.axis === 'horizontal') {
      lockCalendarVerticalScroll(start)
      event.preventDefault()
      return
    }
    if (start.axis !== 'vertical') return

    const elapsed = event.timeStamp - start.lastTime
    if (elapsed > 0) start.velocityY = (event.clientY - start.lastY) / elapsed
    start.lastY = event.clientY
    start.lastTime = event.timeStamp
    start.progress = calendarMonthDragProgress(
      start.geometry.currentProgress,
      deltaY,
      start.geometry.travelDistance,
    )
    applyMonthDragVisual(start.geometry, start.progress)
    lockCalendarVerticalScroll(start)
    event.preventDefault()
  }

  function finishMonthPointerSwipe(event) {
    const start = calendarGestureRef.current
    if (!start || start.view !== 'month' || start.pointerId !== event.pointerId) return
    calendarGestureRef.current = null
    unlockCalendarVerticalScroll(start)
    try {
      start.pointerTarget.releasePointerCapture(event.pointerId)
    } catch {
      // The browser may release capture before pointerup.
    }

    const deltaX = event.clientX - start.x
    const deltaY = event.clientY - start.y
    if (start.axis === 'horizontal') {
      clearMonthDragVisual(start.geometry.surface)
      const direction = calendarSwipeDirection(deltaX, deltaY)
      if (!direction) return
      suppressCalendarClickUntilRef.current = Date.now() + 400
      moveCalendar(direction)
      return
    }
    if (start.axis !== 'vertical') {
      clearMonthDragVisual(start.geometry.surface)
      return
    }

    const releaseVelocity = event.timeStamp - start.lastTime > 80 ? 0 : start.velocityY
    const expanded = calendarMonthExpansionTarget(start.progress, releaseVelocity)
    suppressCalendarClickUntilRef.current = Date.now() + 400
    settleMonthDrag(start.geometry, start.progress, expanded)
  }

  function cancelMonthPointerSwipe(event) {
    const start = calendarGestureRef.current
    if (!start || start.view !== 'month' || start.pointerId !== event.pointerId) return
    calendarGestureRef.current = null
    unlockCalendarVerticalScroll(start)
    settleMonthDrag(start.geometry, start.progress, start.monthExpanded)
  }

  function updateCalendarSwipe(event) {
    const start = calendarGestureRef.current
    if (!start || start.blocked || event.touches.length !== 1) return
    const touch = event.touches[0]
    const deltaX = touch.clientX - start.x
    const deltaY = touch.clientY - start.y
    if (!start.axis && Math.max(Math.abs(deltaX), Math.abs(deltaY)) >= 10) {
      if (Math.abs(deltaX) > Math.abs(deltaY) * 1.12) start.axis = 'horizontal'
      else if (Math.abs(deltaY) > Math.abs(deltaX) * 1.12) start.axis = 'vertical'
    }
    if (start.axis === 'horizontal') {
      lockCalendarVerticalScroll(start)
      if (event.cancelable) event.preventDefault()
    }
    if (start.axis === 'vertical' && start.view === 'month') {
      const expanded = calendarMonthExpansion(deltaX, deltaY)
      const canToggle = expanded !== null
        && expanded !== start.monthExpanded
        && (!expanded || start.scrollTop <= 1)
      if (canToggle) {
        lockCalendarVerticalScroll(start)
        if (event.cancelable) event.preventDefault()
      }
    }
  }

  function finishCalendarSwipe(event) {
    const start = calendarGestureRef.current
    calendarGestureRef.current = null
    unlockCalendarVerticalScroll(start)
    if (!start || start.blocked || event.changedTouches.length !== 1) return
    const touch = event.changedTouches[0]
    const deltaX = touch.clientX - start.x
    const deltaY = touch.clientY - start.y
    const direction = calendarSwipeDirection(deltaX, deltaY)
    if (!direction && calendarView === 'month') {
      const expanded = calendarMonthExpansion(deltaX, deltaY)
      if (expanded === null || expanded === monthExpanded) return
      if (expanded && start.scrollTop > 1) return
      suppressCalendarClickUntilRef.current = Date.now() + 400
      setMonthExpanded(expanded)
      return
    }
    if (!direction) return
    suppressCalendarClickUntilRef.current = Date.now() + 400
    moveCalendar(direction)
  }

  function cancelCalendarSwipe() {
    unlockCalendarVerticalScroll(calendarGestureRef.current)
    calendarGestureRef.current = null
  }

  function handleMonthCalendarKeyDown(event) {
    if (!compactCalendarLayout || calendarView !== 'month') return
    // Left/right move the selected date by one day (Windows keyboard
    // navigation). Up/down keep their collapse/expand meaning and move by
    // a week when the month is already expanded.
    const horizontalOffset = {
      ArrowLeft: -1,
      ArrowRight: 1,
    }[event.key]
    if (horizontalOffset !== undefined) {
      event.preventDefault()
      suppressCalendarClickUntilRef.current = Date.now() + 400
      setCalendarDate((current) => addDays(current, horizontalOffset))
      return
    }
    const wantsExpanded = event.key === 'ArrowDown' ? true : event.key === 'ArrowUp' ? false : null
    if (wantsExpanded === null) return
    event.preventDefault()
    if (wantsExpanded === monthExpanded) {
      // Already in the target state: move by a week instead.
      const weekOffset = wantsExpanded ? 7 : -7
      suppressCalendarClickUntilRef.current = Date.now() + 400
      setCalendarDate((current) => addDays(current, weekOffset))
      return
    }
    setMonthExpanded(wantsExpanded)
  }

  function jumpFromYearPopover(view) {
    const date = calendarPopover?.date
    if (!date) return
    const currentIndex = CALENDAR_VIEWS.findIndex((item) => item.id === calendarView)
    const nextIndex = CALENDAR_VIEWS.findIndex((item) => item.id === view)
    startCalendarMotion(nextIndex >= currentIndex ? 'next' : 'previous')
    setCalendarDate(date)
    setCalendarView(view)
    setCalendarPopover(null)
  }

  function chooseCalendarView(view) {
    if (view === calendarView) return
    const currentIndex = CALENDAR_VIEWS.findIndex((item) => item.id === calendarView)
    const nextIndex = CALENDAR_VIEWS.findIndex((item) => item.id === view)
    startCalendarMotion(nextIndex >= currentIndex ? 'next' : 'previous')
    setCalendarPopover(null)
    setCalendarView(view)
  }

  function openYearDayPopover(event, dateString) {
    const popoverWidth = 300
    const popoverHeight = 340
    const x = Math.min(event.clientX + 12, window.innerWidth - popoverWidth - 12)
    const y = Math.min(event.clientY + 12, window.innerHeight - popoverHeight - 12)
    setCalendarDate(dateString)
    setCalendarPopover({
      date: dateString,
      x: Math.max(12, x),
      y: Math.max(12, y),
    })
  }

  function selectYearDate(event, dateString) {
    // A double-click fires two click events first; defer the single-click
    // action so the desktop double-click (open month view) wins cleanly.
    if (!compactCalendarLayout) {
      const point = { clientX: event.clientX, clientY: event.clientY }
      window.clearTimeout(yearClickTimerRef.current)
      yearClickTimerRef.current = window.setTimeout(() => {
        openYearDayPopover(point, dateString)
      }, 250)
      return
    }
    openYearDayPopover(event, dateString)
  }

  function openDesktopYearMonth(event, dateString) {
    if (compactCalendarLayout) return
    event.preventDefault()
    window.clearTimeout(yearClickTimerRef.current)
    startCalendarMotion('previous')
    setCalendarDate(dateString)
    setCalendarView('month')
    setCalendarPopover(null)
  }

  async function runTask(name, task) {
    setLoadingTasks((current) => [...current, name])
    setError('')
    try {
      await task()
    } catch (taskError) {
      setError(taskError.message)
    } finally {
      setLoadingTasks((current) => current.filter((item) => item !== name))
    }
  }

  async function loadSchedule() {
    if (settingsSaving) return
    await runTask('schedule', async () => {
      const accountDataRevision = localDataClearRevision.current
      const data = await command('fetch_schedule', requestBody(settings, {
        term_id: settings.termId,
        term_start_date: settings.termStartDate,
        automatic_term_detection_enabled: settings.automaticTermDetectionEnabled,
      }))
      if (accountDataRevision !== localDataClearRevision.current) return
      setSchedule(data)
      setCalendarImportedPath('')
      setUsePersonalSchedule(true)
      // Auto-apply the authoritative term info returned by the backend so
      // users never need to hand-enter the semester id or start date.
      if (settings.automaticTermDetectionEnabled && isValidTermId(data.term_id) && isValidTermStartDate(data.term_start_date)) {
        const termChanged = settings.termId !== data.term_id
          || settings.termStartDate !== data.term_start_date
        if (termChanged) {
          const next = {
            ...settings,
            termId: data.term_id,
            termStartDate: data.term_start_date,
          }
          // Keep persistence outside the React state updater. Updaters may run
          // more than once in development, while saving credentials/settings
          // must remain a single, observable operation.
          const persisted = await command('save_saved_settings', settingsToPayload(next))
          if (accountDataRevision !== localDataClearRevision.current) return
          const persistedSettings = savedSettingsToState(persisted, next)
          const persistedCredential = savedCredentialSnapshot(persistedSettings)
          savedCredentialState.current = persistedCredential
          setSettings((current) => ({
            ...current,
            termId: persistedSettings.termId,
            termStartDate: persistedSettings.termStartDate,
            hasSavedPassword: accountHasSavedPassword(current.account, persistedCredential),
          }))
        }
      }
      const nextState = getWeekState(data.courses, data.term_start_date, todayDate)
      const nextFreeSlots = slotMeta.map((slot) => slot.index).filter((slot) => !nextState.busySlots.includes(slot))
      setSelectedSlots(nextFreeSlots)
    })
  }

  async function loadClassrooms() {
    if (settingsSaving) return false
    let succeeded = false
    await runTask('classrooms', async () => {
      const accountDataRevision = localDataClearRevision.current
      const data = await command('fetch_classrooms', requestBody(settings, {
        campus_id: queryCampusId,
        target_date: todayDate,
      }))
      if (accountDataRevision !== localDataClearRevision.current) return
      const nextCache = normalizeClassroomsCache(data)
      if (nextCache) {
        setClassroomsCache(nextCache)
        succeeded = true
      }
    })
    return succeeded
  }

  async function loadWeather(campusId = queryCampusId) {
    const revision = weatherRevisionRef.current + 1
    weatherRevisionRef.current = revision
    setWeatherLoading(true)
    setWeatherError('')
    try {
      const data = await command('fetch_weather', { campus_id: campusId })
      if (revision !== weatherRevisionRef.current) return
      setWeather(data)
    } catch (weatherFetchError) {
      if (revision !== weatherRevisionRef.current) return
      setWeather(null)
      setWeatherError(weatherFetchError.message)
    } finally {
      if (revision === weatherRevisionRef.current) setWeatherLoading(false)
    }
  }

  async function loadAlmanac(date = calendarDate, force = false) {
    if (!force && almanacByDate[date]) return
    const revision = almanacRevisionRef.current + 1
    almanacRevisionRef.current = revision
    setAlmanacLoadingDate(date)
    setAlmanacErrorByDate((current) => ({ ...current, [date]: '' }))
    try {
      const data = await command('fetch_almanac', { date })
      if (revision !== almanacRevisionRef.current) return
      setAlmanacByDate((current) => ({ ...current, [date]: data }))
    } catch (almanacFetchError) {
      if (revision !== almanacRevisionRef.current) return
      setAlmanacErrorByDate((current) => ({ ...current, [date]: almanacFetchError.message }))
    } finally {
      if (revision === almanacRevisionRef.current) setAlmanacLoadingDate('')
    }
  }

  async function loadDeadlines(date = calendarDate, force = false) {
    if (!force && deadlinesByDate[date]) return
    const revision = deadlinesRevisionRef.current + 1
    deadlinesRevisionRef.current = revision
    setDeadlinesLoadingDate(date)
    setDeadlinesErrorByDate((current) => ({ ...current, [date]: '' }))
    try {
      const data = await command('fetch_deadlines', { date })
      if (revision !== deadlinesRevisionRef.current) return
      setDeadlinesByDate((current) => ({ ...current, [date]: data }))
    } catch (deadlineError) {
      if (revision !== deadlinesRevisionRef.current) return
      setDeadlinesErrorByDate((current) => ({ ...current, [date]: deadlineError.message }))
    } finally {
      if (revision === deadlinesRevisionRef.current) setDeadlinesLoadingDate('')
    }
  }

  function applyDeadlineCalendarResponse(startDate, endDate, data) {
    const rangeDates = datesInRange(startDate, endDate)
    const itemsByDate = new Map()
    ;(data?.items || []).forEach((item) => {
      const date = datePart(item.primary_deadline)
      if (!itemsByDate.has(date)) itemsByDate.set(date, [])
      itemsByDate.get(date).push(item)
    })
    rangeDates.forEach((date) => deadlineCoveredDatesRef.current.add(date))
    setDeadlinesByDate((current) => {
      const next = { ...current }
      rangeDates.forEach((date) => {
        next[date] = {
          date,
          fetched_at: data.fetched_at,
          source: data.source,
          used_backup: data.used_backup,
          items: itemsByDate.get(date) || [],
        }
      })
      return next
    })
    setDeadlinesErrorByDate((current) => {
      const next = { ...current }
      rangeDates.forEach((date) => { next[date] = '' })
      return next
    })
  }

  function scheduleDeadlinePreheat(plan, delay) {
    window.clearTimeout(deadlinePreheatTimerRef.current)
    if (!deadlinePreheatEnabledRef.current) return
    deadlinePreheatTimerRef.current = window.setTimeout(() => {
      void preheatDeadlineCalendar(plan)
    }, delay)
  }

  async function preheatDeadlineCalendar(plan) {
    if (!deadlinePreheatEnabledRef.current) return false
    if (deadlinePreheatPromiseRef.current) return deadlinePreheatPromiseRef.current
    const { startDate, endDate } = plan
    const request = command('fetch_deadline_calendar', {
      start_date: startDate,
      end_date: endDate,
    }).then((data) => {
      deadlineSourceReadyRef.current = true
      applyDeadlineCalendarResponse(startDate, endDate, data)
      scheduleDeadlinePreheat(plan, DEADLINE_SOURCE_REFRESH_MS)
      return true
    }).catch(() => {
      scheduleDeadlinePreheat(plan, DEADLINE_PREFETCH_RETRY_MS)
      return false
    }).finally(() => {
      if (deadlinePreheatPromiseRef.current === request) deadlinePreheatPromiseRef.current = null
    })
    deadlinePreheatPromiseRef.current = request
    return request
  }

  async function loadAssignments(date = calendarDate, force = false) {
    if (!force && assignmentsByDate[date]) return
    const revision = assignmentsRevisionRef.current + 1
    assignmentsRevisionRef.current = revision
    setAssignmentsLoadingDate(date)
    setAssignmentsErrorByDate((current) => ({ ...current, [date]: '' }))
    try {
      const data = await command('fetch_assignments', { date })
      if (revision !== assignmentsRevisionRef.current) return
      setAssignmentsByDate((current) => ({ ...current, [date]: data }))
    } catch (assignmentError) {
      if (revision !== assignmentsRevisionRef.current) return
      setAssignmentsErrorByDate((current) => ({ ...current, [date]: assignmentError.message }))
    } finally {
      if (revision === assignmentsRevisionRef.current) setAssignmentsLoadingDate('')
    }
  }

  async function loadCalendarSupplements(startDate, endDate, includeDeadlines) {
    const rangeDates = datesInRange(startDate, endDate)
    if (!rangeDates.length) return
    const accountDataRevision = localDataClearRevision.current
    const accountScopeKey = savedCredentialState.current.account || settings.account.trim() || 'anonymous'
    const assignmentKey = `assignments:${accountScopeKey}:${startDate}:${endDate}`
    const deadlineKey = `deadlines:${startDate}:${endDate}`
    const selectedDateInRange = calendarDate >= startDate && calendarDate <= endDate
    const tasks = []

    if (!requestedCalendarSupplementRanges.current.has(assignmentKey)) {
      requestedCalendarSupplementRanges.current.add(assignmentKey)
      if (selectedDateInRange) setAssignmentsLoadingDate(calendarDate)
      tasks.push(command('fetch_assignment_calendar', {
        start_date: startDate,
        end_date: endDate,
      }).then((data) => {
        if (accountDataRevision !== localDataClearRevision.current) return
        const itemsByDate = new Map()
        ;(data?.items || []).forEach((item) => {
          const date = datePart(item.deadline)
          if (!itemsByDate.has(date)) itemsByDate.set(date, [])
          itemsByDate.get(date).push(item)
        })
        setAssignmentsByDate((current) => {
          const next = { ...current }
          rangeDates.forEach((date) => {
            next[date] = {
              date,
              source: data.source,
              items: itemsByDate.get(date) || [],
              unavailable_reason: null,
            }
          })
          return next
        })
        setAssignmentsErrorByDate((current) => {
          const next = { ...current }
          rangeDates.forEach((date) => { next[date] = '' })
          return next
        })
      }).catch((assignmentError) => {
        requestedCalendarSupplementRanges.current.delete(assignmentKey)
        if (accountDataRevision !== localDataClearRevision.current) return
        setAssignmentsErrorByDate((current) => {
          const next = { ...current }
          rangeDates.forEach((date) => { next[date] = assignmentError.message })
          return next
        })
      }).finally(() => {
        if (selectedDateInRange) setAssignmentsLoadingDate('')
      }))
    }

    const deadlineRangeCovered = rangeDates.every((date) => deadlineCoveredDatesRef.current.has(date))
    if (includeDeadlines && !deadlineRangeCovered && !requestedCalendarSupplementRanges.current.has(deadlineKey)) {
      requestedCalendarSupplementRanges.current.add(deadlineKey)
      if (selectedDateInRange) setDeadlinesLoadingDate(calendarDate)
      tasks.push((async () => {
        try {
          const preheat = deadlinePreheatPromiseRef.current
          if (preheat) {
            const succeeded = await preheat
            if (!succeeded) {
              requestedCalendarSupplementRanges.current.delete(deadlineKey)
              return
            }
          }
          if (deadlinePreheatEnabledRef.current && !deadlineSourceReadyRef.current) {
            requestedCalendarSupplementRanges.current.delete(deadlineKey)
            return
          }
          if (rangeDates.every((date) => deadlineCoveredDatesRef.current.has(date))) return
          const data = await command('fetch_deadline_calendar', {
            start_date: startDate,
            end_date: endDate,
          })
          applyDeadlineCalendarResponse(startDate, endDate, data)
        } catch (deadlineError) {
          requestedCalendarSupplementRanges.current.delete(deadlineKey)
          setDeadlinesErrorByDate((current) => {
            const next = { ...current }
            rangeDates.forEach((date) => { next[date] = deadlineError.message })
            return next
          })
        } finally {
          if (selectedDateInRange) setDeadlinesLoadingDate('')
        }
      })())
    }

    await Promise.allSettled(tasks)
  }

  async function importSystemCalendar() {
    if (settingsSaving) return
    await runTask('calendar-import', async () => {
      const path = await command('import_schedule_to_calendar')
      setCalendarImportedPath(path)
    })
  }

  async function clearAllLocalData() {
    await runTask('clear-local-data', async () => {
      const previousSavedCredential = { ...savedCredentialState.current }
      credentialStateRevision.current += 1
      localDataClearRevision.current += 1
      savedCredentialState.current = { account: '', hasSavedPassword: false }
      try {
        await command('clear_local_data')
      } catch (clearError) {
        savedCredentialState.current = previousSavedCredential
        throw clearError
      }
      setSettings({
        ...DEFAULT_SETTINGS,
        termId: metadata.default_term_id || DEFAULT_SETTINGS.termId,
        termStartDate: metadata.default_term_start_date || DEFAULT_SETTINGS.termStartDate,
        campusId: metadata.campuses?.[0]?.id || DEFAULT_SETTINGS.campusId,
      })
      setQueryCampusId(metadata.campuses?.[0]?.id || DEFAULT_SETTINGS.campusId)
      clearAccountScopedViewState()
      setMinSeats(0)
      setSettingsSaved(false)
      setClearConfirmationOpen(false)
    })
  }

  function clearAccountScopedViewState() {
    assignmentsRevisionRef.current += 1
    requestedCalendarSupplementRanges.current.clear()
    setSchedule(null)
    setClassroomsCache(null)
    setAssignmentsByDate({})
    setAssignmentsErrorByDate({})
    setAssignmentsLoadingDate('')
    setSelectedSlots([])
    setSelectedBuildings([])
    setUsePersonalSchedule(true)
    setCalendarImportedPath('')
    autoFetchedClassroomsDate.current = ''
  }

  return (
    <main className="app-shell" lang={uiLanguage === 'en' ? 'en' : 'zh-Hans'}>
      <div className="app-frame">
        <aside className="side-nav">
          <div className="side-brand">
            <p className="eyebrow">BUPT</p>
            <strong>Where To Study</strong>
          </div>
          <nav className="app-nav" aria-label={t('应用导航')}>
            {NAV_ITEMS.map(({ id, label, Icon }) => (
              <button
                key={id}
                type="button"
                className={activePage === id ? 'active' : ''}
                onClick={() => setActivePage(id)}
                aria-label={t(label)}
                title={t(label)}
              >
                <Icon size={17} />
                <span className="nav-label">{t(label)}</span>
              </button>
            ))}
          </nav>
        </aside>

        <section
          ref={pageContentRef}
          key={activePage}
          className={`page-content ${activePage}-page-content ${activePage === 'calendar' && calendarView === 'month' ? 'calendar-month-page' : ''}`}
        >
          <header className={`topbar ${activePage}-topbar`}>
            <div>
              <p className="eyebrow">{activePage === 'calendar' ? 'BUPT Classroom Planner' : 'Where To Study'}</p>
              <h1>{activePage === 'calendar' ? calendarHeaderTitle : activePage === 'settings' ? t('设置') : t('联动查询')}</h1>
            </div>
            {activePage === 'calendar' ? (
              <div className="calendar-toolbar-actions">
                <div className="calendar-view-switch" aria-label={t('日历视图')}>
                  {CALENDAR_VIEWS.map((view) => (
                    <button
                      key={view.id}
                      type="button"
                      className={calendarView === view.id ? 'active' : ''}
                      onClick={() => chooseCalendarView(view.id)}
                    >
                      {t(view.label)}
                    </button>
                  ))}
                </div>
              </div>
            ) : activePage === 'planner' ? (
              <div className="status-pill">
                <Clock3 size={16} />
                <span>{todayDate}</span>
              </div>
            ) : null}
          </header>

          {error ? (
            <div className="notice error">
              <AlertTriangle size={18} />
              <span>{t(error)}</span>
            </div>
          ) : null}

          {activePage === 'planner' ? (
        <>
        {settings.weatherEnabled ? (
          <WeatherStrip
            weather={weather}
            loading={weatherLoading}
            error={weatherError}
            onRetry={() => loadWeather(queryCampusId)}
            language={uiLanguage}
            t={t}
          />
        ) : null}
        <div className="workspace planner-workspace">
          <aside className="control-panel">
            <section className="panel planner-query-panel">
              <div className="panel-title">
                <CalendarDays size={18} />
                <h2>{t('查询条件')}</h2>
              </div>
              <div className="campus-options" aria-label={t('查询校区')}>
                {(metadata.campuses || []).map((campus) => (
                  <button
                    key={campus.id}
                    type="button"
                    className={queryCampusId === campus.id ? 'active' : ''}
                    onClick={() => {
                      setQueryCampusId(campus.id)
                      setSelectedBuildings([])
                    }}
                  >
                    {campus.name}
                  </button>
                ))}
              </div>
              <button
                type="button"
                className="planner-refresh-button"
                onClick={loadClassrooms}
                disabled={settingsSaving || !!loading}
              >
                {loading === 'classrooms' ? <Loader2 className="spin" size={17} /> : <RefreshCw size={17} />}
                {loading === 'classrooms' ? t('正在获取当天空教室…') : t('获取空教室信息')}
              </button>
              {classrooms?.provider ? (
                <p className="planner-source-note">
                  {t('数据源')}：{t(classrooms.provider === 'sjd' ? '移动教务实时接口' : classrooms.provider === 'jray_public' ? 'Jraaay 公共实时数据' : '微信教务实时接口')} · {classroomsCache?.target_date || todayDate}
                </p>
              ) : null}
            </section>

            <PlannerSummary
              className="planner-summary-desktop"
              dayCoursesCount={plannerWeekState.dayCourses.length}
              freeSlotsCount={freeSlots.length}
              matchingRoomsCount={needsBuildingSelection || needsSlotSelection ? 0 : filteredRooms.length}
              t={t}
            />

          </aside>

          <section className="main-grid">
            <section className="panel wide planner-slot-panel">
              <div className="panel-title">
                <Clock3 size={18} />
                <h2>{t('节次筛选')}</h2>
              </div>
              <label className="planner-switch-row">
                <span>{t('使用个人课表排除已有课程')}</span>
                <input
                  type="checkbox"
                  checked={usePersonalSchedule}
                  onChange={togglePersonalSchedule}
                />
                <i aria-hidden="true" />
              </label>
              <div className="mini-actions planner-slot-actions">
                <button
                  type="button"
                  onClick={() => {
                    setSelectedSlots(freeSlots)
                  }}
                >
                  {t('选中空闲')}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setSelectedSlots([])
                  }}
                >
                  {t('清空')}
                </button>
              </div>
              <div className="slot-grid">
                {slotMeta.map((slot) => {
                  const personalCourseSlot = plannerWeekState.busySlots.includes(slot.index)
                  const busy = busySlots.includes(slot.index)
                  const selected = selectedSlots.includes(slot.index)
                  return (
                    <button
                      key={slot.index}
                      type="button"
                      className={`slot-cell ${busy ? 'busy' : 'free'} ${selected ? 'selected' : ''}`}
                      onClick={() => !busy && toggleSlot(slot.index)}
                      disabled={busy}
                      title={busy ? t('个人课表占用') : personalCourseSlot ? t('个人课程时间，已纳入筛选') : t('个人空闲，可筛选教室')}
                    >
                      <span>{uiLanguage === 'en' ? `Period ${slot.label}` : `第 ${slot.label} 节`}</span>
                      <small>{slot.start}-{slot.end}</small>
                    </button>
                  )
                })}
              </div>
              <p className="muted">
                {formatUiTeachingWeek(plannerWeekState.weekNumber, uiLanguage)} · {uiLanguage === 'en' ? 'Selected: ' : '选中范围：'}
                {selectedRanges.length ? selectedRanges.map((range) => range.label).join(' / ') : t('未选择')}
              </p>
            </section>

            <section className="panel planner-courses-panel">
              <div className="panel-title">
                <CalendarDays size={18} />
                <h2>{t('当天课程')}</h2>
              </div>
              <div className="course-list">
                {plannerWeekState.dayCourses.length ? plannerWeekState.dayCourses.map((course) => (
                  <article key={course.id} className="course-row">
                    <div>
                      <strong><CourseName course={course} t={t} /></strong>
                      <span>{course.teacher || t('教师未标注')}</span>
                    </div>
                    <div>
                      <span>{course.time_range}</span>
                      <span>{course.room || t('地点未标注')}</span>
                    </div>
                  </article>
                )) : (
                  <div className="empty-state">{t('暂无课程')}</div>
                )}
              </div>
            </section>

            <section className="panel planner-buildings-panel">
              <div className="panel-title">
                <Building2 size={18} />
                <h2>{t('教学楼')}</h2>
              </div>
              <div className="building-list">
                {buildings.length ? buildings.map((building) => (
                  <button
                    key={building}
                    type="button"
                    className={selectedBuildings.includes(building) ? 'active' : ''}
                    onClick={() => toggleBuilding(building)}
                  >
                    <MapPin size={15} />
                    {displayBuildingName(building)}
                  </button>
                )) : <div className="empty-state">{t('暂无教学楼')}</div>}
              </div>
            </section>

            <section className="panel wide planner-results-panel">
              <div className="panel-title">
                <CheckCircle2 size={18} />
                <h2>{t('空教室结果')}</h2>
              </div>
              <div className="room-list">
                {needsBuildingSelection ? (
                  <div className="empty-state">{t('未选择教学楼')}</div>
                ) : needsSlotSelection ? (
                  <div className="empty-state">{t('未选择节次')}</div>
                ) : (
                  filteredRooms.length ? filteredRooms.slice(0, 80).map((room) => (
                    <article key={room.id} className="room-card">
                      <div>
                        <strong>{displayBuildingName(room.name)}</strong>
                        <span>{room.size ? (uiLanguage === 'en' ? `${room.size} seats` : `${room.size} 座`) : t('座位未知')}</span>
                      </div>
                      <p>{slotsToRanges(room.available_slots.filter((slot) => selectedSlots.includes(slot)), slotMeta).map((range) => range.label).join(' / ')}</p>
                    </article>
                  )) : (
                    <div className="empty-state">{t('暂无匹配空教室')}</div>
                  )
                )}
              </div>
            </section>
          </section>

          <PlannerSummary
            className="planner-summary-mobile"
            dayCoursesCount={plannerWeekState.dayCourses.length}
            freeSlotsCount={freeSlots.length}
            matchingRoomsCount={needsBuildingSelection || needsSlotSelection ? 0 : filteredRooms.length}
            t={t}
          />
        </div>
        </>
          ) : null}

          {activePage === 'calendar' ? (
        <section className="calendar-page">
          <div
            className={`teaching-calendar-layout ${calendarView === 'month' && compactCalendarLayout ? 'month-gesture-surface' : ''}`}
            role={calendarView === 'month' && compactCalendarLayout ? 'region' : undefined}
            tabIndex={calendarView === 'month' && compactCalendarLayout ? 0 : undefined}
            aria-label={calendarView === 'month' && compactCalendarLayout ? t('月历') : undefined}
            aria-expanded={calendarView === 'month' && compactCalendarLayout ? monthExpanded : undefined}
            onKeyDown={calendarView === 'month' && compactCalendarLayout ? handleMonthCalendarKeyDown : undefined}
          >
            {calendarView === 'month' && compactCalendarLayout ? (
              <button
                type="button"
                className="assistive-only month-expansion-accessibility-action"
                tabIndex={-1}
                aria-controls="teaching-month-calendar"
                aria-expanded={monthExpanded}
                onClick={() => {
                  if (Date.now() < suppressCalendarClickUntilRef.current) return
                  setMonthExpanded((current) => !current)
                }}
              >
                {monthExpanded ? t('收起月历') : t('展开月历')}
              </button>
            ) : null}
            <section className="teaching-calendar-main">
              <div className="calendar-action-strip">
                <div className="calendar-navigation-actions">
                  <button type="button" className="calendar-icon-button" onClick={() => moveCalendar(-1)} aria-label={t('上一段')}>‹</button>
                  <input
                    type="date"
                    value={calendarDate}
                    min="2024-01-01"
                    max="2030-12-31"
                    onChange={chooseCalendarDateFromInput}
                  />
                  <button type="button" className="calendar-today-button" onClick={() => chooseCalendarDate(todayDate)}>{t('今天')}</button>
                  <button type="button" className="calendar-icon-button" onClick={() => moveCalendar(1)} aria-label={t('下一段')}>›</button>
                </div>
                <div className="calendar-data-actions">
                  <button type="button" onClick={loadSchedule} disabled={settingsSaving || !!loading}>
                    {loading === 'schedule' ? <Loader2 className="spin" size={16} /> : <RefreshCw size={16} />}
                    {t('获取/刷新个人课表')}
                  </button>
                  {metadata.supports_calendar_import ? (
                    <button type="button" onClick={importSystemCalendar} disabled={settingsSaving || !!loading || !courses.length}>
                      {loading === 'calendar-import' ? <Loader2 className="spin" size={16} /> : <CalendarPlus size={16} />}
                      {t('导入苹果日历')}
                    </button>
                  ) : null}
                </div>
              </div>
              {calendarImportedPath ? (
                <p className="calendar-export-note">{t('已生成日历文件并打开苹果日历：')}{calendarImportedPath}</p>
              ) : null}

              <div ref={calendarTransitionHostRef} className="calendar-transition-host">
                {calendarView === 'day' || calendarView === 'week' ? (
                  <div
                    ref={calendarAnimatedSurfaceRef}
                    key={`${calendarView}-${calendarDate}`}
                    className={`time-calendar calendar-swipe-surface ${calendarView === 'day' ? 'single-day' : 'week-calendar'} ${visibleAllDayItems ? 'has-all-day' : ''} ${calendarMotion ? `calendar-motion-${calendarMotion}` : ''}`}
                    style={{ '--day-count': visibleCalendarDays.length }}
                    onTouchStart={beginCalendarSwipe}
                    onTouchEnd={finishCalendarSwipe}
                    onTouchCancel={cancelCalendarSwipe}
                    onPointerDown={beginCalendarPointerSwipe}
                    onPointerMove={updateCalendarPointerSwipe}
                    onPointerUp={finishCalendarPointerSwipe}
                    onPointerCancel={cancelCalendarPointerSwipe}
                  >
                    <div className="time-corner" />
                    {visibleCalendarDays.map((dateString) => {
                      const date = dateFromString(dateString)
                      const dayState = getWeekState(courses, activeTermStartDate, dateString)
                      return (
                        <button
                          key={`head-${dateString}`}
                          type="button"
                          className={`time-day-head ${dateString === calendarDate ? 'selected' : ''} ${dateString === todayDate ? 'today' : ''}`}
                          aria-label={`${formatUiCourseDate(dateString, uiLanguage)} · ${dayState.dayCourses.length ? (uiLanguage === 'en' ? `${dayState.dayCourses.length} courses` : `${dayState.dayCourses.length} 门课`) : t('无课程')}`}
                          onClick={() => chooseCalendarDate(dateString)}
                        >
                          <span>{uiWeekdayLabels[(date.getDay() + 6) % 7]}</span>
                          <strong data-mobile-day={date.getDate()}>{date.getMonth() + 1}/{date.getDate()}</strong>
                          <small>{dayState.dayCourses.length ? (uiLanguage === 'en' ? `${dayState.dayCourses.length} courses` : `${dayState.dayCourses.length} 门课`) : t('无课程')}</small>
                          {dayState.dayCourses.length ? (
                            <div className="calendar-day-tags">
                              <i aria-hidden="true" />
                            </div>
                          ) : null}
                        </button>
                      )
                    })}
                    {visibleAllDayItems ? (
                      <>
                        <div className="time-all-day-label">{t('全天')}</div>
                        {visibleCalendarDays.map((dateString) => {
                          const summary = summarizeMonthEntries(allDayEntriesFor(dateString), 2)
                          return (
                            <div key={`all-day-${dateString}`} className="time-all-day-cell">
                              {summary.visible.map((item) => (
                                <span key={`${dateString}-${item.key}`} className={item.type} title={item.label}>
                                  {item.type === 'assignment' ? `${t('作')} ` : item.type === 'school-notice' ? `${t('赛')} ` : ''}{item.label}
                                </span>
                              ))}
                              {summary.hiddenCount ? (
                                <button
                                  type="button"
                                  className="time-all-day-overflow"
                                  aria-label={uiLanguage === 'en' ? `${summary.hiddenCount} more all-day events on ${dateString}` : `${dateString} 还有 ${summary.hiddenCount} 项全天日程`}
                                  onClick={() => setCalendarAgendaDialog({ date: dateString })}
                                >+{summary.hiddenCount}</button>
                              ) : null}
                            </div>
                          )
                        })}
                      </>
                    ) : null}
                    <div className="time-labels">
                      {calendarHours.map((hour) => {
                        const top = (((hour * 60) - CALENDAR_START_HOUR * 60) / ((CALENDAR_END_HOUR - CALENDAR_START_HOUR) * 60)) * 100
                        return <span key={hour} style={{ top: `${top}%` }}>{String(hour).padStart(2, '0')}:00</span>
                      })}
                    </div>
                    <div className="slot-time-labels">
                      {slotMeta.map((slot) => {
                        const start = parseTimeMinutes(slot.start)
                        const end = parseTimeMinutes(slot.end)
                        const top = ((start - CALENDAR_START_HOUR * 60) / ((CALENDAR_END_HOUR - CALENDAR_START_HOUR) * 60)) * 100
                        const height = Math.max(((end - start) / ((CALENDAR_END_HOUR - CALENDAR_START_HOUR) * 60)) * 100, 4)
                        return (
                          <span key={slot.index} style={{ top: `${top}%`, height: `${height}%` }}>
                            <strong>{uiLanguage === 'en' ? `Period ${slot.label}` : `第 ${slot.label} 节`}</strong>
                            <small>{slot.start}-{slot.end}</small>
                          </span>
                        )
                      })}
                    </div>
                    {visibleCalendarDays.map((dateString) => {
                      const dayState = getWeekState(courses, activeTermStartDate, dateString)
                      const visibleStart = CALENDAR_START_HOUR * 60
                      const visibleEnd = CALENDAR_END_HOUR * 60
                      const visibleRange = visibleEnd - visibleStart
                      return (
                        <div key={`lane-${dateString}`} className={`time-day-lane ${dateString === calendarDate ? 'selected' : ''}`}>
                          <div className="time-grid-lines">
                            {calendarHours.map((hour) => {
                              const top = (((hour * 60) - visibleStart) / visibleRange) * 100
                              return <span key={hour} style={{ top: `${top}%` }} />
                            })}
                          </div>
                          <div className="time-course-layer">
                            {currentTimeLine && dateString === todayDate ? (
                              <div className="current-time-line" style={{ top: `${currentTimeLine.top}%` }}>
                                <span>{currentTimeLine.label}</span>
                              </div>
                            ) : null}
                            {dayState.dayCourses.map((course, index) => {
                              const bounds = courseTimeBounds(course, slotMeta)
                              const start = Math.max(bounds.startMinutes, visibleStart)
                              const end = Math.min(bounds.endMinutes, visibleEnd)
                              const top = ((start - visibleStart) / visibleRange) * 100
                              const height = Math.max(((end - start) / visibleRange) * 100, 6)
                              return (
                                <button
                                  key={`${dateString}-${course.id}-${index}`}
                                  type="button"
                                  className="time-course-block"
                                  style={{ top: `${top}%`, height: `${height}%` }}
                                  title={`${course.name} · ${bounds.start}-${bounds.end} · ${course.room || t('地点未标注')}`}
                                  onClick={() => chooseCalendarDate(dateString)}
                                >
                                  <strong><CourseName course={course} t={t} /></strong>
                                  <span className="course-block-time">{bounds.start}-{bounds.end}</span>
                                  <small className="course-block-place">
                                    <span>{course.room || t('地点未标注')}</span>
                                    <span>{course.teacher || t('教师未标注')}</span>
                                  </small>
                                </button>
                              )
                            })}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                ) : null}

                {calendarView === 'month' ? (
                  <div
                    ref={calendarAnimatedSurfaceRef}
                    key={`month-${calendarDate}`}
                    className={`month-view ${compactCalendarLayout ? (monthExpanded ? 'expanded' : 'compact') : 'expanded desktop-month-view'} ${calendarMotion ? `calendar-motion-${calendarMotion}` : ''}`}
                    onPointerDown={compactCalendarLayout ? beginMonthPointerSwipe : undefined}
                    onPointerMove={compactCalendarLayout ? updateMonthPointerSwipe : undefined}
                    onPointerUp={compactCalendarLayout ? finishMonthPointerSwipe : undefined}
                    onPointerCancel={compactCalendarLayout ? cancelMonthPointerSwipe : undefined}
                  >
                    <div
                      id="teaching-month-calendar"
                      className="calendar-swipe-surface month-calendar"
                      aria-label={t('月历')}
                      aria-expanded={compactCalendarLayout ? monthExpanded : undefined}
                    >
                      {uiWeekdayLabels.map((label) => <span key={label} className="month-weekday">{label}</span>)}
                      {visibleCalendarDays.map((dateString) => {
                        const date = dateFromString(dateString)
                        const currentMonth = date.getMonth() === dateFromString(calendarDate).getMonth()
                        const dayState = getWeekState(courses, activeTermStartDate, dateString)
                        const calendarItems = calendarItemsFor(dateString)
                        const supplementalEntries = supplementalEntriesFor(dateString)
                        const compactMarkers = Math.min(calendarItems.length + dayState.dayCourses.length + supplementalEntries.length, 3)
                        const monthEntries = [
                          ...calendarItems.map((item) => ({
                            key: `${dateString}-${item.type}-${item.name}`,
                            label: `${t(item.type === 'holiday' ? '休' : '班')} ${item.name}`,
                            type: item.type,
                          })),
                          ...dayState.dayCourses.map((course) => ({
                            key: `${dateString}-${course.id}`,
                            label: `${course.is_exam ? `${t('试')} ` : ''}${course.name}`,
                            type: 'course',
                          })),
                          ...supplementalEntries.map((item) => ({
                            ...item,
                            key: `${dateString}-${item.key}`,
                            label: `${t(item.type === 'assignment' ? '作' : '赛')} ${item.label}`,
                          })),
                        ]
                        const monthEntrySummary = summarizeMonthEntries(monthEntries)
                        return (
                          <button
                            key={dateString}
                            type="button"
                            className={`month-cell ${currentMonth ? '' : 'muted-day'} ${calendarItems.length || supplementalEntries.length ? 'has-calendar-item' : ''} ${supplementalEntries.length ? 'has-supplement' : ''} ${hasCalendarItemType(calendarItems, 'holiday') ? 'has-holiday' : ''} ${hasCalendarItemType(calendarItems, 'workday') ? 'has-workday' : ''} ${dateString === calendarDate ? 'selected' : ''} ${dateString === todayDate ? 'today' : ''}`}
                            onClick={() => chooseCalendarDate(dateString)}
                          >
                            <span>{date.getDate()}</span>
                            <div className="month-compact-markers" aria-hidden="true">
                              {Array.from({ length: compactMarkers }, (_, index) => <i key={index} />)}
                            </div>
                            <div className="month-cell-details">
                              {monthEntrySummary.visible.map((entry) => (
                                <small
                                  key={entry.key}
                                  className={`month-entry ${entry.type}`}
                                  title={entry.label}
                                >
                                  {entry.label}
                                </small>
                              ))}
                              {monthEntrySummary.hiddenCount ? (
                                <em className="month-entry-overflow">+{monthEntrySummary.hiddenCount}</em>
                              ) : null}
                            </div>
                          </button>
                        )
                      })}
                    </div>
                    {compactCalendarLayout ? (
                      <button
                        type="button"
                        className="month-expansion-handle"
                        aria-label={monthExpanded ? t('收起月历') : t('展开月历')}
                        aria-controls="teaching-month-calendar"
                        aria-expanded={monthExpanded}
                        onClick={() => {
                          if (Date.now() < suppressCalendarClickUntilRef.current) return
                          setMonthExpanded((current) => !current)
                        }}
                      >
                        <span aria-hidden="true" />
                      </button>
                    ) : null}
                    <div className="month-detail-stack">
                      <SelectedDaySchedule date={calendarDate} weekState={calendarWeekState} slotMeta={slotMeta} language={uiLanguage} t={t} />
                      <AssignmentDeadlineCard
                        date={calendarDate}
                        response={assignmentsByDate[calendarDate]}
                        loading={assignmentsLoadingDate === calendarDate}
                        error={assignmentsErrorByDate[calendarDate] || ''}
                        onRetry={() => loadAssignments(calendarDate, true)}
                        t={t}
                      />
                      {settings.almanacEnabled ? (
                        <AlmanacCard
                          date={calendarDate}
                          almanac={almanacByDate[calendarDate]}
                          loading={almanacLoadingDate === calendarDate}
                          error={almanacErrorByDate[calendarDate] || ''}
                          onRetry={() => loadAlmanac(calendarDate, true)}
                          t={t}
                        />
                      ) : null}
                      {settings.competitionDeadlinesEnabled
                        || settings.schoolContestNoticesEnabled
                        || settings.summerCampDeadlinesEnabled
                        || settings.hackathonDeadlinesEnabled ? (
                          <ContestDeadlineCard
                            date={calendarDate}
                            response={deadlinesByDate[calendarDate]}
                            loading={deadlinesLoadingDate === calendarDate}
                            error={deadlinesErrorByDate[calendarDate] || ''}
                            enabledTypes={{
                              competition: settings.competitionDeadlinesEnabled,
                              school_notice: settings.schoolContestNoticesEnabled,
                              summer_camp: settings.summerCampDeadlinesEnabled,
                              hackathon: settings.hackathonDeadlinesEnabled,
                            }}
                            onRetry={() => loadDeadlines(calendarDate, true)}
                            t={t}
                          />
                        ) : null}
                    </div>
                  </div>
                ) : null}

                {calendarView === 'year' ? (
                  <div
                    ref={calendarAnimatedSurfaceRef}
                    key={`year-${calendarDate}`}
                    className={`year-calendar ${calendarMotion ? `calendar-motion-${calendarMotion}` : ''}`}
                  >
                    {calendarYearMonths.map((month) => (
                      <section key={month.monthIndex} className="year-month">
                        <h3>{month.label}</h3>
                        <div className="mini-month-head">
                          {uiWeekdayLabels.map((label) => <span key={label}>{label}</span>)}
                        </div>
                        <div className="mini-month-grid">
                          {month.days.map((dateString) => {
                            const date = dateFromString(dateString)
                            const state = getWeekState(courses, activeTermStartDate, dateString)
                            const currentMonth = date.getMonth() === month.monthIndex
                            const courseCount = currentMonth ? state.dayCourses.length : 0
                            const courseOpacity = yearCourseOpacity(courseCount)
                            const calendarItems = currentMonth ? calendarItemsFor(dateString) : []
                            const supplementalEntries = currentMonth ? supplementalEntriesFor(dateString) : []
                            const hasHoliday = hasCalendarItemType(calendarItems, 'holiday')
                            const hasWorkday = hasCalendarItemType(calendarItems, 'workday')
                            const hasAssignment = supplementalEntries.some((item) => item.type === 'assignment')
                            const hasSchoolNotice = supplementalEntries.some((item) => item.type === 'school-notice')
                            return (
                              <button
                                key={dateString}
                                type="button"
                                className={`year-day-button ${currentMonth ? '' : 'muted-day'} ${courseCount ? 'has-course' : ''} ${hasHoliday ? 'has-holiday' : ''} ${hasWorkday ? 'has-workday' : ''} ${hasAssignment ? 'has-assignment' : ''} ${hasSchoolNotice ? 'has-school-notice' : ''} ${currentMonth && calendarPopover?.date === dateString ? 'selected' : ''} ${currentMonth && dateString === todayDate ? 'today' : ''}`}
                                style={courseCount ? { '--course-load-opacity': courseOpacity } : null}
                                title={[
                                  ...calendarItems.map((item) => `${t(item.type === 'holiday' ? '休' : '班')} ${item.name}`),
                                  ...supplementalEntries.map((item) => `${item.type === 'assignment' ? (uiLanguage === 'en' ? 'Assignment' : '作业') : t('校内竞赛通知')} ${item.label}`),
                                ].join(' / ')}
                                onClick={(event) => currentMonth && selectYearDate(event, dateString)}
                                onDoubleClick={(event) => currentMonth && openDesktopYearMonth(event, dateString)}
                              >
                                <span>{date.getDate()}</span>
                                {hasHoliday ? <em>{uiLanguage === 'en' ? 'O' : t('休')}</em> : null}
                                {hasWorkday ? <em className="workday">{uiLanguage === 'en' ? 'W' : t('班')}</em> : null}
                                {hasAssignment ? <em className="assignment">{t('作')}</em> : null}
                                {hasSchoolNotice ? <em className="school-notice">{t('赛')}</em> : null}
                              </button>
                            )
                          })}
                        </div>
                      </section>
                    ))}
                  </div>
                ) : null}
              </div>
                {calendarView === 'year' && calendarPopover && calendarPopoverState ? (
                  <div
                    ref={calendarPopoverRef}
                    className="year-day-popover"
                    style={{ left: calendarPopover.x, top: calendarPopover.y }}
                    role="dialog"
                    aria-label={`${formatUiCourseDate(calendarPopover.date, uiLanguage)} ${t('全天日程')}`}
                  >
                    <span>{formatUiCourseDate(calendarPopover.date, uiLanguage)}</span>
                    <strong>{uiLanguage === 'en' ? `${calendarPopoverState.dayCourses.length} courses` : `${calendarPopoverState.dayCourses.length} 门课`}</strong>
                    <small>{formatUiTeachingWeek(calendarPopoverState.weekNumber, uiLanguage)}</small>
                    {calendarItemsFor(calendarPopover.date).length ? (
                      <div className="popover-holiday-list">
                        {calendarItemsFor(calendarPopover.date).map((item) => (
                          <span key={`${calendarPopover.date}-${item.type}-${item.name}`} className={item.type}>
                            {t(item.type === 'holiday' ? '休' : '班')} {item.name}
                          </span>
                        ))}
                      </div>
                    ) : null}
                    {supplementalEntriesFor(calendarPopover.date).length ? (
                      <div className="popover-supplement-list">
                        {supplementalEntriesFor(calendarPopover.date).map((item) => {
                          const content = (
                            <>
                              <strong>{item.type === 'assignment' ? (uiLanguage === 'en' ? 'Assignment' : '作业') : t('校内竞赛通知')} · {item.label}</strong>
                              <span>{item.subtitle || t('信息未标注')}</span>
                              <small>{item.time || t('时间待定')}</small>
                            </>
                          )
                          return item.url ? (
                            <a key={item.key} href={item.url} target="_blank" rel="noreferrer" className={item.type}>{content}</a>
                          ) : <article key={item.key} className={item.type}>{content}</article>
                        })}
                      </div>
                    ) : null}
                    <div className="popover-course-list">
                      {calendarPopoverState.dayCourses.length ? calendarPopoverState.dayCourses.map((course) => {
                        const bounds = courseTimeBounds(course, slotMeta)
                        return (
                          <article key={`${calendarPopover.date}-${course.id}`}>
                            <strong><CourseName course={course} t={t} /></strong>
                            <span>{bounds.start}-{bounds.end}</span>
                            <small>{course.room || t('地点未标注')}</small>
                          </article>
                        )
                      }) : (
                        <p>{t('当天没有课程')}</p>
                      )}
                    </div>
                    <div className="popover-view-actions" aria-label={t('打开所选日期')}>
                      <button type="button" onClick={() => jumpFromYearPopover('day')}>{t('查看日')}</button>
                      <button type="button" onClick={() => jumpFromYearPopover('week')}>{t('查看周')}</button>
                      <button type="button" onClick={() => jumpFromYearPopover('month')}>{t('查看月')}</button>
                    </div>
                  </div>
                ) : null}
              </section>


          </div>
        </section>
          ) : null}

          {activePage === 'settings' ? (
        <section className="settings-layout">
          <section className="panel settings-reference-notice" aria-label={t('数据参考提示')}>
            <strong>{t('显示数据仅供参考，请以实际情况为准。')}</strong>
            <span>{uiLanguage === 'en' ? '显示数据仅供参考，请以实际情况为准。' : 'Displayed data is for reference only; please rely on the actual official information.'}</span>
          </section>
          <div className="settings-column settings-primary-column">
            <section className="panel">
              <div className="panel-title"><KeyRound size={18} /><h2>{t('个人账号')}</h2></div>
              <label>
                {t('学号')}
                <input
                  value={settings.account}
                  onChange={(event) => updateSetting('account', event.target.value)}
                  onKeyDown={(event) => { if (event.key === 'Enter') saveCurrentSettings() }}
                  inputMode="numeric"
                  placeholder={t('请输入教务学号')}
                />
              </label>
              <label>
                {t('教务密码')}
                <input
                  value={settings.password}
                  onChange={(event) => updateSetting('password', event.target.value)}
                  onKeyDown={(event) => { if (event.key === 'Enter') saveCurrentSettings() }}
                  type="password"
                  placeholder={settings.hasSavedPassword ? t('已安全保存，留空保持不变') : t('输入后保存到系统凭据存储')}
                  autoComplete="new-password"
                />
              </label>
              <div className="field-group">
                {t('默认校区')}
                <div className="campus-options">
                  {(metadata.campuses || []).map((campus) => (
                    <button
                      key={campus.id}
                      type="button"
                      className={settings.campusId === campus.id ? 'active' : ''}
                      onClick={() => updateSetting('campusId', campus.id)}
                    >
                      {campus.name}
                    </button>
                  ))}
                </div>
              </div>
              <button type="button" className="primary settings-full-button" onClick={saveCurrentSettings} disabled={!settingsLoaded || settingsSaving || !!loading}>
                {settingsSaving ? <Loader2 className="spin" size={17} /> : <CheckCircle2 size={17} />} {t('保存设置')}
              </button>
              <button type="button" className="secondary settings-full-button" onClick={loadSchedule} disabled={settingsSaving || !!loading}>
                {loading === 'schedule' ? <Loader2 className="spin" size={17} /> : <RefreshCw size={17} />} {t('获取/刷新个人课表')}
              </button>
              {settingsSaved ? <span className="settings-saved-note">{t('已保存')}</span> : null}
            </section>

            <section className="panel">
              <div className="panel-title"><CalendarDays size={18} /><h2>{t('学期设置')}</h2></div>
              <div className="settings-switch-row compact-switch-row">
                <strong>{t('自动检测当前学期')}</strong>
                <button
                  type="button"
                  className="settings-switch"
                  role="switch"
                  aria-checked={settings.automaticTermDetectionEnabled}
                  onClick={() => updateSetting('automaticTermDetectionEnabled', !settings.automaticTermDetectionEnabled)}
                ><span aria-hidden="true" /></button>
              </div>
              <label>
                {t('学期编号')}
                <input
                  value={settings.termId}
                  disabled={settings.automaticTermDetectionEnabled}
                  onChange={(event) => updateSetting('termId', event.target.value)}
                />
              </label>
              <label>
                {t('第一周周一')}
                <input
                  type="date"
                  value={settings.termStartDate}
                  min="2020-01-01"
                  max="2035-12-31"
                  disabled={settings.automaticTermDetectionEnabled}
                  onChange={(event) => updateSetting('termStartDate', event.target.value)}
                />
              </label>
              <p className="term-detect-note">
                {settings.automaticTermDetectionEnabled
                  ? t('获取/刷新课表后会自动应用教务返回的学期与开学日期。')
                  : t('已关闭自动检测，将使用上方手动填写的学期信息。')}
              </p>
              {!settings.automaticTermDetectionEnabled ? (
                <div className="mini-actions term-detect-actions">
                  <button type="button" className="secondary compact-button" onClick={() => {
                    const suggested = suggestTermForDate()
                    updateSetting('termId', suggested.termId)
                    updateSetting('termStartDate', suggested.termStartDate)
                  }}><CalendarDays size={15} />{t('按当前日期填写')}</button>
                  {termMatchesCurrentPeriod(settings.termId, settings.termStartDate) ? (
                    <span className="term-detect-ok">{t('✓ 与当前学期一致')}</span>
                  ) : isValidTermId(settings.termId) && isValidTermStartDate(settings.termStartDate) ? (
                    <span className="term-detect-hint">{t('当前设置与检测结果不同')}</span>
                  ) : null}
                </div>
              ) : null}
              <button type="button" className="secondary settings-full-button" onClick={saveCurrentSettings} disabled={!settingsLoaded || settingsSaving || !!loading}>
                <CheckCircle2 size={17} /> {t('保存学期设置')}
              </button>
            </section>
          </div>

          <div className="settings-column settings-secondary-column">
            <section className="panel settings-reminder">
              <div className="panel-title"><BellRing size={18} /><h2>{t('课程提醒')}</h2></div>
              <div className="settings-switch-row">
                <div>
                  <strong>{t('每天 07:30 发送当日课程摘要')}</strong>
                  <span>{t('仅在当天有课时发送；课表更新或账号变更后会自动重排。')}</span>
                </div>
                <button
                  type="button"
                  className="settings-switch"
                  role="switch"
                  aria-checked={settings.dailyCourseNotificationsEnabled}
                  aria-label={t('每天 07:30 发送当日课程摘要')}
                  onClick={() => updateSetting('dailyCourseNotificationsEnabled', !settings.dailyCourseNotificationsEnabled)}
                ><span aria-hidden="true" /></button>
              </div>
            </section>

            <section className="panel settings-daily-info">
              <div className="panel-title"><CalendarRange size={18} /><h2>{t('生活信息与 DDL')}</h2></div>
              {[
                ['weatherEnabled', '校区天气', '在空教室联动查询上方显示默认折叠的今日、明日天气。'],
                ['almanacEnabled', '黄历信息', '在月视图日期详情中显示农历、干支与宜忌。'],
                ['competitionDeadlinesEnabled', '学科竞赛', '在统一 DDL 卡片中显示 Contest DDL 收录的公开学科竞赛截止日期。'],
                ['schoolContestNoticesEnabled', '校内竞赛通知', '由脚本从学校内部网站公开通知页提取整理，并在统一 DDL 卡片中显示。'],
                ['summerCampDeadlinesEnabled', '夏令营', '在统一 DDL 卡片中显示夏令营截止日期。'],
                ['hackathonDeadlinesEnabled', '黑客松', '在统一 DDL 卡片中显示黑客松截止日期。'],
              ].map(([field, title, description]) => (
                <div className="settings-switch-row" key={field}>
                  <div>
                    <strong>{t(title)}</strong>
                    <span>{t(description)}</span>
                  </div>
                  <button
                    type="button"
                    className="settings-switch"
                    role="switch"
                    aria-checked={settings[field]}
                    aria-label={t(title)}
                    onClick={() => updateSetting(field, !settings[field])}
                  ><span aria-hidden="true" /></button>
                </div>
              ))}
              <p className="settings-source-note">{t('天气、黄历与 DDL 卡片底部会分别标明第三方数据来源；学科竞赛和脚本提取的校内竞赛通知由独立开关控制。')}</p>
            </section>

          <section className="panel settings-language">
            <div className="panel-title"><Settings size={18} /><h2>{t('界面语言')}</h2></div>
            <div className="language-options" role="group" aria-label={t('界面语言')}>
              {[
                ['system', t('跟随系统')],
                ['zh-Hans', t('简体中文')],
                ['en', 'English'],
              ].map(([value, label]) => (
                <button
                  key={value}
                  type="button"
                  className={settings.uiLanguage === value ? 'active' : ''}
                  onClick={() => updateSetting('uiLanguage', value)}
                >{label}</button>
              ))}
            </div>
          </section>

          <section className="panel settings-about">
            <div className="panel-title">
              <Info size={18} />
              <h2>{t('关于本应用')}</h2>
            </div>
            <p>{t('Where To Study 是独立开发的非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。')}</p>
            <div className="settings-about-actions">
              <button
                type="button"
                className="settings-privacy-link"
                onClick={(event) => {
                  privacyTriggerRef.current = event.currentTarget
                  setPrivacyPolicyOpen(true)
                }}
              >
                <ShieldCheck size={16} />
                {t('隐私说明')}
              </button>
              <a href={PROJECT_URL} target="_blank" rel="noreferrer">
                <ExternalLink size={16} />
                {t('GitHub 项目')}
              </a>
            </div>
          </section>

          <section className="panel settings-actions settings-local-data">
            <div className="panel-title">
              <HardDrive size={18} />
              <h2>{t('本地数据')}</h2>
            </div>
            <p className="settings-local-data-note">{t('清除已保存的教务账户与密码、个人课表、空教室和节假日缓存，并恢复本地设置。')}</p>
            <button
              type="button"
              className="danger"
              onClick={() => setClearConfirmationOpen(true)}
              disabled={settingsSaving || !!loading}
            >
              <Trash2 size={17} />
              {t('清除本地数据')}
            </button>
            {clearConfirmationOpen ? (
              <div className="clear-data-confirmation" role="alertdialog" aria-labelledby="clear-data-title">
                <strong id="clear-data-title">{t('清除全部本地数据？')}</strong>
                <p>{t('将删除保存的账号、密码、个人课表、空教室缓存和设置。此操作无法撤销。')}</p>
                <div>
                  <button ref={clearCancelButtonRef} type="button" className="secondary" onClick={() => setClearConfirmationOpen(false)} disabled={settingsSaving || !!loading}>
                    {t('取消')}
                  </button>
                  <button type="button" className="danger" onClick={clearAllLocalData} disabled={settingsSaving || !!loading}>
                    {loading === 'clear-local-data' ? <Loader2 className="spin" size={17} /> : <Trash2 size={17} />}
                    {t('确认清除')}
                  </button>
                </div>
              </div>
            ) : null}
          </section>
          </div>
        </section>
          ) : null}
        </section>
      </div>
      {calendarAgendaDialog ? (
        <div
          className="calendar-agenda-backdrop"
          onMouseDown={(event) => {
            if (event.button === 0 && event.target === event.currentTarget) setCalendarAgendaDialog(null)
          }}
        >
          <section className="calendar-agenda-dialog" role="dialog" aria-modal="true" aria-labelledby="calendar-agenda-title">
            <header>
              <div>
                <span>{t('全天日程')}</span>
                <h2 id="calendar-agenda-title">{formatUiCourseDate(calendarAgendaDialog.date, uiLanguage)}</h2>
              </div>
              <button type="button" onClick={() => setCalendarAgendaDialog(null)} aria-label={t('关闭全天日程')}><X size={19} /></button>
            </header>
            <div className="calendar-agenda-list">
              {allDayEntriesFor(calendarAgendaDialog.date).map((item) => {
                const content = (
                  <>
                    <strong>{item.label}</strong>
                    {item.subtitle ? <span>{item.subtitle}</span> : null}
                    {item.time ? <time>{item.time}</time> : null}
                  </>
                )
                return item.url ? (
                  <a key={item.key} href={item.url} target="_blank" rel="noreferrer" className={item.type}>{content}</a>
                ) : <article key={item.key} className={item.type}>{content}</article>
              })}
            </div>
          </section>
        </div>
      ) : null}
      {privacyPolicyOpen ? (
        <PrivacyPolicyDialog onClose={() => {
          setPrivacyPolicyOpen(false)
          privacyTriggerRef.current?.focus()
        }} />
      ) : null}
    </main>
  )
}

export default App
