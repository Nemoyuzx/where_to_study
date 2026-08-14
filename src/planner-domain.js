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
export const CALENDAR_WEEKDAYS = ['日', '一', '二', '三', '四', '五', '六']
export const CALENDAR_VIEWS = [
  { id: 'day', label: '日' },
  { id: 'week', label: '周' },
  { id: 'month', label: '月' },
  { id: 'year', label: '年' },
]
export const CALENDAR_START_HOUR = 8
export const CALENDAR_END_HOUR = 22
export const CALENDAR_VISIBLE_MINUTES = (CALENDAR_END_HOUR - CALENDAR_START_HOUR) * 60
export const DEFAULT_SETTINGS = {
  account: '',
  password: '',
  hasSavedPassword: false,
  termId: '2025-2026-2',
  termStartDate: '2026-03-02',
  campusId: '01',
  defaultMinSeats: 0,
  dailyCourseNotificationsEnabled: false,
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
  return new Date(`${dateString}T00:00:00`)
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

export function calendarSwipeDirection(deltaX, deltaY, threshold = 56) {
  if (Math.abs(deltaX) < threshold || Math.abs(deltaX) <= Math.abs(deltaY) * 1.2) {
    return 0
  }
  return deltaX < 0 ? 1 : -1
}

export function startOfWeekSunday(dateString) {
  const date = dateFromString(dateString)
  date.setDate(date.getDate() - date.getDay())
  return localDateString(date)
}

export function buildMonthDays(dateString) {
  const date = dateFromString(dateString)
  const first = new Date(date.getFullYear(), date.getMonth(), 1)
  first.setDate(first.getDate() - first.getDay())
  return Array.from({ length: 42 }, (_, index) => localDateString(new Date(first.getFullYear(), first.getMonth(), first.getDate() + index)))
}

export function buildMiniMonthDays(year, monthIndex) {
  const first = new Date(year, monthIndex, 1)
  first.setDate(first.getDate() - first.getDay())
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

export function savedSettingsToState(data = {}, fallback = DEFAULT_SETTINGS) {
  return {
    account: data.account ?? fallback.account ?? '',
    password: '',
    hasSavedPassword: Boolean(data.has_saved_password),
    termId: data.term_id || fallback.termId || DEFAULT_SETTINGS.termId,
    termStartDate: data.term_start_date || fallback.termStartDate || DEFAULT_SETTINGS.termStartDate,
    campusId: data.campus_id || fallback.campusId || DEFAULT_SETTINGS.campusId,
    defaultMinSeats: Number(data.default_min_seats ?? fallback.defaultMinSeats ?? 0) || 0,
    dailyCourseNotificationsEnabled: Boolean(
      data.daily_course_notifications_enabled
      ?? fallback.dailyCourseNotificationsEnabled
      ?? false,
    ),
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
    default_min_seats: Number(settings.defaultMinSeats) || 0,
    daily_course_notifications_enabled: Boolean(settings.dailyCourseNotificationsEnabled),
  }
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

export function getScheduleExamWeeks(courses) {
  const existingWeeks = [...new Set(
    courses.flatMap((course) => Array.isArray(course.week_numbers) ? course.week_numbers : [])
      .filter((week) => Number.isFinite(week) && week > 0),
  )].sort((a, b) => a - b)
  return [existingWeeks[16], existingWeeks[17]].filter(Boolean)
}

function isExamCourseOccurrence(course, weekNumber, scheduleExamWeeks) {
  const savedExamWeeks = Array.isArray(course.exam_week_numbers) ? course.exam_week_numbers : []
  return savedExamWeeks.includes(weekNumber) || scheduleExamWeeks.includes(weekNumber)
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
  const weekNumber = Math.max(0, Math.floor(days / 7) + 1)
  const weekday = target.getDay() === 0 ? 7 : target.getDay()
  const scheduleExamWeeks = getScheduleExamWeeks(courses)
  const dayCourses = courses
    .filter((course) => course.weekday === weekday && course.week_numbers.includes(weekNumber))
    .map((course) => ({
      ...course,
      is_exam: isExamCourseOccurrence(course, weekNumber, scheduleExamWeeks),
    }))
    .sort((a, b) => a.start_slot - b.start_slot || a.name.localeCompare(b.name, 'zh-Hans-CN'))
  const busySlots = [...new Set(dayCourses.flatMap((course) => {
    const slots = []
    for (let slot = course.start_slot; slot <= course.end_slot; slot += 1) slots.push(slot)
    return slots
  }))].sort((a, b) => a - b)
  return { weekNumber, weekday, busySlots, dayCourses }
}

export function formatTeachingWeek(weekNumber) {
  return weekNumber > 0 ? `第 ${weekNumber} 周` : '非教学周'
}

export function slotsToRanges(slots, slotMeta) {
  if (!slots.length) return []
  const sorted = [...new Set(slots)].sort((a, b) => a - b)
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
