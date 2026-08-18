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
  Clock3,
  ExternalLink,
  Home,
  HardDrive,
  Info,
  KeyRound,
  Loader2,
  MapPin,
  RefreshCw,
  Search,
  Settings,
  ShieldCheck,
  Trash2,
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
  localDateString,
  msUntilNextShanghaiMidnight,
  normalizeClassroomsCache,
  normalizeError,
  parseTimeMinutes,
  requestBody,
  savedCredentialSnapshot,
  savedSettingsToState,
  settingsToPayload,
  shanghaiDateString,
  shiftDate,
  slotsToRanges,
  startOfWeekSunday,
  summarizeMonthEntries,
  yearCourseOpacity,
} from './planner-domain.js'
import './App.css'

const NAV_ITEMS = [
  { id: 'planner', label: '空教室', Icon: Home },
  { id: 'calendar', label: '教学日历', Icon: CalendarRange },
  { id: 'settings', label: '设置', Icon: Settings },
]

const APP_WIDGET_MODE = typeof window === 'undefined'
  ? ''
  : new URLSearchParams(window.location.search).get('widget') || ''
const BROWSER_PREVIEW_ENABLED = import.meta.env.DEV
const PROJECT_URL = 'https://github.com/Nemoyuzx/where_to_study'
const PRIVACY_POLICY_URL = 'https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md'

function PrivacyPolicyDialog({ onClose }) {
  const closeButtonRef = useRef(null)

  useEffect(() => {
    const closeOnEscape = (event) => {
      if (event.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', closeOnEscape)
    closeButtonRef.current?.focus()
    return () => window.removeEventListener('keydown', closeOnEscape)
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
        className="privacy-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="privacy-dialog-title"
      >
        <header className="privacy-dialog-header">
          <div>
            <p className="eyebrow">Where To Study</p>
            <h2 id="privacy-dialog-title">隐私声明</h2>
            <span>生效日期：2026 年 8 月 9 日</span>
          </div>
          <button ref={closeButtonRef} type="button" onClick={onClose} aria-label="关闭隐私声明" title="关闭">
            <X size={20} />
          </button>
        </header>

        <div className="privacy-dialog-body">
          <p>Where To Study 是用于查看北邮个人课表和空教室的独立非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。</p>

          <section>
            <h3>账户与教务请求</h3>
            <p>你输入的学号和密码保存在操作系统的受保护凭据存储中。应用在你手动获取课表或空教室时，会通过 HTTPS 将凭据发送到北邮教务服务 jwglweixin.bupt.edu.cn。保存有效凭据后，桌面端还可能在应用运行期间每日 07:00 左右自动刷新当天空教室。项目维护者无法读取这些凭据。</p>
          </section>
          <section>
            <h3>本地数据</h3>
            <p>个人课表、空教室结果、校区和学期等设置会缓存在你的设备上，以减少重复请求。你可以在设置中使用“清除本地数据”删除应用保存的凭据、课表、空教室缓存、节假日缓存和提醒任务。</p>
          </section>
          <section>
            <h3>节假日数据</h3>
            <p>应用在启动、切换日历年份或缓存需要更新时，可能通过 unpkg 自动获取 holiday-calendar 数据集中的中国法定节假日和调休信息。请求只包含 CN 地区和年份，不包含你的凭据、课表或空教室数据。</p>
          </section>
          <section>
            <h3>系统日历与课程提醒</h3>
            <p>只有在你主动操作并授予系统权限后，应用才会向系统日历写入课程或在本地安排课程摘要通知。应用只管理带有 Where To Study 标记的日历事件，相关数据不会上传给项目维护者。</p>
          </section>
          <section>
            <h3>不收集的数据</h3>
            <p>本项目不运营应用后端，不包含广告、分析或行为跟踪 SDK，也不收集位置、联系人、广告标识符或使用行为。北邮教务服务和节假日数据的 CDN 可能依据各自政策处理 IP 地址、请求时间等普通网络元数据。</p>
          </section>
          <section>
            <h3>保留、删除与联系</h3>
            <p>凭据和缓存会保留在你的设备上，直到被替换、在设置中清除或随应用卸载移除。隐私问题可以在 GitHub 提交不含敏感信息的讨论或 Issue；请勿在公开内容中提供账号、密码、令牌或个人课表。</p>
          </section>
        </div>

        <footer className="privacy-dialog-footer">
          <a href={PRIVACY_POLICY_URL} target="_blank" rel="noreferrer">
            在 GitHub 查看项目与完整声明
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
      daily_course_notifications_enabled: DEFAULT_SETTINGS.dailyCourseNotificationsEnabled,
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
      daily_course_notifications_enabled: Boolean(payload.daily_course_notifications_enabled),
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
  if (name === 'show_desktop_widget' || name === 'hide_desktop_widget') {
    return true
  }
  if (name === 'clear_local_data') {
    return true
  }
  return null
}

function PlannerSummary({ dayCoursesCount, freeSlotsCount, matchingRoomsCount, className = '' }) {
  return (
    <section className={`summary-band ${className}`.trim()}>
      <div>
        <span>当天课程</span>
        <strong>{dayCoursesCount}</strong>
      </div>
      <div>
        <span>个人空闲节次</span>
        <strong>{freeSlotsCount}</strong>
      </div>
      <div>
        <span>匹配教室</span>
        <strong>{matchingRoomsCount}</strong>
      </div>
    </section>
  )
}

function CourseName({ course }) {
  return (
    <span className="course-name-with-badge">
      {course.is_exam ? <em className="course-exam-badge">试</em> : null}
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

function CourseWidget() {
  const [metadata, setMetadata] = useState({ slots: FALLBACK_SLOTS })
  const [schedule, setSchedule] = useState(null)
  const [now, setNow] = useState(() => new Date())
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const scheduleRevision = useRef(0)

  const todayDate = shanghaiDateString(now)
  const slotMeta = metadata.slots?.length ? metadata.slots : FALLBACK_SLOTS
  const courses = schedule?.courses || []
  const weekState = useMemo(
    () => getWeekState(courses, schedule?.term_start_date || DEFAULT_SETTINGS.termStartDate, todayDate),
    [courses, schedule?.term_start_date, todayDate],
  )
  const nowMinutes = now.getHours() * 60 + now.getMinutes()
  const upcomingCourse = weekState.dayCourses.find((course) => courseTimeBounds(course, slotMeta).endMinutes >= nowMinutes) || null

  async function loadWidgetSchedule(expectedAccountScope = '') {
    const revision = scheduleRevision.current + 1
    scheduleRevision.current = revision
    setLoading(true)
    setError('')
    try {
      const [nextMetadata, savedSchedule] = await Promise.all([
        command('get_metadata'),
        expectedAccountScope
          ? command('load_saved_schedule_for_scope', { account_scope: expectedAccountScope })
          : command('load_saved_schedule'),
      ])
      if (revision !== scheduleRevision.current) return
      setMetadata(nextMetadata || { slots: FALLBACK_SLOTS })
      setSchedule(savedSchedule)
    } catch (widgetError) {
      if (revision === scheduleRevision.current) setError(widgetError.message)
    } finally {
      if (revision === scheduleRevision.current) setLoading(false)
    }
  }

  useEffect(() => {
    let disposed = false
    let unlistenUpdated = null
    let unlistenCleared = null

    async function startWidget() {
      if (hasTauriRuntime()) {
        try {
          unlistenCleared = await listen('account-scope:cleared', () => {
            scheduleRevision.current += 1
            setSchedule(null)
            setLoading(false)
            setError('')
          })
          if (disposed) {
            unlistenCleared()
            unlistenCleared = null
            return
          }
          unlistenUpdated = await listen('schedule:updated', (event) => {
            const accountScope = event.payload?.account_scope
            setSchedule(null)
            if (!isValidAccountScope(accountScope)) {
              scheduleRevision.current += 1
              setLoading(false)
              setError('课程更新的账号作用域无效，已拒绝显示。')
              return
            }
            void loadWidgetSchedule(accountScope)
          })
          if (disposed) {
            unlistenUpdated()
            unlistenUpdated = null
            return
          }
        } catch (listenError) {
          if (!disposed) setError(normalizeError(listenError))
          return
        }
      }
      if (!disposed) await loadWidgetSchedule()
    }

    startWidget()
    return () => {
      disposed = true
      scheduleRevision.current += 1
      if (unlistenUpdated) unlistenUpdated()
      if (unlistenCleared) unlistenCleared()
    }
  }, [])

  useEffect(() => {
    const current = new Date()
    const currentMinutes = current.getHours() * 60 + current.getMinutes()
    const nextMidnight = new Date(current)
    nextMidnight.setHours(24, 0, 0, 0)
    const wakeTimes = [nextMidnight.getTime()]

    weekState.dayCourses.forEach((course) => {
      const { endMinutes } = courseTimeBounds(course, slotMeta)
      if (endMinutes < currentMinutes) return
      const wake = new Date(current)
      const nextMinute = endMinutes + 1
      wake.setHours(Math.floor(nextMinute / 60), nextMinute % 60, 0, 0)
      wakeTimes.push(wake.getTime())
    })

    const delay = Math.max(1000, Math.min(...wakeTimes) - current.getTime())
    const timer = window.setTimeout(() => setNow(new Date()), delay)
    return () => window.clearTimeout(timer)
  }, [now, slotMeta, weekState.dayCourses])

  async function hideWidget() {
    try {
      await command('hide_desktop_widget')
    } catch (hideError) {
      setError(hideError.message)
    }
  }

  return (
    <main className="course-widget-shell">
      <section className="course-widget-card">
        <header className="course-widget-header">
          <div className="course-widget-drag" data-tauri-drag-region>
            <span>{formatCourseDate(todayDate)}</span>
            <strong>{weekState.dayCourses.length ? `${weekState.dayCourses.length} 门课` : '今日无课'}</strong>
          </div>
          <div className="course-widget-actions">
            <button type="button" onClick={loadWidgetSchedule} aria-label="刷新课程" title="刷新课程" disabled={loading}>
              {loading ? <Loader2 className="spin" size={16} /> : <RefreshCw size={16} />}
            </button>
            <button type="button" onClick={hideWidget} aria-label="隐藏小组件" title="隐藏小组件">
              <X size={16} />
            </button>
          </div>
        </header>

        <div className="course-widget-overview">
          <span>{formatTeachingWeek(weekState.weekNumber)}</span>
          <strong>{upcomingCourse ? <CourseName course={upcomingCourse} /> : schedule ? '没有待上课程' : '课表未载入'}</strong>
          {upcomingCourse ? (
            <small>{courseTimeBounds(upcomingCourse, slotMeta).start}-{courseTimeBounds(upcomingCourse, slotMeta).end} · {upcomingCourse.room || '地点未标注'}</small>
          ) : (
            <small>{schedule ? '今天可以自由安排' : '打开主应用刷新个人课表后显示'}</small>
          )}
        </div>

        {error ? <p className="course-widget-error">{error}</p> : null}

        <div className="course-widget-list">
          {schedule ? (
            weekState.dayCourses.length ? weekState.dayCourses.map((course) => {
              const bounds = courseTimeBounds(course, slotMeta)
              return (
                <article key={course.id}>
                  <time>{bounds.start}</time>
                  <div>
                    <strong><CourseName course={course} /></strong>
                    <span>{bounds.start}-{bounds.end} · {course.room || '地点未标注'}</span>
                  </div>
                </article>
              )
            }) : (
              <div className="course-widget-empty">今日暂无课程</div>
            )
          ) : (
            <div className="course-widget-empty">暂无本地课表</div>
          )}
        </div>
      </section>
    </main>
  )
}

function App() {
  if (APP_WIDGET_MODE === 'course') {
    return <CourseWidget />
  }

  const [activePage, setActivePage] = useState('planner')
  const [metadata, setMetadata] = useState({
    campuses: [],
    slots: FALLBACK_SLOTS,
    supports_calendar_import: false,
  })
  const [settings, setSettings] = useState(() => ({ ...DEFAULT_SETTINGS }))
  const [queryCampusId, setQueryCampusId] = useState(DEFAULT_SETTINGS.campusId)
  const [calendarDate, setCalendarDate] = useState(localDateString())
  const [calendarView, setCalendarView] = useState('week')
  const [calendarMotion, setCalendarMotion] = useState('')
  const [monthExpanded, setMonthExpanded] = useState(true)
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

  useEffect(() => {
    const page = pageContentRef.current
    if (!page) return undefined
    page.addEventListener('touchmove', updateCalendarSwipe, { passive: false })
    return () => {
      page.removeEventListener('touchmove', updateCalendarSwipe)
      page.classList.remove('calendar-gesture-locked')
    }
  }, [])

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

    let unlisten = null

    listen('tray:navigate', (event) => {
      if (['planner', 'calendar', 'settings'].includes(event.payload)) {
        setActivePage(event.payload)
      }
    }).then((dispose) => {
      unlisten = dispose
    })

    listen('tray:hide-notice', (event) => {
      setError(String(event.payload || '窗口已隐藏，应用仍在系统托盘运行。'))
    }).then((dispose) => {
      unlisten = dispose
    })

    return () => {
      if (unlisten) unlisten()
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
    if (activePage !== 'calendar' || calendarView !== 'day' || calendarDate !== todayDate) {
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
      const start = startOfWeekSunday(calendarDate)
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
      label: `${monthIndex + 1}月`,
      days: buildMiniMonthDays(year, monthIndex),
    }))
  }, [calendarDate])
  const calendarDetailCourse = calendarWeekState.dayCourses[0] || null
  const calendarHeaderTitle = calendarView === 'week'
    ? `${formatCalendarTitle(calendarDate, calendarView)} · ${formatTeachingWeek(calendarWeekState.weekNumber)}`
    : formatCalendarTitle(calendarDate, calendarView)
  const visibleAllDayItems = useMemo(
    () => visibleCalendarDays.reduce(
      (count, dateString) => count + (calendarDayMap.get(dateString) || []).length,
      0,
    ),
    [calendarDayMap, visibleCalendarDays],
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
      blocked: Boolean(event.target.closest('input, select, textarea, a')),
    }
  }

  // Pointer-based swipe for the day/week calendar: lets Windows/macOS mouse
  // users drag horizontally to page the calendar, matching the touch gesture.
  function beginCalendarPointerSwipe(event) {
    if (calendarView === 'year' || event.isPrimary === false) return
    if (event.pointerType === 'mouse' && event.button !== 0) return
    if (event.target.closest('input, select, textarea, a')) return
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
      window.clearTimeout(yearClickTimerRef.current)
      yearClickTimerRef.current = window.setTimeout(() => {
        setCalendarDate(dateString)
        setCalendarPopover(null)
      }, 250)
      return
    }
    openYearDayPopover(event, dateString)
  }

  function openDesktopYearMonth(event, dateString) {
    if (compactCalendarLayout) return
    event.preventDefault()
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
      }))
      if (accountDataRevision !== localDataClearRevision.current) return
      setSchedule(data)
      setCalendarImportedPath('')
      setUsePersonalSchedule(true)
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

  async function importSystemCalendar() {
    if (settingsSaving) return
    await runTask('calendar-import', async () => {
      const path = await command('import_schedule_to_calendar')
      setCalendarImportedPath(path)
    })
  }

  async function openDesktopWidget() {
    await runTask('widget', async () => {
      await command('show_desktop_widget')
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
    setSchedule(null)
    setClassroomsCache(null)
    setSelectedSlots([])
    setSelectedBuildings([])
    setUsePersonalSchedule(true)
    setCalendarImportedPath('')
    autoFetchedClassroomsDate.current = ''
  }

  return (
    <main className="app-shell">
      <div className="app-frame">
        <aside className="side-nav">
          <div className="side-brand">
            <p className="eyebrow">BUPT</p>
            <strong>Where To Study</strong>
          </div>
          <nav className="app-nav" aria-label="应用导航">
            {NAV_ITEMS.map(({ id, label, Icon }) => (
              <button
                key={id}
                type="button"
                className={activePage === id ? 'active' : ''}
                onClick={() => setActivePage(id)}
                aria-label={label}
                title={label}
              >
                <Icon size={17} />
                <span className="nav-label">{label}</span>
              </button>
            ))}
          </nav>
        </aside>

        <section
          ref={pageContentRef}
          className={`page-content ${activePage}-page-content ${activePage === 'calendar' && calendarView === 'month' ? 'calendar-month-page' : ''}`}
        >
          <header className={`topbar ${activePage}-topbar`}>
            <div>
              <p className="eyebrow">BUPT Classroom Planner</p>
              <h1>{activePage === 'calendar' ? calendarHeaderTitle : activePage === 'settings' ? '设置' : '联动查询'}</h1>
            </div>
            {activePage === 'calendar' ? (
              <div className="calendar-toolbar-actions">
                <div className="calendar-view-switch" aria-label="日历视图">
                  {CALENDAR_VIEWS.map((view) => (
                    <button
                      key={view.id}
                      type="button"
                      className={calendarView === view.id ? 'active' : ''}
                      onClick={() => chooseCalendarView(view.id)}
                    >
                      {view.label}
                    </button>
                  ))}
                </div>
                <button type="button" className="calendar-icon-button" onClick={() => moveCalendar(-1)} aria-label="上一段">‹</button>
                <button type="button" className="calendar-today-button" onClick={() => chooseCalendarDate(todayDate)}>今天</button>
                <button type="button" className="calendar-icon-button" onClick={() => moveCalendar(1)} aria-label="下一段">›</button>
              </div>
            ) : (
              <div className="status-pill">
                <Clock3 size={16} />
                <span>{todayDate}</span>
              </div>
            )}
          </header>

          {error ? (
            <div className="notice error">
              <AlertTriangle size={18} />
              <span>{error}</span>
            </div>
          ) : null}

          {activePage === 'planner' ? (
        <div className="workspace planner-workspace">
          <aside className="control-panel">
            <section className="panel planner-query-panel">
              <div className="panel-title">
                <CalendarDays size={18} />
                <h2>查询条件</h2>
              </div>
              <div className="campus-options" aria-label="查询校区">
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
                {loading === 'classrooms' ? '正在获取当天空教室…' : '获取空教室信息'}
              </button>
              {classrooms?.provider ? (
                <p className="planner-source-note">
                  数据源：{classrooms.provider === 'sjd' ? '移动教务实时接口' : classrooms.provider === 'jray_public' ? 'Jraaay 公共实时数据' : '微信教务实时接口'} · {classroomsCache?.target_date || todayDate}
                </p>
              ) : null}
            </section>

            <PlannerSummary
              className="planner-summary-desktop"
              dayCoursesCount={plannerWeekState.dayCourses.length}
              freeSlotsCount={freeSlots.length}
              matchingRoomsCount={needsBuildingSelection || needsSlotSelection ? 0 : filteredRooms.length}
            />

          </aside>

          <section className="main-grid">
            <section className="panel wide planner-slot-panel">
              <div className="panel-title">
                <Clock3 size={18} />
                <h2>节次筛选</h2>
              </div>
              <label className="planner-switch-row">
                <span>使用个人课表排除已有课程</span>
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
                  选中空闲
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setSelectedSlots([])
                  }}
                >
                  清空
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
                      title={busy ? '个人课表占用' : personalCourseSlot ? '个人课程时间，已纳入筛选' : '个人空闲，可筛选教室'}
                    >
                      <span>第 {slot.label} 节</span>
                      <small>{slot.start}-{slot.end}</small>
                    </button>
                  )
                })}
              </div>
              <p className="muted">
                {formatTeachingWeek(plannerWeekState.weekNumber)}，选中范围：
                {selectedRanges.length ? selectedRanges.map((range) => range.label).join(' / ') : '未选择'}
              </p>
            </section>

            <section className="panel">
              <div className="panel-title">
                <CalendarDays size={18} />
                <h2>当天课程</h2>
              </div>
              <div className="course-list">
                {plannerWeekState.dayCourses.length ? plannerWeekState.dayCourses.map((course) => (
                  <article key={course.id} className="course-row">
                    <div>
                      <strong><CourseName course={course} /></strong>
                      <span>{course.teacher || '教师未标注'}</span>
                    </div>
                    <div>
                      <span>{course.time_range}</span>
                      <span>{course.room || '地点未标注'}</span>
                    </div>
                  </article>
                )) : (
                  <div className="empty-state">暂无课程</div>
                )}
              </div>
            </section>

            <section className="panel">
              <div className="panel-title">
                <Building2 size={18} />
                <h2>教学楼</h2>
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
                )) : <div className="empty-state">暂无教学楼</div>}
              </div>
            </section>

            <section className="panel wide">
              <div className="panel-title">
                <CheckCircle2 size={18} />
                <h2>空教室结果</h2>
              </div>
              <div className="room-list">
                {needsBuildingSelection ? (
                  <div className="empty-state">未选择教学楼</div>
                ) : needsSlotSelection ? (
                  <div className="empty-state">未选择节次</div>
                ) : (
                  filteredRooms.length ? filteredRooms.slice(0, 80).map((room) => (
                    <article key={room.id} className="room-card">
                      <div>
                        <strong>{displayBuildingName(room.name)}</strong>
                        <span>{room.size ? `${room.size} 座` : '座位未知'}</span>
                      </div>
                      <p>{slotsToRanges(room.available_slots.filter((slot) => selectedSlots.includes(slot)), slotMeta).map((range) => range.label).join(' / ')}</p>
                    </article>
                  )) : (
                    <div className="empty-state">暂无匹配空教室</div>
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
          />
        </div>
          ) : null}

          {activePage === 'calendar' ? (
        <section className="calendar-page">
          <div
            className={`teaching-calendar-layout ${calendarView === 'month' && compactCalendarLayout ? 'month-gesture-surface' : ''}`}
            role={calendarView === 'month' && compactCalendarLayout ? 'region' : undefined}
            tabIndex={calendarView === 'month' && compactCalendarLayout ? 0 : undefined}
            aria-label={calendarView === 'month' && compactCalendarLayout ? '月历，下拉或按下方向键展开，上拉或按上方向键收起' : undefined}
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
                {monthExpanded ? '收起月历' : '展开月历'}
              </button>
            ) : null}
            <section className="teaching-calendar-main">
              <div className="calendar-action-strip">
                <input
                  type="date"
                  value={calendarDate}
                  min="2024-01-01"
                  max="2030-12-31"
                  onChange={chooseCalendarDateFromInput}
                />
                <button type="button" onClick={loadSchedule} disabled={settingsSaving || !!loading}>
                  {loading === 'schedule' ? <Loader2 className="spin" size={16} /> : <RefreshCw size={16} />}
                  获取/刷新个人课表
                </button>
                {metadata.supports_calendar_import ? (
                  <button type="button" onClick={importSystemCalendar} disabled={settingsSaving || !!loading || !courses.length}>
                    {loading === 'calendar-import' ? <Loader2 className="spin" size={16} /> : <CalendarPlus size={16} />}
                    导入苹果日历
                  </button>
                ) : null}
              </div>
              {calendarImportedPath ? (
                <p className="calendar-export-note">已生成日历文件并打开苹果日历：{calendarImportedPath}</p>
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
                          aria-label={`${date.getMonth() + 1}月${date.getDate()}日，${dayState.dayCourses.length ? `${dayState.dayCourses.length} 门课` : '无课程'}`}
                          onClick={() => chooseCalendarDate(dateString)}
                        >
                          <span>{CALENDAR_WEEKDAYS[date.getDay()]}</span>
                          <strong data-mobile-day={date.getDate()}>{date.getMonth() + 1}/{date.getDate()}</strong>
                          <small>{dayState.dayCourses.length ? `${dayState.dayCourses.length} 门课` : '无课程'}</small>
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
                        <div className="time-all-day-label">全天</div>
                        {visibleCalendarDays.map((dateString) => (
                          <div key={`all-day-${dateString}`} className="time-all-day-cell">
                            {calendarItemsFor(dateString).map((item) => (
                              <span key={`${dateString}-${item.type}-${item.name}`} className={item.type}>
                                {item.type === 'holiday' ? '休' : '班'} {item.name}
                              </span>
                            ))}
                          </div>
                        ))}
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
                            <strong>第 {slot.label} 节</strong>
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
                                  onClick={() => chooseCalendarDate(dateString)}
                                >
                                  <strong><CourseName course={course} /></strong>
                                  <span className="course-block-time">{bounds.start}-{bounds.end}</span>
                                  <small className="course-block-place">
                                    <span>{course.room || '地点未标注'}</span>
                                    <span>{course.teacher || '教师未标注'}</span>
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
                      aria-label={compactCalendarLayout ? `${monthExpanded ? '展开' : '收起'}的月历，下拉展开，上拉收起` : '月历'}
                      aria-expanded={compactCalendarLayout ? monthExpanded : undefined}
                    >
                      {CALENDAR_WEEKDAYS.map((label) => <span key={label} className="month-weekday">{label}</span>)}
                      {visibleCalendarDays.map((dateString) => {
                        const date = dateFromString(dateString)
                        const currentMonth = date.getMonth() === dateFromString(calendarDate).getMonth()
                        const dayState = getWeekState(courses, activeTermStartDate, dateString)
                        const calendarItems = calendarItemsFor(dateString)
                        const compactMarkers = Math.min(calendarItems.length + dayState.dayCourses.length, 3)
                        const monthEntries = [
                          ...calendarItems.map((item) => ({
                            key: `${dateString}-${item.type}-${item.name}`,
                            label: `${item.type === 'holiday' ? '休' : '班'} ${item.name}`,
                            type: item.type,
                          })),
                          ...dayState.dayCourses.map((course) => ({
                            key: `${dateString}-${course.id}`,
                            label: `${course.is_exam ? '试 ' : ''}${course.name}`,
                            type: 'course',
                          })),
                        ]
                        const monthEntrySummary = summarizeMonthEntries(monthEntries)
                        return (
                          <button
                            key={dateString}
                            type="button"
                            className={`month-cell ${currentMonth ? '' : 'muted-day'} ${calendarItems.length ? 'has-calendar-item' : ''} ${hasCalendarItemType(calendarItems, 'holiday') ? 'has-holiday' : ''} ${hasCalendarItemType(calendarItems, 'workday') ? 'has-workday' : ''} ${dateString === calendarDate ? 'selected' : ''} ${dateString === todayDate ? 'today' : ''}`}
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
                        aria-label={monthExpanded ? '收起月历' : '展开月历'}
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
                          {CALENDAR_WEEKDAYS.map((label) => <span key={label}>{label}</span>)}
                        </div>
                        <div className="mini-month-grid">
                          {month.days.map((dateString) => {
                            const date = dateFromString(dateString)
                            const state = getWeekState(courses, activeTermStartDate, dateString)
                            const currentMonth = date.getMonth() === month.monthIndex
                            const courseCount = currentMonth ? state.dayCourses.length : 0
                            const courseOpacity = yearCourseOpacity(courseCount)
                            const calendarItems = currentMonth ? calendarItemsFor(dateString) : []
                            const hasHoliday = hasCalendarItemType(calendarItems, 'holiday')
                            const hasWorkday = hasCalendarItemType(calendarItems, 'workday')
                            return (
                              <button
                                key={dateString}
                                type="button"
                                className={`year-day-button ${currentMonth ? '' : 'muted-day'} ${courseCount ? 'has-course' : ''} ${hasHoliday ? 'has-holiday' : ''} ${hasWorkday ? 'has-workday' : ''} ${currentMonth && (compactCalendarLayout ? calendarPopover?.date === dateString : calendarDate === dateString) ? 'selected' : ''} ${currentMonth && dateString === todayDate ? 'today' : ''}`}
                                style={courseCount ? { '--course-load-opacity': courseOpacity } : null}
                                title={calendarItems.map((item) => `${item.type === 'holiday' ? '休' : '班'} ${item.name}`).join(' / ')}
                                onClick={(event) => currentMonth && selectYearDate(event, dateString)}
                                onDoubleClick={(event) => currentMonth && openDesktopYearMonth(event, dateString)}
                              >
                                <span>{date.getDate()}</span>
                                {hasHoliday ? <em>休</em> : null}
                                {hasWorkday ? <em className="workday">班</em> : null}
                              </button>
                            )
                          })}
                        </div>
                      </section>
                    ))}
                  </div>
                ) : null}
              </div>
                {compactCalendarLayout && calendarView === 'year' && calendarPopover && calendarPopoverState ? (
                  <div
                    ref={calendarPopoverRef}
                    className="year-day-popover"
                    style={{ left: calendarPopover.x, top: calendarPopover.y }}
                    role="dialog"
                    aria-label={`${formatCourseDate(calendarPopover.date)} 日程`}
                  >
                    <span>{formatCourseDate(calendarPopover.date)}</span>
                    <strong>{calendarPopoverState.dayCourses.length} 门课</strong>
                    <small>{formatTeachingWeek(calendarPopoverState.weekNumber)}</small>
                    {calendarItemsFor(calendarPopover.date).length ? (
                      <div className="popover-holiday-list">
                        {calendarItemsFor(calendarPopover.date).map((item) => (
                          <span key={`${calendarPopover.date}-${item.type}-${item.name}`} className={item.type}>
                            {item.type === 'holiday' ? '休' : '班'} {item.name}
                          </span>
                        ))}
                      </div>
                    ) : null}
                    <div className="popover-course-list">
                      {calendarPopoverState.dayCourses.length ? calendarPopoverState.dayCourses.map((course) => {
                        const bounds = courseTimeBounds(course, slotMeta)
                        return (
                          <article key={`${calendarPopover.date}-${course.id}`}>
                            <strong><CourseName course={course} /></strong>
                            <span>{bounds.start}-{bounds.end}</span>
                            <small>{course.room || '地点未标注'}</small>
                          </article>
                        )
                      }) : (
                        <p>当天没有课程</p>
                      )}
                    </div>
                    <div className="popover-view-actions" aria-label="打开所选日期">
                      <button type="button" onClick={() => jumpFromYearPopover('day')}>查看日</button>
                      <button type="button" onClick={() => jumpFromYearPopover('week')}>查看周</button>
                      <button type="button" onClick={() => jumpFromYearPopover('month')}>查看月</button>
                    </div>
                  </div>
                ) : null}
              </section>

              <aside className={`calendar-inspector ${compactCalendarLayout && calendarView === 'month' && monthExpanded ? 'month-expanded-hidden' : ''}`}>
                <div className="inspector-card primary">
                  <span>{formatCourseDate(calendarDate)}</span>
                  <strong>{calendarWeekState.dayCourses.length} 门课</strong>
                  <small>{formatTeachingWeek(calendarWeekState.weekNumber)}</small>
                </div>
                {calendarDetailCourse ? (
                  <div className="inspector-card">
                    <strong><CourseName course={calendarDetailCourse} /></strong>
                    <span>{courseTimeBounds(calendarDetailCourse, slotMeta).start}-{courseTimeBounds(calendarDetailCourse, slotMeta).end}</span>
                    <span>{calendarDetailCourse.room || '地点未标注'}</span>
                    <small>{calendarDetailCourse.teacher || '教师未标注'}</small>
                  </div>
                ) : (
                  <div className="inspector-card muted-card">所选日期暂无课程</div>
                )}
                <div className="inspector-list">
                  {calendarWeekState.dayCourses.slice(calendarDetailCourse ? 1 : 0).map((course) => {
                    const bounds = courseTimeBounds(course, slotMeta)
                    return (
                      <article key={`${calendarDate}-${course.id}`}>
                        <strong><CourseName course={course} /></strong>
                        <span>{bounds.start}-{bounds.end}</span>
                        <small>{course.room || '地点未标注'}</small>
                      </article>
                    )
                  })}
                </div>
            </aside>
          </div>
        </section>
          ) : null}

          {activePage === 'settings' ? (
        <section className="settings-layout">
          <section className="panel">
            <div className="panel-title">
              <KeyRound size={18} />
              <h2>个人账号</h2>
            </div>
            <label>
              学号
              <input
                value={settings.account}
                onChange={(event) => updateSetting('account', event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') saveCurrentSettings()
                }}
                inputMode="numeric"
                placeholder="可使用环境变量"
              />
            </label>
            <label>
              教务密码
              <input
                value={settings.password}
                onChange={(event) => updateSetting('password', event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') saveCurrentSettings()
                }}
                type="password"
                placeholder={settings.hasSavedPassword ? '已安全保存，留空保持不变' : '输入后保存到系统凭据存储'}
                autoComplete="new-password"
              />
            </label>
          </section>

          <section className="panel">
            <div className="panel-title">
              <CalendarDays size={18} />
              <h2>学期设置</h2>
            </div>
            <label>
              学期
              <input
                value={settings.termId}
                onChange={(event) => updateSetting('termId', event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') saveCurrentSettings()
                }}
              />
            </label>
            <label>
              第一周周一
              <input
                type="date"
                value={settings.termStartDate}
                min="2020-01-01"
                max="2035-12-31"
                onChange={(event) => updateSetting('termStartDate', event.target.value)}
              />
            </label>
          </section>

          <section className="panel">
            <div className="panel-title">
              <Building2 size={18} />
              <h2>查询默认值</h2>
            </div>
            <div className="field-group">
              默认校区
              <div className="campus-options">
                {(metadata.campuses || []).map((campus) => (
                  <button
                    key={campus.id}
                    type="button"
                    className={settings.campusId === campus.id ? 'active' : ''}
                    onClick={() => updateSetting('campusId', campus.id)}
                  >
                    <MapPin size={15} />
                    {campus.name}
                  </button>
                ))}
              </div>
            </div>
            <label>
              默认最少座位
              <input
                type="number"
                min="0"
                value={settings.defaultMinSeats}
                onChange={(event) => updateSetting('defaultMinSeats', Number(event.target.value))}
              />
            </label>
          </section>

          <section className="panel">
            <div className="panel-title">
              <BellRing size={18} />
              <h2>课程提醒</h2>
            </div>
            <label className="settings-toggle">
              <span>每天 07:30 课程摘要</span>
              <input
                type="checkbox"
                checked={settings.dailyCourseNotificationsEnabled}
                onChange={(event) => updateSetting('dailyCourseNotificationsEnabled', event.target.checked)}
              />
            </label>
          </section>

          <section className="panel settings-actions">
            <button type="button" className="primary" onClick={saveCurrentSettings} disabled={!settingsLoaded || settingsSaving || !!loading}>
              {settingsSaving ? <Loader2 className="spin" size={17} /> : <CheckCircle2 size={17} />}
              保存设置
            </button>
            <button type="button" className="secondary" onClick={openDesktopWidget} disabled={settingsSaving || !!loading}>
              {loading === 'widget' ? <Loader2 className="spin" size={17} /> : <CalendarDays size={17} />}
              打开课程小组件
            </button>
            {settingsSaved ? <span>已保存</span> : null}
          </section>

          <section className="panel settings-actions settings-local-data">
            <div className="panel-title">
              <HardDrive size={18} />
              <h2>本地数据</h2>
            </div>
            <p className="settings-local-data-note">清除已保存的教务账户与密码、个人课表、空教室和节假日缓存，并恢复本地设置。</p>
            <button
              type="button"
              className="danger"
              onClick={() => setClearConfirmationOpen(true)}
              disabled={settingsSaving || !!loading}
            >
              <Trash2 size={17} />
              清除本地数据
            </button>
            {clearConfirmationOpen ? (
              <div className="clear-data-confirmation" role="alertdialog" aria-labelledby="clear-data-title">
                <strong id="clear-data-title">清除全部本地数据？</strong>
                <p>将删除保存的账号、密码、个人课表、空教室缓存和设置。此操作无法撤销。</p>
                <div>
                  <button ref={clearCancelButtonRef} type="button" className="secondary" onClick={() => setClearConfirmationOpen(false)} disabled={settingsSaving || !!loading}>
                    取消
                  </button>
                  <button type="button" className="danger" onClick={clearAllLocalData} disabled={settingsSaving || !!loading}>
                    {loading === 'clear-local-data' ? <Loader2 className="spin" size={17} /> : <Trash2 size={17} />}
                    确认清除
                  </button>
                </div>
              </div>
            ) : null}
          </section>

          <section className="panel settings-about">
            <div className="panel-title">
              <Info size={18} />
              <h2>关于本应用</h2>
            </div>
            <p>Where To Study 是独立开发的非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。</p>
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
                隐私说明
              </button>
              <a href={PROJECT_URL} target="_blank" rel="noreferrer">
                <ExternalLink size={16} />
                GitHub 项目
              </a>
            </div>
          </section>
        </section>
          ) : null}
        </section>
      </div>
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
