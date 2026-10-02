export const SHUTTLE_WEEKDAYS = Object.freeze([
  { key: 'monday', label: '周一', english: 'Mon' },
  { key: 'tuesday', label: '周二', english: 'Tue' },
  { key: 'wednesday', label: '周三', english: 'Wed' },
  { key: 'thursday', label: '周四', english: 'Thu' },
  { key: 'friday', label: '周五', english: 'Fri' },
  { key: 'saturday', label: '周六', english: 'Sat' },
  { key: 'sunday', label: '周日', english: 'Sun' },
])

export const IMPORTANT_EVENT_TYPES = Object.freeze([
  'competition',
  'conference',
  'journal_special_issue',
  'hackathon',
  'summer_camp',
  'pre_admission',
])

export const IMPORTANT_EVENT_BATCH_SIZE = 20

export function filterAssignmentQueries(items, { query = '', course = '', range = 'all', now = new Date() } = {}) {
  const needle = query.trim().toLowerCase()
  return items.filter(item => {
    if (course && item.course_name !== course) return false
    if (needle && ![item.title, item.course_name, item.status].some(v => String(v || '').toLowerCase().includes(needle))) return false
    const deadline = deadlineTimestamp(item.deadline)
    return range === 'all' || (Number.isFinite(deadline) && (range === 'past' ? deadline < now.getTime() : deadline >= now.getTime()))
  }).sort((a, b) => (deadlineTimestamp(a.deadline) || Number.MAX_SAFE_INTEGER) - (deadlineTimestamp(b.deadline) || Number.MAX_SAFE_INTEGER) || String(a.id).localeCompare(String(b.id)))
}

export function nextImportantEventVisibleCount(
  currentCount,
  totalCount,
  batchSize = IMPORTANT_EVENT_BATCH_SIZE,
) {
  const total = Math.max(0, Math.trunc(Number(totalCount) || 0))
  const current = Math.max(0, Math.trunc(Number(currentCount) || 0))
  const batch = Math.max(1, Math.trunc(Number(batchSize) || IMPORTANT_EVENT_BATCH_SIZE))
  return Math.min(total, current + batch)
}

export function importantEventVisibleCount(renderWindow, renderKey, totalCount) {
  const requested = renderWindow?.key === renderKey
    ? renderWindow.count
    : IMPORTANT_EVENT_BATCH_SIZE
  return Math.min(
    Math.max(0, Math.trunc(Number(totalCount) || 0)),
    Math.max(0, Math.trunc(Number(requested) || 0)),
  )
}

export function shuttlePeriodKey(period = {}) {
  return `${period.start_date || 'unknown'}:${period.end_date || 'open'}:${period.label || ''}`
}

export function shuttlePeriodState(period = {}, today = '') {
  if (period.start_date && today < period.start_date) return 'upcoming'
  if (period.end_date && today > period.end_date) return 'ended'
  if (period.start_date && today >= period.start_date
    && (!period.end_date || today <= period.end_date)) return 'active'
  return 'unknown'
}

function verifiedShuttleSchedule(schedule) {
  return schedule?.parse_status === 'parsed'
    && Array.isArray(schedule.rows) && schedule.rows.length > 0
    && Boolean(schedule.from && schedule.to)
    && schedule.rows.some((row) => SHUTTLE_WEEKDAYS.some(({ key }) => row.services?.[key]))
}

export function selectShuttleNotice(payload = {}) {
  const items = Array.isArray(payload.items) ? payload.items : []
  const latest = items[0] || null
  const latestHasParsedSchedule = latest?.schedules?.some(
    verifiedShuttleSchedule,
  )
  const notice = latestHasParsedSchedule
    ? latest
    : items.find((item) => item.id === payload.last_parsed_notice_id) || null
  return {
    latest,
    notice,
    usingFallback: Boolean(latest && notice && latest.id !== notice.id),
  }
}

export function shuttlePeriods(notice) {
  const periods = new Map()
  ;(notice?.schedules || []).forEach((schedule) => {
    if (!verifiedShuttleSchedule(schedule)) return
    const key = shuttlePeriodKey(schedule.period)
    if (!periods.has(key)) periods.set(key, schedule.period)
  })
  return [...periods.entries()].map(([key, period]) => ({ key, period }))
}

export function defaultShuttlePeriodKey(periods, today) {
  return periods
    .filter(({ period }) => shuttlePeriodState(period, today) === 'active')
    .reduce((selected, candidate) => (
      !selected || candidate.period.start_date > selected.period.start_date
        ? candidate : selected
    ), null)?.key || ''
}

export function resolvedShuttleSelection({
  weekdaySelection,
  periodSelection,
  today,
  currentWeekday,
  noticeIdentity,
}) {
  return {
    weekday: weekdaySelection?.date === today ? weekdaySelection.key : currentWeekday,
    period: periodSelection?.date === today
      && periodSelection.noticeIdentity === noticeIdentity
      ? periodSelection.key : '',
  }
}

export function buildShuttleTimetable(payload = {}, today = '') {
  const { latest, notice, usingFallback } = selectShuttleNotice(payload)
  const holidayNotice = [latest, notice]
    .filter(Boolean)
    .flatMap((item) => (item.notes || []).map((text) => ({ text, source: item })))
    .find(({ text }) => /法定节假日|放假|假期/.test(text)) || null
  const periods = shuttlePeriods(notice).map(({ key, period }) => ({
    key,
    period,
    state: shuttlePeriodState(period, today),
    routes: (notice?.schedules || [])
      .filter((schedule) => shuttlePeriodKey(schedule.period) === key
        && verifiedShuttleSchedule(schedule))
      .map((schedule) => ({
        from: schedule.from,
        to: schedule.to,
        stop: notice?.stops?.find((item) => item.campus === schedule.from)?.location || '',
        rows: [...schedule.rows].sort((left, right) =>
          left.departure_time.localeCompare(right.departure_time)),
      })),
  })).filter(({ routes }) => routes.length > 0)
  return { latest, notice, usingFallback, holidayNotice, periods }
}

export function isLegalShuttleHoliday(items = [], today = '') {
  const todayItems = items.filter((item) => item.date === today)
  return todayItems.some((item) => item.type === 'holiday')
    && !todayItems.some((item) => item.type === 'workday')
}

export function departureMinutes(value) {
  const match = /^(\d{2}):([0-5]\d)$/.exec(String(value || ''))
  if (!match || Number(match[1]) > 23) return null
  return Number(match[1]) * 60 + Number(match[2])
}

export function buildShuttleDayView(payload, {
  today,
  weekday,
  nowMinutes = null,
  selectedPeriod = '',
  currentWeekday = shanghaiWeekdayKey(),
} = {}) {
  const { latest, notice, usingFallback } = selectShuttleNotice(payload)
  const periods = shuttlePeriods(notice)
  const fallbackPeriod = defaultShuttlePeriodKey(periods, today)
  const visiblePeriod = periods.some(({ key }) => key === selectedPeriod)
    ? selectedPeriod
    : fallbackPeriod
  const period = periods.find(({ key }) => key === visiblePeriod)?.period || null
  const periodState = period ? shuttlePeriodState(period, today) : 'unknown'
  const compareWithNow = weekday && weekday === currentWeekday
    && periodState === 'active'
    && Number.isInteger(nowMinutes)
  const schedules = periodState === 'active' ? (notice?.schedules || []).filter((schedule) => (
    shuttlePeriodKey(schedule.period) === visiblePeriod
      && verifiedShuttleSchedule(schedule)
  )) : []
  const routes = schedules.map((schedule) => {
    const departures = schedule.rows.flatMap((row) => {
      const service = row.services?.[weekday]
      return service ? [{ departureTime: row.departure_time, service }] : []
    }).sort((left, right) => left.departureTime.localeCompare(right.departureTime))
    const nextIndex = compareWithNow
      ? departures.findIndex(({ departureTime }) => (
        (departureMinutes(departureTime) ?? -1) > nowMinutes
      ))
      : -1
    return {
      from: schedule.from || '',
      to: schedule.to || '',
      stop: notice?.stops?.find((item) => item.campus === schedule.from)?.location || '',
      departures: departures.map((departure, index) => {
        const minutes = departureMinutes(departure.departureTime)
        const departed = compareWithNow && minutes !== null && minutes <= nowMinutes
        return {
          ...departure,
          departed,
          next: !departed && index === nextIndex,
        }
      }),
    }
  })
  return {
    latest,
    notice,
    usingFallback,
    periods,
    visiblePeriod,
    period,
    periodState,
    routes,
  }
}

export function shanghaiWeekdayKey(date = new Date()) {
  const label = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Shanghai',
    weekday: 'short',
  }).format(date).toLowerCase()
  return {
    mon: 'monday',
    tue: 'tuesday',
    wed: 'wednesday',
    thu: 'thursday',
    fri: 'friday',
    sat: 'saturday',
    sun: 'sunday',
  }[label.slice(0, 3)] || 'monday'
}

export function shanghaiClockMinutes(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Shanghai',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(date)
  const hour = Number(parts.find((part) => part.type === 'hour')?.value)
  const minute = Number(parts.find((part) => part.type === 'minute')?.value)
  return Number.isInteger(hour) && Number.isInteger(minute) ? hour * 60 + minute : null
}

function deadlineTimestamp(value) {
  // UCloud also returns timezone-less school-local timestamps. Interpret those
  // in Asia/Shanghai even when the desktop itself is in a different timezone.
  const raw = String(value || '').trim()
  const normalized = /^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$/.test(raw)
    ? `${raw.replace(' ', 'T')}+08:00` : raw
  const timestamp = new Date(normalized).getTime()
  return Number.isFinite(timestamp) ? timestamp : null
}

export function importantEventFavorite(item = {}) {
  return {
    id: item.id,
    name: item.name,
    event_type: item.event_type,
    source_type: item.source_type,
    primary_deadline: item.primary_deadline,
    organizer: item.organizer || item.source_name || null,
    official_url: item.official_url || item.source_url || null,
    source_name: item.source_name || null,
    source_url: item.source_url || null,
    deadline_label: item.deadline_label || null,
    categories: Array.isArray(item.categories) ? [...item.categories] : [],
    tags: Array.isArray(item.tags) ? [...item.tags] : [],
    level: item.level || null,
    location: item.location || null,
    status: item.status || null,
    description: item.description || null,
    eligibility: item.eligibility || null,
    notes: item.notes || null,
    region: item.region || null,
    mode: item.mode || null,
    published_at: item.published_at || null,
    stale: Boolean(item.stale),
    archived: Boolean(item.archived),
  }
}

export function mergeImportantEventCatalog(liveItems, favoriteItems) {
  const merged = new Map()
  for (const items of [liveItems, favoriteItems]) {
    for (const item of Array.isArray(items) ? items : []) {
      if (!['contest_ddl', 'school_notice'].includes(item?.source_type)) continue
      const key = [item.source_type, item.id, item.primary_deadline].join('\u0000')
      if (!merged.has(key)) merged.set(key, item)
    }
  }
  return [...merged.values()]
}

export function importantEventFilterOptions(items, {
  type = 'all',
  source = 'all',
  includeExpired = false,
  now = new Date(),
} = {}) {
  const itemSource = Array.isArray(items) ? items : []
  const nowTimestamp = now.getTime()
  const supported = itemSource.filter((item) => (
    deadlineTimestamp(item.primary_deadline) !== null
      && IMPORTANT_EVENT_TYPES.includes(item.event_type)
      && ['contest_ddl', 'school_notice'].includes(item.source_type)
  ))
  const categoryItems = supported.filter((item) => {
    const timestamp = deadlineTimestamp(item.primary_deadline)
    return (type === 'all' || item.event_type === type)
      && (source === 'all'
        || (source === 'school' && item.source_type === 'school_notice')
        || (source === 'public' && item.source_type !== 'school_notice'))
      && (includeExpired || (timestamp >= nowTimestamp && !item.archived))
  })
  return {
    types: IMPORTANT_EVENT_TYPES.filter((value) =>
      supported.some((item) => item.event_type === value)),
    categories: [...new Set(categoryItems.flatMap((item) => item.categories || []))]
      .sort((left, right) => left.localeCompare(right, 'zh-Hans-CN')),
  }
}

export function filterImportantEvents(items, {
  query = '',
  type = 'all',
  category = 'all',
  source = 'all',
  includeExpired = false,
  now = new Date(),
} = {}) {
  const normalizedQuery = String(query).trim().toLocaleLowerCase()
  const nowTimestamp = now.getTime()
  return (Array.isArray(items) ? items : [])
    .filter((item) => {
      const timestamp = deadlineTimestamp(item.primary_deadline)
      if (timestamp === null
        || !IMPORTANT_EVENT_TYPES.includes(item.event_type)
        || !['contest_ddl', 'school_notice'].includes(item.source_type)) return false
      const haystack = [
        item.name,
        item.organizer,
        item.level,
        item.location,
        item.description,
        item.eligibility,
        item.notes,
        item.region,
        item.mode,
        item.status,
        item.deadline_label,
        item.source_name,
        ...(item.categories || []),
        ...(item.tags || []),
      ].filter(Boolean).join(' ').toLocaleLowerCase()
      return (!normalizedQuery || haystack.includes(normalizedQuery))
        && (type === 'all' || item.event_type === type)
        && (category === 'all' || item.categories?.includes(category))
        && (source === 'all'
          || (source === 'school' && item.source_type === 'school_notice')
          || (source === 'public' && item.source_type !== 'school_notice'))
        && (includeExpired || (timestamp >= nowTimestamp && !item.archived))
    })
    .sort((left, right) => (
      (deadlineTimestamp(left.primary_deadline) ?? Number.POSITIVE_INFINITY)
        - (deadlineTimestamp(right.primary_deadline) ?? Number.POSITIVE_INFINITY)
      || String(left.name).localeCompare(String(right.name), 'zh-Hans-CN')
    ))
}
