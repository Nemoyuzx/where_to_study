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

export function selectShuttleNotice(payload = {}) {
  const items = Array.isArray(payload.items) ? payload.items : []
  const latest = items[0] || null
  const latestHasParsedSchedule = latest?.schedules?.some(
    (schedule) => schedule.parse_status === 'parsed' && schedule.rows?.length,
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
    const key = shuttlePeriodKey(schedule.period)
    if (!periods.has(key)) periods.set(key, schedule.period)
  })
  return [...periods.entries()].map(([key, period]) => ({ key, period }))
}

export function defaultShuttlePeriodKey(periods, today) {
  return periods.find(({ period }) => shuttlePeriodState(period, today) === 'active')?.key
    || ''
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
      && schedule.parse_status === 'parsed'
      && Array.isArray(schedule.rows)
  )) : []
  const routes = schedules.map((schedule) => {
    const departures = schedule.rows.flatMap((row) => {
      const service = row.services?.[weekday]
      return service ? [{ departureTime: row.departure_time, service }] : []
    })
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
  const timestamp = new Date(value).getTime()
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

export function importantEventFilterOptions(items) {
  const source = Array.isArray(items) ? items : []
  return {
    types: IMPORTANT_EVENT_TYPES.filter((type) => source.some((item) => item.event_type === type)),
    categories: [...new Set(source.flatMap((item) => item.categories || []))]
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
