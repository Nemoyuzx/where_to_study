import { useEffect, useMemo, useRef, useState } from 'react'
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import {
  AlertTriangle,
  Building2,
  CalendarDays,
  CalendarPlus,
  CalendarRange,
  CheckCircle2,
  Clock3,
  Home,
  KeyRound,
  Loader2,
  MapPin,
  RefreshCw,
  Search,
  Settings,
  Sparkles,
} from 'lucide-react'
import './App.css'

const FALLBACK_SLOTS = [
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

const WEEKDAY_LABELS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
const CALENDAR_WEEKDAYS = ['日', '一', '二', '三', '四', '五', '六']
const CALENDAR_VIEWS = [
  { id: 'day', label: '日' },
  { id: 'week', label: '周' },
  { id: 'month', label: '月' },
  { id: 'year', label: '年' },
]
const CALENDAR_START_HOUR = 8
const CALENDAR_END_HOUR = 22
const DEFAULT_SETTINGS = {
  account: '',
  password: '',
  termId: '2025-2026-2',
  termStartDate: '2026-03-02',
  campusId: '01',
  defaultMinSeats: 0,
}

function localDateString(date = new Date()) {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

function addDays(dateString, days) {
  const date = new Date(`${dateString}T00:00:00`)
  date.setDate(date.getDate() + days)
  return localDateString(date)
}

function formatShortDate(dateString) {
  const date = new Date(`${dateString}T00:00:00`)
  return `${date.getMonth() + 1}/${date.getDate()}`
}

function dateFromString(dateString) {
  return new Date(`${dateString}T00:00:00`)
}

function shiftDate(dateString, view, direction) {
  const date = dateFromString(dateString)
  if (view === 'day') {
    date.setDate(date.getDate() + direction)
  } else if (view === 'week') {
    date.setDate(date.getDate() + direction * 7)
  } else if (view === 'month') {
    date.setMonth(date.getMonth() + direction)
  } else {
    date.setFullYear(date.getFullYear() + direction)
  }
  return localDateString(date)
}

function startOfWeekSunday(dateString) {
  const date = dateFromString(dateString)
  date.setDate(date.getDate() - date.getDay())
  return localDateString(date)
}

function buildMonthDays(dateString) {
  const date = dateFromString(dateString)
  const first = new Date(date.getFullYear(), date.getMonth(), 1)
  first.setDate(first.getDate() - first.getDay())
  return Array.from({ length: 42 }, (_, index) => localDateString(new Date(first.getFullYear(), first.getMonth(), first.getDate() + index)))
}

function buildMiniMonthDays(year, monthIndex) {
  const first = new Date(year, monthIndex, 1)
  first.setDate(first.getDate() - first.getDay())
  return Array.from({ length: 42 }, (_, index) => localDateString(new Date(first.getFullYear(), first.getMonth(), first.getDate() + index)))
}

function formatCalendarTitle(dateString, view) {
  const date = dateFromString(dateString)
  if (view === 'day') return `${date.getFullYear()}年 ${date.getMonth() + 1}月${date.getDate()}日`
  if (view === 'year') return `${date.getFullYear()}年`
  return `${date.getFullYear()}年 ${date.getMonth() + 1}月`
}

function formatCourseDate(dateString) {
  const date = dateFromString(dateString)
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日 ${WEEKDAY_LABELS[(date.getDay() || 7) - 1]}`
}

function parseTimeMinutes(value) {
  const [hours, minutes] = String(value || '00:00').split(':').map((item) => Number(item))
  return (Number.isFinite(hours) ? hours : 0) * 60 + (Number.isFinite(minutes) ? minutes : 0)
}

function courseTimeBounds(course, slotMeta) {
  const start = slotMeta[course.start_slot]?.start || '08:00'
  const end = slotMeta[course.end_slot]?.end || start
  return {
    start,
    end,
    startMinutes: parseTimeMinutes(start),
    endMinutes: parseTimeMinutes(end),
  }
}

function savedSettingsToState(data = {}, fallback = DEFAULT_SETTINGS) {
  return {
    account: data.account ?? fallback.account ?? '',
    password: data.password ?? fallback.password ?? '',
    termId: data.term_id || fallback.termId || DEFAULT_SETTINGS.termId,
    termStartDate: data.term_start_date || fallback.termStartDate || DEFAULT_SETTINGS.termStartDate,
    campusId: data.campus_id || fallback.campusId || DEFAULT_SETTINGS.campusId,
    defaultMinSeats: Number(data.default_min_seats ?? fallback.defaultMinSeats ?? 0) || 0,
  }
}

function settingsToPayload(settings) {
  return {
    account: settings.account,
    password: settings.password,
    term_id: settings.termId,
    term_start_date: settings.termStartDate,
    campus_id: settings.campusId,
    default_min_seats: Number(settings.defaultMinSeats) || 0,
  }
}

function requestBody(settings, extras = {}) {
  return {
    account: settings.account.trim() || null,
    password: settings.password || null,
    ...extras,
  }
}

function normalizeError(error) {
  if (typeof error === 'string') return error
  if (error?.message) return error.message
  return '请求失败，请稍后重试。'
}

async function command(name, payload) {
  try {
    if (payload === undefined) return await invoke(name)
    return await invoke(name, { payload })
  } catch (error) {
    throw new Error(normalizeError(error))
  }
}

function getWeekState(courses, termStartDate, targetDate) {
  if (!termStartDate || !targetDate) {
    return { weekNumber: 0, weekday: 0, busySlots: [], dayCourses: [] }
  }
  const start = new Date(`${termStartDate}T00:00:00`)
  const target = new Date(`${targetDate}T00:00:00`)
  const days = Math.floor((target - start) / 86400000)
  const weekNumber = Math.floor(days / 7) + 1
  const weekday = target.getDay() === 0 ? 7 : target.getDay()
  const dayCourses = courses
    .filter((course) => course.weekday === weekday && course.week_numbers.includes(weekNumber))
    .sort((a, b) => a.start_slot - b.start_slot || a.name.localeCompare(b.name, 'zh-Hans-CN'))
  const busySlots = [...new Set(dayCourses.flatMap((course) => {
    const slots = []
    for (let slot = course.start_slot; slot <= course.end_slot; slot += 1) slots.push(slot)
    return slots
  }))].sort((a, b) => a - b)
  return { weekNumber, weekday, busySlots, dayCourses }
}

function slotsToRanges(slots, slotMeta) {
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

function displayBuildingName(name) {
  return String(name || '').replaceAll('未来学习大楼', '主楼')
}

function App() {
  const [activePage, setActivePage] = useState('planner')
  const [metadata, setMetadata] = useState({ campuses: [], slots: FALLBACK_SLOTS })
  const [settings, setSettings] = useState(() => ({ ...DEFAULT_SETTINGS }))
  const [calendarDate, setCalendarDate] = useState(localDateString())
  const [calendarView, setCalendarView] = useState('week')
  const [schedule, setSchedule] = useState(null)
  const [classrooms, setClassrooms] = useState(null)
  const [recommendations, setRecommendations] = useState(null)
  const [selectedSlots, setSelectedSlots] = useState([])
  const [selectedBuildings, setSelectedBuildings] = useState([])
  const [minSeats, setMinSeats] = useState(0)
  const [usePersonalSchedule, setUsePersonalSchedule] = useState(true)
  const [showRecommendationHighlight, setShowRecommendationHighlight] = useState(true)
  const [loading, setLoading] = useState('')
  const [error, setError] = useState('')
  const [settingsSaved, setSettingsSaved] = useState(false)
  const [settingsLoaded, setSettingsLoaded] = useState(false)
  const [calendarImportedPath, setCalendarImportedPath] = useState('')
  const autoFetchedClassroomsDate = useRef('')

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
        setMetadata({ campuses: [{ id: '01', name: '西土城' }], slots: FALLBACK_SLOTS })
      })
  }, [])

  useEffect(() => {
    let cancelled = false

    command('load_saved_settings')
      .then((data) => {
        if (cancelled) return
        const nextSettings = savedSettingsToState(data)
        setSettings(nextSettings)
        setMinSeats(Number(nextSettings.defaultMinSeats) || 0)
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
    let unlisten = null

    listen('tray:navigate', (event) => {
      if (['planner', 'calendar', 'settings'].includes(event.payload)) {
        setActivePage(event.payload)
      }
    }).then((dispose) => {
      unlisten = dispose
    })

    return () => {
      if (unlisten) unlisten()
    }
  }, [])

  useEffect(() => {
    let unlistenFetched = null
    let unlistenError = null

    listen('classrooms:auto-fetched', (event) => {
      setClassrooms(event.payload)
      setRecommendations(null)
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

  const slotMeta = metadata.slots?.length ? metadata.slots : FALLBACK_SLOTS
  const todayDate = localDateString()
  const courses = useMemo(() => (schedule ? schedule.courses : []), [schedule])
  const activeTermId = schedule?.term_id || settings.termId
  const activeTermStartDate = schedule?.term_start_date || settings.termStartDate
  const plannerWeekState = useMemo(
    () => getWeekState(courses, activeTermStartDate, todayDate),
    [courses, activeTermStartDate, todayDate],
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
    const names = [...new Set((classrooms?.rooms || []).map((room) => room.building))]
    return names.sort((a, b) => a.localeCompare(b, 'zh-Hans-CN'))
  }, [classrooms])
  const filteredRooms = useMemo(() => {
    return (classrooms?.rooms || [])
      .filter((room) => !selectedBuildings.length || selectedBuildings.includes(room.building))
      .filter((room) => !room.size || room.size >= minSeats)
      .filter((room) => selectedSlots.length > 0 && selectedSlots.every((slot) => room.available_slots.includes(slot)))
      .sort((a, b) => a.building.localeCompare(b.building, 'zh-Hans-CN') || a.room.localeCompare(b.room, 'zh-Hans-CN'))
  }, [classrooms, minSeats, selectedBuildings, selectedSlots])
  const selectedRanges = slotsToRanges(selectedSlots, slotMeta)
  const recommendationItems = useMemo(
    () => (recommendations ? recommendations.recommendations : []),
    [recommendations],
  )
  const recommendationByRoom = useMemo(
    () => new Map(recommendationItems.map((item) => [item.classroom.id, item])),
    [recommendationItems],
  )
  const canShowRecommendationHighlight = showRecommendationHighlight && recommendationItems.length > 0
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
  const calendarYearMonths = useMemo(() => {
    const year = dateFromString(calendarDate).getFullYear()
    return Array.from({ length: 12 }, (_, monthIndex) => ({
      monthIndex,
      label: `${monthIndex + 1}月`,
      days: buildMiniMonthDays(year, monthIndex),
    }))
  }, [calendarDate])
  const calendarDetailCourse = calendarWeekState.dayCourses[0] || null

  useEffect(() => {
    if (!settingsLoaded || autoFetchedClassroomsDate.current === todayDate) {
      return
    }

    autoFetchedClassroomsDate.current = todayDate
    loadClassrooms()
  }, [settingsLoaded, todayDate])

  useEffect(() => {
    let cancelled = false

    command('load_saved_schedule')
      .then((data) => {
        if (!cancelled && data) {
          setSchedule(data)
        }
      })
      .catch(() => {})

    return () => {
      cancelled = true
    }
  }, [])

  function updateSetting(field, value) {
    setSettingsSaved(false)
    setSettings((current) => ({ ...current, [field]: value }))
  }

  async function saveCurrentSettings() {
    setError('')
    setSettingsSaved(false)

    try {
      const data = await command('save_saved_settings', settingsToPayload(settings))
      const nextSettings = savedSettingsToState(data, settings)
      setSettings(nextSettings)
      setMinSeats(Number(nextSettings.defaultMinSeats) || 0)
      setSelectedBuildings([])
      setClassrooms(null)
      setRecommendations(null)
      setSettingsSaved(true)
    } catch (saveError) {
      setError(saveError.message)
    }
  }

  function toggleSlot(slotIndex) {
    setRecommendations(null)
    setSelectedSlots((current) => (
      current.includes(slotIndex)
        ? current.filter((slot) => slot !== slotIndex)
        : [...current, slotIndex].sort((a, b) => a - b)
    ))
  }

  function toggleBuilding(building) {
    setRecommendations(null)
    setSelectedBuildings((current) => (
      current.includes(building)
        ? current.filter((item) => item !== building)
        : [...current, building]
    ))
  }

  function togglePersonalSchedule() {
    const nextValue = !usePersonalSchedule
    setUsePersonalSchedule(nextValue)
    setRecommendations(null)
    if (nextValue) {
      setSelectedSlots((current) => current.filter((slot) => !plannerWeekState.busySlots.includes(slot)))
    }
  }

  function chooseCalendarDate(dateString) {
    setCalendarDate(dateString)
  }

  function moveCalendar(direction) {
    setCalendarDate((current) => shiftDate(current, calendarView, direction))
  }

  async function runTask(name, task) {
    setLoading(name)
    setError('')
    try {
      await task()
    } catch (taskError) {
      setError(taskError.message)
    } finally {
      setLoading('')
    }
  }

  async function loadSchedule() {
    await runTask('schedule', async () => {
      const data = await command('fetch_schedule', requestBody(settings, {
        term_id: settings.termId,
        term_start_date: settings.termStartDate,
      }))
      setSchedule(data)
      setCalendarImportedPath('')
      setUsePersonalSchedule(true)
      const nextState = getWeekState(data.courses, data.term_start_date, todayDate)
      const nextFreeSlots = slotMeta.map((slot) => slot.index).filter((slot) => !nextState.busySlots.includes(slot))
      setSelectedSlots(nextFreeSlots)
      setRecommendations(null)
    })
  }

  async function loadClassrooms() {
    await runTask('classrooms', async () => {
      const data = await command('fetch_classrooms', requestBody(settings, {
        campus_id: settings.campusId,
        target_date: todayDate,
      }))
      setClassrooms(data)
      setRecommendations(null)
    })
  }

  async function runRecommendations() {
    await runTask('recommendations', async () => {
      const data = await command('fetch_recommendations', requestBody(settings, {
        campus_id: settings.campusId,
        target_date: todayDate,
        term_id: settings.termId,
        term_start_date: settings.termStartDate,
        buildings: selectedBuildings,
        min_seats: Number(minSeats) || 0,
        use_schedule_filter: usePersonalSchedule,
      }))
      setClassrooms(data.classrooms)
      setSchedule({
        term_id: settings.termId,
        term_start_date: settings.termStartDate,
        fetched_at: data.classrooms.fetched_at,
        courses: data.schedule.courses,
      })
      setCalendarImportedPath('')
      setRecommendations(data)
      setShowRecommendationHighlight(true)
      setSelectedSlots(data.selected_slots)
    })
  }

  async function importAppleCalendar() {
    await runTask('calendar-import', async () => {
      const path = await command('import_schedule_to_calendar')
      setCalendarImportedPath(path)
    })
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
            <button type="button" className={activePage === 'planner' ? 'active' : ''} onClick={() => setActivePage('planner')}>
              <Home size={17} />
              空教室
            </button>
            <button type="button" className={activePage === 'calendar' ? 'active' : ''} onClick={() => setActivePage('calendar')}>
              <CalendarRange size={17} />
              教学日历
            </button>
            <button type="button" className={activePage === 'settings' ? 'active' : ''} onClick={() => setActivePage('settings')}>
              <Settings size={17} />
              设置
            </button>
          </nav>
        </aside>

        <section className="page-content">
          {activePage !== 'calendar' ? (
            <header className="topbar">
              <div>
                <p className="eyebrow">BUPT Classroom Planner</p>
                <h1>{activePage === 'settings' ? '设置' : '空教室与个人课表联动查询'}</h1>
              </div>
              <div className="status-pill">
                <Clock3 size={16} />
                <span>{todayDate}</span>
              </div>
            </header>
          ) : null}

          {error ? (
            <div className="notice error">
              <AlertTriangle size={18} />
              <span>{error}</span>
            </div>
          ) : null}

          {activePage === 'planner' ? (
        <div className="workspace planner-workspace">
          <aside className="control-panel">
            <section className="panel">
              <div className="panel-title">
                <CalendarDays size={18} />
                <h2>查询条件</h2>
              </div>
              <label>
                日期
                <input
                  type="date"
                  value={todayDate}
                  disabled
                />
              </label>
              <div className="field-group">
                校区
                <div className="campus-options">
                  {(metadata.campuses || []).map((campus) => (
                    <button
                      key={campus.id}
                      type="button"
                      className={settings.campusId === campus.id ? 'active' : ''}
                      onClick={() => {
                        updateSetting('campusId', campus.id)
                        setSelectedBuildings([])
                        setClassrooms(null)
                        setRecommendations(null)
                      }}
                    >
                      <MapPin size={15} />
                      {campus.name}
                    </button>
                  ))}
                </div>
              </div>
              <label>
                最少座位
                <input
                  type="number"
                  min="0"
                  value={minSeats}
                  onChange={(event) => {
                    setMinSeats(Number(event.target.value))
                    setRecommendations(null)
                  }}
                />
              </label>
            </section>

            <section className="summary-band">
              <div>
                <span>当天课程</span>
                <strong>{plannerWeekState.dayCourses.length}</strong>
              </div>
              <div>
                <span>个人空闲节次</span>
                <strong>{freeSlots.length}</strong>
              </div>
              <div>
                <span>匹配教室</span>
                <strong>{needsBuildingSelection || needsSlotSelection ? 0 : filteredRooms.length}</strong>
              </div>
              <div>
                <span>{classrooms?.provider === 'jray_public' ? '公共源推荐' : '推荐结果'}</span>
                <strong>{recommendationItems.length || 0}</strong>
              </div>
            </section>

            <section className="panel action-panel">
              <button type="button" onClick={loadSchedule} disabled={!!loading}>
                {loading === 'schedule' ? <Loader2 className="spin" size={17} /> : <RefreshCw size={17} />}
                获取/刷新个人课表
              </button>
              <button type="button" onClick={loadClassrooms} disabled={!!loading}>
                {loading === 'classrooms' ? <Loader2 className="spin" size={17} /> : <Search size={17} />}
                查看空教室
              </button>
              <button type="button" className="primary" onClick={runRecommendations} disabled={!!loading}>
                {loading === 'recommendations' ? <Loader2 className="spin" size={17} /> : <Sparkles size={17} />}
                推荐同一教室
              </button>
            </section>
          </aside>

          <section className="main-grid">
            <section className="panel wide">
              <div className="panel-heading">
                <div className="panel-title">
                  <Clock3 size={18} />
                  <h2>节次筛选</h2>
                </div>
                <div className="mini-actions">
                  <button
                    type="button"
                    onClick={() => {
                      setSelectedSlots(freeSlots)
                      setRecommendations(null)
                    }}
                  >
                    选中空闲
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setSelectedSlots([])
                      setRecommendations(null)
                    }}
                  >
                    清空
                  </button>
                </div>
              </div>
              <div className="filter-toggles">
                <button
                  type="button"
                  className={usePersonalSchedule ? 'active' : ''}
                  onClick={togglePersonalSchedule}
                >
                  个人课表 {usePersonalSchedule ? '开' : '关'}
                </button>
                <button
                  type="button"
                  className={canShowRecommendationHighlight ? 'active' : ''}
                  disabled={!recommendationItems.length}
                  onClick={() => setShowRecommendationHighlight((current) => !current)}
                >
                  推荐高亮 {showRecommendationHighlight ? '开' : '关'}
                </button>
              </div>
              <div className="slot-grid">
                {slotMeta.map((slot) => {
                  const busy = busySlots.includes(slot.index)
                  const selected = selectedSlots.includes(slot.index)
                  return (
                    <button
                      key={slot.index}
                      type="button"
                      className={`slot-cell ${busy ? 'busy' : 'free'} ${selected ? 'selected' : ''}`}
                      onClick={() => !busy && toggleSlot(slot.index)}
                      disabled={busy}
                      title={busy ? '个人课表占用' : '个人空闲，可筛选教室'}
                    >
                      <span>{slot.label}</span>
                      <small>{slot.start}-{slot.end}</small>
                    </button>
                  )
                })}
              </div>
              <p className="muted">
                第 {plannerWeekState.weekNumber || '-'} 周，选中范围：
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
                      <strong>{course.name}</strong>
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
              {classrooms?.provider ? (
                <p className="muted source-note">
                  数据源：{classrooms.provider === 'sjd' ? '移动教务实时接口' : classrooms.provider === 'jray_public' ? 'Jraaay 公共实时数据' : '微信教务实时接口'}
                  {recommendationItems.length ? ' · 已计算推荐' : ''}
                </p>
              ) : null}
              <div className="room-list">
                {needsBuildingSelection ? (
                  <div className="empty-state">未选择教学楼</div>
                ) : needsSlotSelection ? (
                  <div className="empty-state">未选择节次</div>
                ) : (
                  filteredRooms.length ? filteredRooms.slice(0, 80).map((room) => (
                    (() => {
                      const recommendation = canShowRecommendationHighlight ? recommendationByRoom.get(room.id) : null
                      return (
                        <article key={room.id} className={`room-card ${recommendation ? 'recommended' : ''}`}>
                          <div>
                            <strong>{displayBuildingName(room.name)}</strong>
                            <span>
                              {recommendation ? '推荐 · ' : ''}
                              {room.size ? `${room.size} 座` : '座位未知'}
                              {recommendation ? ` · 评分 ${recommendation.score}` : ''}
                            </span>
                          </div>
                          {recommendation?.longest_range ? (
                            <p>
                              最长连续 {recommendation.longest_range.length} 节：
                              {recommendation.longest_range.start_time}-{recommendation.longest_range.end_time}
                            </p>
                          ) : (
                            <p>{slotsToRanges(room.available_slots.filter((slot) => selectedSlots.includes(slot)), slotMeta).map((range) => range.label).join(' / ')}</p>
                          )}
                          {recommendation ? (
                            <div className="range-tags">
                              {recommendation.ranges.map((range) => (
                                <span key={`${room.id}-${range.start_slot}-${range.end_slot}`}>
                                  {range.start_time}-{range.end_time}
                                </span>
                              ))}
                            </div>
                          ) : null}
                        </article>
                      )
                    })()
                  )) : (
                    <div className="empty-state">暂无匹配空教室</div>
                  )
                )}
              </div>
            </section>
          </section>
        </div>
          ) : null}

          {activePage === 'calendar' ? (
        <section className="calendar-page">
          <section className="teaching-calendar-shell">
            <div className="teaching-calendar-toolbar">
              <div className="calendar-title-group">
                <p className="eyebrow">BUPT Classroom Planner</p>
                <h2>教学日历</h2>
                <p>
                  {formatCalendarTitle(calendarDate, calendarView)} · 第 {calendarWeekState.weekNumber || '-'} 周 · {activeTermId} · {courses.length} 门已载入
                </p>
              </div>
              <div className="calendar-toolbar-actions">
                <div className="calendar-view-switch" aria-label="日历视图">
                  {CALENDAR_VIEWS.map((view) => (
                    <button
                      key={view.id}
                      type="button"
                      className={calendarView === view.id ? 'active' : ''}
                      onClick={() => setCalendarView(view.id)}
                    >
                      {view.label}
                    </button>
                  ))}
                </div>
                <button type="button" className="calendar-icon-button" onClick={() => moveCalendar(-1)} aria-label="上一段">‹</button>
                <button type="button" className="calendar-today-button" onClick={() => setCalendarDate(todayDate)}>今天</button>
                <button type="button" className="calendar-icon-button" onClick={() => moveCalendar(1)} aria-label="下一段">›</button>
              </div>
            </div>

            <div className="teaching-calendar-layout">
              <section className="teaching-calendar-main">
                <div className="calendar-action-strip">
                  <input
                    type="date"
                    value={calendarDate}
                    onChange={(event) => chooseCalendarDate(event.target.value)}
                  />
                  <button type="button" onClick={loadSchedule} disabled={!!loading}>
                    {loading === 'schedule' ? <Loader2 className="spin" size={16} /> : <RefreshCw size={16} />}
                    获取/刷新个人课表
                  </button>
                  <button type="button" onClick={importAppleCalendar} disabled={!!loading || !courses.length}>
                    {loading === 'calendar-import' ? <Loader2 className="spin" size={16} /> : <CalendarPlus size={16} />}
                    导入苹果日历
                  </button>
                </div>
                {calendarImportedPath ? (
                  <p className="calendar-export-note">已生成日历文件并打开苹果日历：{calendarImportedPath}</p>
                ) : null}

                {calendarView === 'day' || calendarView === 'week' ? (
                  <div className={`time-calendar ${calendarView === 'day' ? 'single-day' : ''}`} style={{ '--day-count': visibleCalendarDays.length }}>
                    <div className="time-corner" />
                    {visibleCalendarDays.map((dateString) => {
                      const date = dateFromString(dateString)
                      const dayState = getWeekState(courses, activeTermStartDate, dateString)
                      return (
                        <button
                          key={`head-${dateString}`}
                          type="button"
                          className={`time-day-head ${dateString === calendarDate ? 'selected' : ''} ${dateString === todayDate ? 'today' : ''}`}
                          onClick={() => chooseCalendarDate(dateString)}
                        >
                          <span>{CALENDAR_WEEKDAYS[date.getDay()]}</span>
                          <strong>{date.getMonth() + 1}/{date.getDate()}</strong>
                          <small>{dayState.dayCourses.length ? `${dayState.dayCourses.length} 门课` : '无课程'}</small>
                        </button>
                      )
                    })}
                    <div className="time-labels">
                      {calendarHours.map((hour) => <span key={hour}>{String(hour).padStart(2, '0')}:00</span>)}
                    </div>
                    {visibleCalendarDays.map((dateString) => {
                      const dayState = getWeekState(courses, activeTermStartDate, dateString)
                      const visibleStart = CALENDAR_START_HOUR * 60
                      const visibleEnd = CALENDAR_END_HOUR * 60
                      const visibleRange = visibleEnd - visibleStart
                      return (
                        <div key={`lane-${dateString}`} className={`time-day-lane ${dateString === calendarDate ? 'selected' : ''}`}>
                          <div className="time-grid-lines">
                            {calendarHours.map((hour) => <span key={hour} />)}
                          </div>
                          <div className="time-course-layer">
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
                                  <strong>{course.name}</strong>
                                  <span>{bounds.start}-{bounds.end}</span>
                                  <small>{course.room || '地点未标注'}</small>
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
                  <div className="month-calendar">
                    {CALENDAR_WEEKDAYS.map((label) => <span key={label} className="month-weekday">{label}</span>)}
                    {visibleCalendarDays.map((dateString) => {
                      const date = dateFromString(dateString)
                      const currentMonth = date.getMonth() === dateFromString(calendarDate).getMonth()
                      const dayState = getWeekState(courses, activeTermStartDate, dateString)
                      return (
                        <button
                          key={dateString}
                          type="button"
                          className={`month-cell ${currentMonth ? '' : 'muted-day'} ${dateString === calendarDate ? 'selected' : ''} ${dateString === todayDate ? 'today' : ''}`}
                          onClick={() => chooseCalendarDate(dateString)}
                        >
                          <span>{date.getDate()}</span>
                          <div>
                            {dayState.dayCourses.slice(0, 3).map((course) => (
                              <small key={`${dateString}-${course.id}`}>{course.name}</small>
                            ))}
                            {dayState.dayCourses.length > 3 ? <em>+{dayState.dayCourses.length - 3}</em> : null}
                          </div>
                        </button>
                      )
                    })}
                  </div>
                ) : null}

                {calendarView === 'year' ? (
                  <div className="year-calendar">
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
                            return (
                              <button
                                key={dateString}
                                type="button"
                                className={`${date.getMonth() === month.monthIndex ? '' : 'muted-day'} ${state.dayCourses.length ? 'has-course' : ''} ${dateString === calendarDate ? 'selected' : ''} ${dateString === todayDate ? 'today' : ''}`}
                                onClick={() => {
                                  setCalendarDate(dateString)
                                  setCalendarView('day')
                                }}
                              >
                                {date.getDate()}
                              </button>
                            )
                          })}
                        </div>
                      </section>
                    ))}
                  </div>
                ) : null}
              </section>

              <aside className="calendar-inspector">
                <div className="inspector-card primary">
                  <span>{formatCourseDate(calendarDate)}</span>
                  <strong>{calendarWeekState.dayCourses.length} 门课</strong>
                  <small>第 {calendarWeekState.weekNumber || '-'} 周</small>
                </div>
                {calendarDetailCourse ? (
                  <div className="inspector-card">
                    <strong>{calendarDetailCourse.name}</strong>
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
                        <strong>{course.name}</strong>
                        <span>{bounds.start}-{bounds.end}</span>
                        <small>{course.room || '地点未标注'}</small>
                      </article>
                    )
                  })}
                </div>
              </aside>
            </div>
          </section>
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
                inputMode="numeric"
                placeholder="可使用环境变量"
              />
            </label>
            <label>
              教务密码
              <input
                value={settings.password}
                onChange={(event) => updateSetting('password', event.target.value)}
                type="password"
                placeholder="保存到本地数据"
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
              <input value={settings.termId} onChange={(event) => updateSetting('termId', event.target.value)} />
            </label>
            <label>
              第一周周一
              <input type="date" value={settings.termStartDate} onChange={(event) => updateSetting('termStartDate', event.target.value)} />
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

          <section className="panel settings-actions">
            <button type="button" className="primary" onClick={saveCurrentSettings}>
              <CheckCircle2 size={17} />
              保存设置
            </button>
            {settingsSaved ? <span>已保存</span> : null}
          </section>
        </section>
          ) : null}
        </section>
      </div>
    </main>
  )
}

export default App
