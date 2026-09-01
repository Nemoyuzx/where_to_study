export const FALLBACK_SLOTS = [
  { index: 0, label: '1', start: '08:00', end: '08:45' },
  { index: 1, label: '2', start: '08:50', end: '09:35' },
  { index: 2, label: '3', start: '09:50', end: '10:35' },
  { index: 3, label: '4', start: '10:40', end: '11:25' },
  { index: 4, label: '5', start: '11:30', end: '12:15' },
  { index: 5, label: '6', start: '13:00', end: '13:45' },
  { index: 6, label: '7', start: '13:50', end: '14:35' },
  { index: 7, label: '8', start: '14:45', end: '15:30' },
  { index: 8, label: '9', start: '15:40', end: '16:25' },
  { index: 9, label: '10', start: '16:35', end: '17:20' },
  { index: 10, label: '11', start: '17:25', end: '18:10' },
  { index: 11, label: '12', start: '18:30', end: '19:15' },
  { index: 12, label: '13', start: '19:20', end: '20:05' },
  { index: 13, label: '14', start: '20:10', end: '20:55' },
]

export const WEEKDAY_LABELS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
export const CALENDAR_WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日']
export const CALENDAR_VIEWS = [
  { id: 'day', label: '日' },
  { id: 'week', label: '周' },
  { id: 'month', label: '月' },
  { id: 'year', label: '年' },
]
export const CALENDAR_START_HOUR = 8
export const CALENDAR_END_HOUR = 22
export const CALENDAR_VISIBLE_MINUTES = (CALENDAR_END_HOUR - CALENDAR_START_HOUR) * 60

const SHANGHAI_DATE_FORMAT = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Shanghai',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
})

// Beijing University of Posts and Telecommunications academic calendar:
// - Spring semester (term 2): starts early March, ends mid July
// - Fall semester (term 1): starts early September, ends mid January
const SPRING_MONTHS = [2, 3, 4, 5, 6, 7]

// The backend treats "today" as the Asia/Shanghai calendar date and rejects
// any other target_date, so app-facing date decisions must use Shanghai too.
export function shanghaiDateString(date = new Date()) {
  const parts = SHANGHAI_DATE_FORMAT.formatToParts(date)
  const get = (type) => parts.find((part) => part.type === type)?.value
  return `${get('year')}-${get('month')}-${get('day')}`
}

export const DEFAULT_SETTINGS = {
  account: '',
  password: '',
  hasSavedPassword: false,
  termId: '',
  termStartDate: '',
  campusId: '01',
  defaultMinSeats: 0,
  uiLanguage: 'system',
  dailyCourseNotificationsEnabled: false,
  automaticTermDetectionEnabled: true,
  weatherEnabled: true,
  almanacEnabled: true,
  competitionDeadlinesEnabled: true,
  conferenceDeadlinesEnabled: true,
  schoolContestNoticesEnabled: true,
  summerCampDeadlinesEnabled: true,
  hackathonDeadlinesEnabled: true,
  customDeadlinesEnabled: false,
  customDeadlinesUrl: '',
}

export const CAMPUS_BUILDINGS = Object.freeze({
  '01': Object.freeze(['教1', '教2', '教3', '教4', '主楼']),
  '04': Object.freeze(['综合教学楼N', '综合教学楼S', '教学实验综合楼N', '教学实验综合楼S', '智慧教学楼']),
})

const FALLBACK_HOLIDAY_PERIODS_2026 = [
  { name: '元旦', start: '2026-01-01', end: '2026-01-03' },
  { name: '春节', start: '2026-02-15', end: '2026-02-23' },
  { name: '清明节', start: '2026-04-04', end: '2026-04-06' },
  { name: '劳动节', start: '2026-05-01', end: '2026-05-05' },
  { name: '端午节', start: '2026-06-19', end: '2026-06-21' },
  { name: '中秋节', start: '2026-09-25', end: '2026-09-27' },
  { name: '国庆节', start: '2026-10-01', end: '2026-10-07' },
]

const FALLBACK_WORKDAY_ADJUSTMENTS_2026 = [
  { name: '元旦', date: '2026-01-04' },
  { name: '春节', date: '2026-02-14' },
  { name: '春节', date: '2026-02-28' },
  { name: '劳动节', date: '2026-05-09' },
  { name: '国庆节', date: '2026-09-20' },
  { name: '国庆节', date: '2026-10-10' },
]

export function localDateString(date = new Date()) {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

export function msUntilNextShanghaiMidnight(date = new Date()) {
  // Compute the next Asia/Shanghai midnight in absolute (UTC) time so the
  // result is correct regardless of the device timezone. Shanghai is fixed
  // at UTC+8 with no DST, so Shanghai midnight is 16:00 UTC of the previous
  // calendar day.
  const SHANGHAI_UTC_OFFSET_MS = 8 * 60 * 60 * 1000
  const utcNow = date.getTime()
  const shanghaiNow = utcNow + SHANGHAI_UTC_OFFSET_MS
  const shanghaiDate = new Date(shanghaiNow)
  const shanghaiDayStartUtc = Date.UTC(
    shanghaiDate.getUTCFullYear(),
    shanghaiDate.getUTCMonth(),
    shanghaiDate.getUTCDate(),
  )
  const nextShanghaiMidnightUtc = shanghaiDayStartUtc + 24 * 60 * 60 * 1000 - SHANGHAI_UTC_OFFSET_MS
  return Math.max(1000, nextShanghaiMidnightUtc - utcNow)
}

export function contractTimestamp(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z')
}

export function addDays(dateString, days) {
  const date = dateFromString(dateString)
  date.setDate(date.getDate() + days)
  return localDateString(date)
}

function dateRange(startDate, endDate) {
  const days = []
  let current = startDate
  while (current <= endDate) {
    days.push(current)
    current = addDays(current, 1)
  }
  return days
}

export function fallbackHolidayItems(year) {
  if (year !== 2026) return []
  const items = []

  FALLBACK_HOLIDAY_PERIODS_2026.forEach((holiday) => {
    dateRange(holiday.start, holiday.end).forEach((dateString) => {
      items.push({ date: dateString, name: holiday.name, type: 'holiday' })
    })
  })

  FALLBACK_WORKDAY_ADJUSTMENTS_2026.forEach((workday) => {
    items.push({ date: workday.date, name: workday.name, type: 'workday' })
  })

  return items
}

export function buildCalendarDayMap(items) {
  const map = new Map()
  items.forEach((item) => {
    const nextItems = map.get(item.date) || []
    nextItems.push({ name: item.name, type: item.type })
    map.set(item.date, nextItems)
  })
  return map
}

export function hasCalendarItemType(items, type) {
  return items.some((item) => item.type === type)
}

export function yearCourseOpacity(courseCount) {
  if (courseCount <= 0) return 0
  return 0.12 + (0.72 * courseCount) / (courseCount + 3)
}

export function formatShortDate(dateString) {
  const date = dateFromString(dateString)
  return `${date.getMonth() + 1}/${date.getDate()}`
}

export function dateFromString(dateString) {
  // Strict yyyy-MM-dd validation: reject impossible dates like 2026-02-30
  // instead of letting the JS engine silently roll them forward.
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateString || ''))
  if (!match) return new Date(NaN)
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  if (month < 1 || month > 12 || day < 1 || day > 31) return new Date(NaN)
  const date = new Date(year, month - 1, day)
  if (
    date.getFullYear() !== year
    || date.getMonth() !== month - 1
    || date.getDate() !== day
  ) {
    return new Date(NaN)
  }
  return date
}

export function builtInDeadlineSourcesEnabled(settings) {
  return Boolean(
    settings?.competitionDeadlinesEnabled
    || settings?.conferenceDeadlinesEnabled
    || settings?.schoolContestNoticesEnabled
    || settings?.summerCampDeadlinesEnabled
    || settings?.hackathonDeadlinesEnabled,
  )
}

export function deadlinePreheatPlan(settings, dateString) {
  if (!builtInDeadlineSourcesEnabled(settings)) return null
  const date = dateFromString(dateString)
  if (Number.isNaN(date.getTime())) return null
  const year = date.getFullYear()
  return {
    startDate: `${year}-01-01`,
    endDate: `${year}-12-31`,
  }
}

function lastDayOfMonth(year, monthIndex) {
  return new Date(year, monthIndex + 1, 0).getDate()
}

export function shiftDate(dateString, view, direction) {
  const date = dateFromString(dateString)
  if (view === 'day') {
    date.setDate(date.getDate() + direction)
  } else if (view === 'week') {
    date.setDate(date.getDate() + direction * 7)
  } else if (view === 'month') {
    const originalDay = date.getDate()
    date.setDate(1)
    date.setMonth(date.getMonth() + direction)
    date.setDate(Math.min(originalDay, lastDayOfMonth(date.getFullYear(), date.getMonth())))
  } else {
    const originalDay = date.getDate()
    const originalMonth = date.getMonth()
    date.setDate(1)
    date.setFullYear(date.getFullYear() + direction)
    date.setMonth(originalMonth)
    date.setDate(Math.min(originalDay, lastDayOfMonth(date.getFullYear(), originalMonth)))
  }
  return localDateString(date)
}

export function calendarSurfaceKey(view, dateString) {
  if (view === 'day') return `day:${dateString}`
  if (view === 'week') return `week:${startOfWeekMonday(dateString)}`
  if (view === 'month') return `month:${String(dateString || '').slice(0, 7)}`
  if (view === 'year') return `year:${String(dateString || '').slice(0, 4)}`
  return `${view}:${dateString}`
}

// ISO 8601: weeks start on Monday and week 1 is the week containing January 4.
// Use UTC calendar arithmetic so the displayed week never depends on the
// device timezone or daylight-saving transitions.
export function calendarWeekOfYear(dateString) {
  const date = dateFromString(dateString)
  if (Number.isNaN(date.getTime())) return 0
  const [year, month, day] = dateString.split('-').map(Number)
  const thursday = new Date(Date.UTC(year, month - 1, day))
  const isoWeekday = thursday.getUTCDay() || 7
  thursday.setUTCDate(thursday.getUTCDate() + 4 - isoWeekday)
  const isoYearStart = new Date(Date.UTC(thursday.getUTCFullYear(), 0, 1))
  return Math.ceil((((thursday - isoYearStart) / 86_400_000) + 1) / 7)
}

export function calendarTransition(currentDate, currentView, targetDate, targetView = currentView) {
  const currentViewIndex = CALENDAR_VIEWS.findIndex((item) => item.id === currentView)
  const targetViewIndex = CALENDAR_VIEWS.findIndex((item) => item.id === targetView)
  let motion = ''
  if (currentView !== targetView && currentViewIndex >= 0 && targetViewIndex >= 0) {
    motion = targetViewIndex > currentViewIndex ? 'next' : 'previous'
  } else if (
    currentDate !== targetDate
    && calendarSurfaceKey(currentView, currentDate) !== calendarSurfaceKey(targetView, targetDate)
  ) {
    motion = targetDate > currentDate ? 'next' : 'previous'
  }
  return {
    date: targetDate,
    view: targetView,
    motion,
    surfaceKey: calendarSurfaceKey(targetView, targetDate),
  }
}

export function calendarSwipeDirection(deltaX, deltaY, threshold = 56) {
  if (Math.abs(deltaX) < threshold || Math.abs(deltaX) <= Math.abs(deltaY) * 1.2) {
    return 0
  }
  return deltaX < 0 ? 1 : -1
}

export function calendarMonthExpansion(deltaX, deltaY, threshold = 48) {
  if (Math.abs(deltaY) < threshold || Math.abs(deltaY) <= Math.abs(deltaX) * 1.2) {
    return null
  }
  return deltaY > 0
}

export function calendarMonthDragProgress(startExpanded, deltaY, travelDistance) {
  const distance = Math.max(1, Math.abs(Number(travelDistance) || 0))
  const startProgress = typeof startExpanded === 'number'
    ? Math.max(0, Math.min(1, startExpanded))
    : startExpanded ? 1 : 0
  const progress = startProgress + (Number(deltaY) || 0) / distance
  return Math.max(0, Math.min(1, progress))
}

export function calendarMonthExpansionTarget(
  progress,
  velocityY = 0,
  velocityThreshold = 0.45,
) {
  const normalizedProgress = Math.max(0, Math.min(1, Number(progress) || 0))
  const normalizedVelocity = Number(velocityY) || 0
  const threshold = Math.max(0, Number(velocityThreshold) || 0)
  if (normalizedVelocity > threshold) return true
  if (normalizedVelocity < -threshold) return false
  return normalizedProgress >= 0.5
}

export function summarizeMonthEntries(entries, maxRows = 2) {
  const rowLimit = Math.max(1, Math.trunc(maxRows))
  const visibleCount = entries.length > rowLimit ? rowLimit - 1 : entries.length
  return {
    visible: entries.slice(0, visibleCount),
    hiddenCount: entries.length - visibleCount,
  }
}

export function desktopMonthGridMetrics(availableHeight) {
  const weekdayHeight = 30
  const normalizedHeight = Math.max(0, Math.floor(Number(availableHeight) || 0))
  const cellHeight = Math.max(Math.floor((normalizedHeight - weekdayHeight) / 6), 70)
  return {
    weekdayHeight,
    cellHeight,
    height: Math.max(normalizedHeight, 520),
    maximumEventRows: cellHeight >= 100 ? 4 : cellHeight >= 80 ? 3 : 2,
  }
}

const CALENDAR_DEADLINE_BORDER_PRIORITY = [
  'assignment',
  'school-notice',
  'competition-deadline',
  'conference-deadline',
  'summer-camp-deadline',
  'hackathon-deadline',
  'custom-deadline',
  'public-deadline',
]

export function calendarDeadlineVisualKind(entry = {}) {
  if (entry.type === 'assignment' || entry.source_type === 'assignment') return 'assignment'
  if (entry.type === 'school-notice' || entry.source_type === 'school_notice') return 'school-notice'
  if (entry.type === 'custom-deadline' || entry.source_type === 'custom') return 'custom-deadline'

  const type = entry.deadlineType || entry.event_type || entry.type
  if (type === 'competition' || type === 'competition-deadline') return 'competition-deadline'
  if (['conference', 'journal_special_issue', 'conference-deadline'].includes(type)) {
    return 'conference-deadline'
  }
  if (['summer_camp', 'pre_admission', 'summer-camp-deadline'].includes(type)) {
    return 'summer-camp-deadline'
  }
  if (type === 'hackathon' || type === 'hackathon-deadline') return 'hackathon-deadline'
  if (type === 'custom' || type === 'custom-deadline') return 'custom-deadline'
  return 'public-deadline'
}

export function calendarDeadlineBorderKinds(entries, limit = 2) {
  const visibleLimit = Math.max(0, Math.trunc(Number(limit) || 0))
  if (!visibleLimit) return []
  const presentKinds = new Set(entries.map(calendarDeadlineVisualKind))
  return CALENDAR_DEADLINE_BORDER_PRIORITY
    .filter((kind) => presentKinds.has(kind))
    .slice(0, visibleLimit)
}

export function calendarDeadlineBorderPriority(entries) {
  return calendarDeadlineBorderKinds(entries, 1)[0] || ''
}

export function calendarDeadlinePublicMarkerKind(entries) {
  return calendarDeadlineBorderKinds(
    entries.filter((entry) => !['assignment', 'school-notice'].includes(
      calendarDeadlineVisualKind(entry),
    )),
    1,
  )[0] || ''
}

export function expandedMonthGridMetrics(
  availableHeight,
  maximumRowHeight = 68,
  minimumRowHeight = 44,
  headerHeight = 30,
) {
  const usableHeight = Math.max(0, Number(availableHeight) || 0)
  const rowHeight = Math.max(
    minimumRowHeight,
    Math.min(maximumRowHeight, Math.floor((usableHeight - headerHeight) / 6)),
  )
  return {
    rowHeight,
    height: headerHeight + rowHeight * 6,
  }
}

export function startOfWeekMonday(dateString) {
  const date = dateFromString(dateString)
  date.setDate(date.getDate() - ((date.getDay() + 6) % 7))
  return localDateString(date)
}

export function buildMonthDays(dateString) {
  const date = dateFromString(dateString)
  const first = new Date(date.getFullYear(), date.getMonth(), 1)
  first.setDate(first.getDate() - ((first.getDay() + 6) % 7))
  return Array.from({ length: 42 }, (_, index) => localDateString(new Date(first.getFullYear(), first.getMonth(), first.getDate() + index)))
}

export function buildMiniMonthDays(year, monthIndex) {
  const first = new Date(year, monthIndex, 1)
  first.setDate(first.getDate() - ((first.getDay() + 6) % 7))
  return Array.from({ length: 42 }, (_, index) => localDateString(new Date(first.getFullYear(), first.getMonth(), first.getDate() + index)))
}

export function formatCalendarTitle(dateString, view) {
  const date = dateFromString(dateString)
  if (view === 'day') return `${date.getFullYear()}年 ${date.getMonth() + 1}月${date.getDate()}日`
  if (view === 'year') return `${date.getFullYear()}年`
  return `${date.getFullYear()}年 ${date.getMonth() + 1}月`
}

export function formatCourseDate(dateString) {
  const date = dateFromString(dateString)
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日 ${WEEKDAY_LABELS[(date.getDay() || 7) - 1]}`
}

export function parseTimeMinutes(value) {
  const [hours, minutes] = String(value || '00:00').split(':').map((item) => Number(item))
  return (Number.isFinite(hours) ? hours : 0) * 60 + (Number.isFinite(minutes) ? minutes : 0)
}

export function nonHourlyCourseBoundaryMinutes(
  slotMeta,
  startMinute = CALENDAR_START_HOUR * 60,
  endMinute = CALENDAR_END_HOUR * 60,
) {
  const boundaryMinutes = (Array.isArray(slotMeta) ? slotMeta : [])
    .flatMap((slot) => [slot?.start, slot?.end])
    .map((value) => {
      const match = /^(\d{2}):([0-5]\d)$/.exec(String(value || ''))
      if (!match) return null
      const hour = Number(match[1])
      if (hour > 23) return null
      return hour * 60 + Number(match[2])
    })
    .filter((minute) => (
      minute != null
      && minute >= startMinute
      && minute <= endMinute
      && minute % 60 !== 0
    ))
  return [...new Set(boundaryMinutes)].sort((left, right) => left - right)
}

export function courseTimeBounds(course, slotMeta) {
  const start = slotMeta[course.start_slot]?.start || '08:00'
  const end = slotMeta[course.end_slot]?.end || start
  return {
    start,
    end,
    startMinutes: parseTimeMinutes(start),
    endMinutes: parseTimeMinutes(end),
  }
}

function normalizeMinSeats(value) {
  const seats = Number(value)
  if (!Number.isFinite(seats)) return 0
  const integerSeats = Math.trunc(seats)
  return Number.isSafeInteger(integerSeats) ? Math.max(0, integerSeats) : 0
}

export function normalizeUiLanguage(value) {
  return ['system', 'zh-Hans', 'en'].includes(value) ? value : 'system'
}

export function resolvedUiLanguage(preference, systemLanguage = '') {
  const normalized = normalizeUiLanguage(preference)
  if (normalized !== 'system') return normalized
  return String(systemLanguage).toLowerCase().startsWith('zh') ? 'zh-Hans' : 'en'
}

export function savedSettingsToState(data = {}, fallback = DEFAULT_SETTINGS) {
  return {
    account: data.account ?? fallback.account ?? '',
    password: '',
    hasSavedPassword: Boolean(data.has_saved_password),
    termId: data.term_id || fallback.termId || DEFAULT_SETTINGS.termId,
    termStartDate: data.term_start_date || fallback.termStartDate || DEFAULT_SETTINGS.termStartDate,
    campusId: data.campus_id || fallback.campusId || DEFAULT_SETTINGS.campusId,
    defaultMinSeats: normalizeMinSeats(data.default_min_seats ?? fallback.defaultMinSeats ?? 0),
    uiLanguage: normalizeUiLanguage(data.ui_language ?? fallback.uiLanguage ?? 'system'),
    dailyCourseNotificationsEnabled: Boolean(
      data.daily_course_notifications_enabled
      ?? fallback.dailyCourseNotificationsEnabled
      ?? false,
    ),
    automaticTermDetectionEnabled: Boolean(
      data.automatic_term_detection_enabled
      ?? fallback.automaticTermDetectionEnabled
      ?? true,
    ),
    weatherEnabled: Boolean(data.weather_enabled ?? fallback.weatherEnabled ?? true),
    almanacEnabled: Boolean(data.almanac_enabled ?? fallback.almanacEnabled ?? true),
    competitionDeadlinesEnabled: Boolean(
      data.competition_deadlines_enabled ?? fallback.competitionDeadlinesEnabled ?? true,
    ),
    conferenceDeadlinesEnabled: Boolean(
      data.conference_deadlines_enabled ?? fallback.conferenceDeadlinesEnabled ?? true,
    ),
    schoolContestNoticesEnabled: Boolean(
      data.school_contest_notices_enabled ?? fallback.schoolContestNoticesEnabled ?? true,
    ),
    summerCampDeadlinesEnabled: Boolean(
      data.summer_camp_deadlines_enabled ?? fallback.summerCampDeadlinesEnabled ?? true,
    ),
    hackathonDeadlinesEnabled: Boolean(
      data.hackathon_deadlines_enabled ?? fallback.hackathonDeadlinesEnabled ?? true,
    ),
    customDeadlinesEnabled: Boolean(
      data.custom_deadlines_enabled ?? fallback.customDeadlinesEnabled ?? false,
    ),
    customDeadlinesUrl: String(
      data.custom_deadlines_url ?? fallback.customDeadlinesUrl ?? '',
    ).trim(),
  }
}

/**
 * Resolve startup settings without depending on which asynchronous command
 * finishes first. Saved values win, metadata only fills empty fields, and an
 * automatic term advances to the current Shanghai-date suggestion. Only a
 * same-term schedule cache may retain a different start date, because saved
 * settings alone cannot prove whether a date came from the academic system or
 * from an earlier calendar fallback.
 */
export function startupSettingsToState(
  data = {},
  metadata = {},
  cachedSchedule = null,
  date = new Date(),
) {
  const suggested = suggestTermForDate(date)
  const fallback = {
    ...DEFAULT_SETTINGS,
    campusId: metadata.campuses?.[0]?.id || DEFAULT_SETTINGS.campusId,
  }
  const settings = savedSettingsToState(data, fallback)
  if (!settings.automaticTermDetectionEnabled) return settings

  const cachedTermIsCurrent = isValidTermId(cachedSchedule?.term_id)
    && cachedSchedule.term_id.trim() === suggested.termId
    && isValidTermStartDate(cachedSchedule?.term_start_date)
  if (cachedTermIsCurrent) {
    return {
      ...settings,
      termId: cachedSchedule.term_id.trim(),
      termStartDate: cachedSchedule.term_start_date.trim(),
    }
  }

  return {
    ...settings,
    termId: suggested.termId,
    termStartDate: suggested.termStartDate,
  }
}

/** Apply authoritative term metadata returned by a successful schedule fetch. */
export function settingsWithScheduleTerm(settings, schedule) {
  if (!settings.automaticTermDetectionEnabled
    || !isValidTermId(schedule?.term_id)
    || !isValidTermStartDate(schedule?.term_start_date)) {
    return settings
  }
  return {
    ...settings,
    termId: schedule.term_id.trim(),
    termStartDate: schedule.term_start_date.trim(),
  }
}

/**
 * Automatic refreshes use a current Shanghai-date fallback. Manual mode keeps
 * the exact term fields entered by the user.
 */
export function scheduleRequestTerm(settings, date = new Date()) {
  if (settings.automaticTermDetectionEnabled) {
    const suggested = suggestTermForDate(date)
    if (isValidTermId(settings.termId)
      && settings.termId.trim() === suggested.termId
      && isValidTermStartDate(settings.termStartDate)) {
      return {
        termId: suggested.termId,
        termStartDate: settings.termStartDate.trim(),
      }
    }
    return suggested
  }
  return {
    termId: settings.termId,
    termStartDate: settings.termStartDate,
  }
}

export function savedCredentialSnapshot(settings) {
  return {
    account: settings.account.trim(),
    hasSavedPassword: settings.hasSavedPassword,
  }
}

export function accountHasSavedPassword(account, savedCredential) {
  return savedCredential.hasSavedPassword
    && account.trim() === savedCredential.account
}

export function settingsToPayload(settings) {
  return {
    account: settings.account,
    password: settings.password || null,
    term_id: settings.termId,
    term_start_date: settings.termStartDate,
    campus_id: settings.campusId,
    default_min_seats: normalizeMinSeats(settings.defaultMinSeats),
    ui_language: normalizeUiLanguage(settings.uiLanguage),
    daily_course_notifications_enabled: Boolean(settings.dailyCourseNotificationsEnabled),
    automatic_term_detection_enabled: Boolean(settings.automaticTermDetectionEnabled),
    weather_enabled: Boolean(settings.weatherEnabled),
    almanac_enabled: Boolean(settings.almanacEnabled),
    competition_deadlines_enabled: Boolean(settings.competitionDeadlinesEnabled),
    conference_deadlines_enabled: Boolean(settings.conferenceDeadlinesEnabled),
    school_contest_notices_enabled: Boolean(settings.schoolContestNoticesEnabled),
    summer_camp_deadlines_enabled: Boolean(settings.summerCampDeadlinesEnabled),
    hackathon_deadlines_enabled: Boolean(settings.hackathonDeadlinesEnabled),
    custom_deadlines_enabled: Boolean(settings.customDeadlinesEnabled),
    custom_deadlines_url: String(settings.customDeadlinesUrl || '').trim(),
  }
}

const FAVORITE_DEADLINE_TYPES = new Set([
  'competition',
  'conference',
  'journal_special_issue',
  'hackathon',
  'summer_camp',
  'pre_admission',
  'custom',
])
const FAVORITE_DEADLINE_SOURCES = new Set(['contest_ddl', 'school_notice', 'custom'])

export function favoriteDeadlineKey(item = {}) {
  const sourceIdentity = item.source_type === 'custom'
    ? (item.source_url || item.source_name || '')
    : ''
  return [item.source_type, sourceIdentity, item.id, item.primary_deadline]
    .map((value) => String(value || ''))
    .join('\u001f')
}

function normalizedFavoriteText(value, maximumLength) {
  const text = typeof value === 'string' ? value.trim() : ''
  return text && text.length <= maximumLength ? text : null
}

function normalizedFavoriteLabels(value, maximumItems = 32, maximumLength = 80) {
  if (!Array.isArray(value)) return []
  return [...new Set(value.flatMap((entry) => {
    const text = normalizedFavoriteText(entry, maximumLength)
    return text ? [text] : []
  }))].slice(0, maximumItems)
}

export function normalizeFavoriteDeadlines(value, maximum = 500) {
  const source = Array.isArray(value) ? value : []
  const seen = new Set()
  const result = []
  source.forEach((item) => {
    if (!item || typeof item !== 'object' || result.length >= maximum) return
    const normalized = {
      id: String(item.id || '').trim(),
      name: String(item.name || '').trim(),
      event_type: String(item.event_type || '').trim(),
      source_type: String(item.source_type || '').trim(),
      primary_deadline: String(item.primary_deadline || '').trim(),
      organizer: normalizedFavoriteText(item.organizer, 200),
      official_url: normalizedFavoriteText(item.official_url, 2_048),
      source_name: normalizedFavoriteText(item.source_name, 120),
      source_url: normalizedFavoriteText(item.source_url, 2_048),
      deadline_label: normalizedFavoriteText(item.deadline_label, 80),
      categories: normalizedFavoriteLabels(item.categories),
      tags: normalizedFavoriteLabels(item.tags),
      level: normalizedFavoriteText(item.level, 120),
      location: normalizedFavoriteText(item.location, 200),
      status: normalizedFavoriteText(item.status, 64),
      description: normalizedFavoriteText(item.description, 2_000),
      eligibility: normalizedFavoriteText(item.eligibility, 500),
      notes: normalizedFavoriteText(item.notes, 4_000),
      region: normalizedFavoriteText(item.region, 80),
      mode: normalizedFavoriteText(item.mode, 80),
      published_at: normalizedFavoriteText(item.published_at, 64),
      stale: Boolean(item.stale),
      archived: Boolean(item.archived),
    }
    if (!normalized.id || normalized.id.length > 128
      || !normalized.name || normalized.name.length > 200
      || !FAVORITE_DEADLINE_TYPES.has(normalized.event_type)
      || !FAVORITE_DEADLINE_SOURCES.has(normalized.source_type)
      || !/^\d{4}-\d{2}-\d{2}T/.test(normalized.primary_deadline)) return
    if (normalized.official_url
      && (!normalized.official_url.startsWith('https://') || normalized.official_url.includes('@'))) {
      normalized.official_url = null
    }
    if (normalized.source_url
      && (!normalized.source_url.startsWith('https://') || normalized.source_url.includes('@'))) {
      normalized.source_url = null
    }
    const key = favoriteDeadlineKey(normalized)
    if (!seen.has(key)) {
      seen.add(key)
      result.push(normalized)
    }
  })
  return result.sort((left, right) => (
    left.primary_deadline.localeCompare(right.primary_deadline)
      || left.name.localeCompare(right.name)
  ))
}

export function favoriteDeadlinesForDate(items, dateString) {
  return normalizeFavoriteDeadlines(items).filter((item) => item.primary_deadline.startsWith(dateString))
}

export function requestBody(settings, extras = {}) {
  return {
    account: settings.account.trim() || null,
    password: settings.password || null,
    ...extras,
  }
}

export function normalizeCampusId(campusId) {
  const value = String(campusId || DEFAULT_SETTINGS.campusId).trim()
  if (/^\d+$/.test(value)) return value.padStart(2, '0')
  return value
}

export function buildingsForCampus(campusId) {
  return [...(CAMPUS_BUILDINGS[normalizeCampusId(campusId)] || [])]
}

export function normalizeClassroomsCache(data) {
  if (!data) return null
  if (Array.isArray(data.campuses)) return data
  if (Array.isArray(data.rooms)) {
    return {
      cache_version: data.cache_version || 0,
      target_date: data.target_date || localDateString(),
      fetched_at: data.fetched_at || '',
      realtime: data.realtime ?? true,
      provider: data.provider || 'sjd',
      campuses: [data],
    }
  }
  return null
}

export function getCampusClassrooms(cache, campusId) {
  const normalizedCampusId = normalizeCampusId(campusId)
  return (cache?.campuses || []).find((campus) => normalizeCampusId(campus.campus_id) === normalizedCampusId) || null
}

export function normalizeError(error) {
  if (typeof error === 'string') return error
  if (error?.message) return error.message
  return '请求失败，请稍后重试。'
}

export function isValidAccountScope(value) {
  return /^opaque-v1:[0-9a-f]{64}$/.test(String(value || ''))
}

function dateOrdinal(dateString) {
  const [year, month, day] = dateString.split('-').map(Number)
  return Math.floor(Date.UTC(year, month - 1, day) / 86_400_000)
}

export function getWeekState(courses, termStartDate, targetDate) {
  if (!termStartDate || !targetDate) {
    return { weekNumber: 0, weekday: 0, busySlots: [], dayCourses: [] }
  }
  const target = dateFromString(targetDate)
  const days = dateOrdinal(targetDate) - dateOrdinal(termStartDate)
  const calculatedWeek = Math.max(0, Math.floor(days / 7) + 1)
  const maximumTeachingWeek = courses.reduce((maximum, course) => {
    const weeks = Array.isArray(course.week_numbers) ? course.week_numbers : []
    return Math.max(
      maximum,
      ...weeks.filter((week) => Number.isInteger(week) && week > 0),
    )
  }, 0)
  const weekNumber = calculatedWeek >= 1 && calculatedWeek <= maximumTeachingWeek
    ? calculatedWeek
    : 0
  const weekday = target.getDay() === 0 ? 7 : target.getDay()
  const dayCourses = courses
    .filter((course) => course.weekday === weekday
      && Array.isArray(course.week_numbers) && course.week_numbers.includes(weekNumber))
    .sort((a, b) => a.start_slot - b.start_slot || a.name.localeCompare(b.name, 'zh-Hans-CN'))
  const maxSlotIndex = FALLBACK_SLOTS.length - 1
  const busySlots = [...new Set(dayCourses.flatMap((course) => {
    const slots = []
    for (let slot = Math.max(0, course.start_slot); slot <= Math.min(course.end_slot, maxSlotIndex); slot += 1) slots.push(slot)
    return slots
  }))].sort((a, b) => a - b)
  return { weekNumber, weekday, busySlots, dayCourses }
}

export function formatTeachingWeek(weekNumber) {
  return weekNumber > 0 ? `第 ${weekNumber} 教学周` : '非教学周'
}

export function slotsToRanges(slots, slotMeta) {
  if (!slots.length) return []
  const validSlots = slots.filter((slot) => Number.isInteger(slot) && slot >= 0 && slot < slotMeta.length)
  if (!validSlots.length) return []
  const sorted = [...new Set(validSlots)].sort((a, b) => a - b)
  const ranges = []
  let start = sorted[0]
  let prev = sorted[0]
  for (const slot of sorted.slice(1)) {
    if (slot === prev + 1) {
      prev = slot
    } else {
      ranges.push({ start, end: prev, label: `${slotMeta[start].start}-${slotMeta[prev].end}` })
      start = slot
      prev = slot
    }
  }
  ranges.push({ start, end: prev, label: `${slotMeta[start].start}-${slotMeta[prev].end}` })
  return ranges
}

export function displayBuildingName(name) {
  return String(name || '').replaceAll('未来学习大楼', '主楼')
}


// ---------- Term (semester) auto-detection ----------

/** Monday of the week that contains the given date, independent of device TZ. */
function mondayOfWeekContaining(year, month, day) {
  const date = new Date(Date.UTC(year, month - 1, day))
  const offset = (date.getUTCDay() + 6) % 7 // days since Monday
  date.setUTCDate(date.getUTCDate() - offset)
  return date.toISOString().slice(0, 10)
}

/**
 * Suggest the current term id and term start date based on the calendar
 * date. Uses the standard BUPT schedule pattern (spring starts around
 * March 1, fall around September 1); the authoritative values come back
 * in the fetch_schedule response and are applied automatically after a
 * successful fetch.
 */
export function suggestTermForDate(date = new Date()) {
  const shanghaiDate = shanghaiDateString(date)
  const year = Number(shanghaiDate.slice(0, 4))
  const month = Number(shanghaiDate.slice(5, 7))
  if (SPRING_MONTHS.includes(month)) {
    // Spring semester starts around March 1-3; the week of March 2 is a
    // stable anchor (2026-03-02, 2025-02-24, 2024-02-26 all match).
    return {
      termId: (year - 1) + '-' + year + '-2',
      termStartDate: mondayOfWeekContaining(year, 3, 2),
    }
  }
  // Fall semester starts around September 1.
  // January still belongs to the fall term that started in the previous year.
  const fallStartYear = month === 1 ? year - 1 : year
  return {
    termId: fallStartYear + '-' + (fallStartYear + 1) + '-1',
    termStartDate: mondayOfWeekContaining(fallStartYear, 9, 1),
  }
}

/** Validate a term id like "2025-2026-2" or "2025-2026-1". */
export function isValidTermId(value) {
  return /^\d{4}-\d{4}-[12]$/.test(String(value || '').trim())
}

/** Validate a term start date as yyyy-MM-dd that parses to a real date. */
export function isValidTermStartDate(value) {
  const text = String(value || '').trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return false
  const parsed = dateFromString(text)
  return !Number.isNaN(parsed.getTime())
    && parsed.getFullYear() === Number(text.slice(0, 4))
    && parsed.getMonth() + 1 === Number(text.slice(5, 7))
    && parsed.getDate() === Number(text.slice(8, 10))
}

/** Return the user-facing validation error for manually entered term fields. */
export function manualTermValidationError(termId, termStartDate) {
  if (!String(termId || '').trim()) return '请填写学期编号。'
  if (!isValidTermId(termId)) {
    return '学期编号格式不正确，请使用 YYYY-YYYY-1 或 YYYY-YYYY-2。'
  }
  if (!String(termStartDate || '').trim()) return '请填写第一周周一日期。'
  if (!isValidTermStartDate(termStartDate)) {
    return '第一周周一日期格式不正确，请使用 yyyy-MM-dd。'
  }
  return ''
}

/**
 * True when the given term is the one suggested for the current period.
 */
export function termMatchesCurrentPeriod(termId, termStartDate, date = new Date()) {
  if (!isValidTermId(termId)) return false
  const suggested = suggestTermForDate(date)
  return String(termId).trim() === suggested.termId
    && String(termStartDate).trim() === suggested.termStartDate
}
