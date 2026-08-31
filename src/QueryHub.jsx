import { useEffect, useMemo, useState } from 'react'
import {
  AlertTriangle,
  BusFront,
  CalendarClock,
  CheckCircle2,
  Clock3,
  ExternalLink,
  Loader2,
  MapPin,
  RefreshCw,
  Search,
  Star,
} from 'lucide-react'

import { shanghaiDateString } from './planner-domain.js'
import {
  buildShuttleDayView,
  filterImportantEvents,
  importantEventFavorite,
  importantEventFilterOptions,
  mergeImportantEventCatalog,
  shanghaiClockMinutes,
  shanghaiWeekdayKey,
  SHUTTLE_WEEKDAYS,
} from './query-domain.js'

const EVENT_TYPE_LABELS = Object.freeze({
  competition: '学科竞赛',
  conference: '学术会议',
  journal_special_issue: '期刊专题',
  hackathon: '黑客松',
  summer_camp: '夏令营',
  pre_admission: '预推免',
})

function formatDeadline(value, language) {
  const date = new Date(value)
  if (!Number.isFinite(date.getTime())) return value || ''
  return new Intl.DateTimeFormat(language === 'en' ? 'en-US' : 'zh-CN', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date)
}

function periodLabel(period, language) {
  if (!period) return ''
  if (period.start_date && period.end_date) {
    return language === 'en'
      ? `${period.start_date} – ${period.end_date}`
      : `${period.start_date} 至 ${period.end_date}`
  }
  if (period.start_date) return language === 'en' ? `From ${period.start_date}` : `${period.start_date} 起`
  return period.label
}

function typeLabel(type, t) {
  return t(EVENT_TYPE_LABELS[type] || type)
}

function statusLabel(state, t) {
  return {
    active: t('当前执行'),
    upcoming: t('尚未开始'),
    ended: t('历史时段'),
    unknown: t('时段待确认'),
  }[state] || t('时段待确认')
}

function QueryError({ fallback, language, message, onRetry, t }) {
  return (
    <div className="query-error" role="alert">
      <AlertTriangle size={20} />
      <div><strong>{t('数据暂时无法读取')}</strong><span>{language === 'en' ? t(fallback) : t(message)}</span></div>
      <button type="button" onClick={onRetry}><RefreshCw size={15} />{t('重新加载')}</button>
    </div>
  )
}

export default function QueryHub({
  command,
  favoriteItems,
  isFavorite,
  language,
  onToggleFavorite,
  t,
}) {
  const [tab, setTab] = useState('shuttle')
  const [shuttle, setShuttle] = useState(null)
  const [shuttleLoading, setShuttleLoading] = useState(true)
  const [shuttleError, setShuttleError] = useState('')
  const [importantEvents, setImportantEvents] = useState(null)
  const [eventsLoading, setEventsLoading] = useState(true)
  const [eventsError, setEventsError] = useState('')
  const [selectedWeekday, setSelectedWeekday] = useState(() => shanghaiWeekdayKey())
  const [selectedPeriod, setSelectedPeriod] = useState('')
  const [now, setNow] = useState(() => new Date())
  const [query, setQuery] = useState('')
  const [eventType, setEventType] = useState('all')
  const [category, setCategory] = useState('all')
  const [eventSource, setEventSource] = useState('all')
  const [includeExpired, setIncludeExpired] = useState(false)
  const [visibleCount, setVisibleCount] = useState(50)

  const loadShuttle = async () => {
    setShuttleLoading(true)
    setShuttleError('')
    try {
      setShuttle(await command('fetch_shuttle_bus'))
    } catch (error) {
      setShuttleError(error?.message || String(error))
    } finally {
      setShuttleLoading(false)
    }
  }

  const loadImportantEvents = async () => {
    setEventsLoading(true)
    setEventsError('')
    try {
      setImportantEvents(await command('fetch_important_events'))
    } catch (error) {
      setEventsError(error?.message || String(error))
    } finally {
      setEventsLoading(false)
    }
  }

  useEffect(() => {
    void loadShuttle()
    void loadImportantEvents()
  }, []) // Both sources warm once, independently from segment animations.

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 30_000)
    return () => window.clearInterval(timer)
  }, [])

  useEffect(() => {
    setVisibleCount(50)
  }, [query, eventType, category, eventSource, includeExpired])

  const today = shanghaiDateString(now)
  const currentWeekday = shanghaiWeekdayKey(now)
  const shuttleView = useMemo(() => buildShuttleDayView(shuttle || {}, {
    today,
    weekday: selectedWeekday,
    currentWeekday,
    nowMinutes: shanghaiClockMinutes(now),
    selectedPeriod,
  }), [currentWeekday, now, selectedPeriod, selectedWeekday, shuttle, today])
  const eventCatalog = useMemo(
    () => mergeImportantEventCatalog(importantEvents?.items || [], favoriteItems),
    [favoriteItems, importantEvents],
  )
  const eventOptions = useMemo(
    () => importantEventFilterOptions(eventCatalog, {
      type: eventType,
      source: eventSource,
      includeExpired,
      now,
    }),
    [eventCatalog, eventSource, eventType, includeExpired, now],
  )
  const filteredEvents = useMemo(() => filterImportantEvents(eventCatalog, {
    query,
    type: eventType,
    category,
    source: eventSource,
    includeExpired,
    now,
  }), [category, eventCatalog, eventSource, eventType, includeExpired, now, query])
  const favoriteOnlyMissing = useMemo(() => favoriteItems.filter((favorite) => (
    ['contest_ddl', 'school_notice'].includes(favorite.source_type)
      && !filteredEvents.some((item) => (
        item.source_type === favorite.source_type
          && item.id === favorite.id
          && item.primary_deadline === favorite.primary_deadline
      ))
  )), [favoriteItems, filteredEvents])
  const visibleEvents = filteredEvents.slice(0, visibleCount)

  useEffect(() => {
    if (eventType !== 'all' && !eventOptions.types.includes(eventType)) {
      setEventType('all')
    }
  }, [eventOptions.types, eventType])

  useEffect(() => {
    if (category !== 'all' && !eventOptions.categories.includes(category)) {
      setCategory('all')
    }
  }, [category, eventOptions.categories])

  return (
    <section className="query-hub" aria-label={t('综合查询')}>
      <div className="query-hub-segments" role="tablist" aria-label={t('查询类型')}>
        <button type="button" role="tab" aria-selected={tab === 'shuttle'} className={tab === 'shuttle' ? 'active' : ''} onClick={() => setTab('shuttle')}>
          <BusFront size={17} />{t('班车查询')}
        </button>
        <button type="button" role="tab" aria-selected={tab === 'events'} className={tab === 'events' ? 'active' : ''} onClick={() => setTab('events')}>
          <CalendarClock size={17} />{t('重要事件')}
        </button>
      </div>

      {tab === 'shuttle' ? (
        <div className="query-shuttle" role="tabpanel">
          <header className="query-section-header">
            <div><span>{t('今日校区班车')}</span><h2>{t('西土城 ↔ 沙河')}</h2></div>
            <button type="button" onClick={loadShuttle} disabled={shuttleLoading} aria-label={t('刷新班车信息')}>
              <RefreshCw className={shuttleLoading ? 'spin' : ''} size={17} />
            </button>
          </header>
          {shuttleLoading && !shuttle ? <div className="query-loading"><Loader2 className="spin" />{t('正在读取最新班车信息…')}</div> : null}
          {shuttleError ? <QueryError fallback="班车信息暂时无法读取。" language={language} message={shuttleError} onRetry={loadShuttle} t={t} /> : null}
          {shuttle ? (
            <>
              <section className={`shuttle-status-card ${shuttle.status === 'stale' ? 'stale' : ''}`}>
                <div>
                  <span>{shuttleView.usingFallback ? t('上一份完整时刻表，仅供对照') : statusLabel(shuttleView.periodState, t)}</span>
                  <strong>{shuttleView.latest?.title || t('等待班车通知')}</strong>
                  <small>{periodLabel(shuttleView.period, language)} · {t('更新于')} {formatDeadline(shuttle.generated_at, language)}</small>
                </div>
                <a href={shuttleView.latest?.source_url || shuttle.source?.page_url} target="_blank" rel="noreferrer">{t('后勤部原文')}<ExternalLink size={14} /></a>
              </section>

              {shuttleView.periods.length > 1 ? (
                <div className="shuttle-period-options" aria-label={t('运行时段')}>
                  {shuttleView.periods.map(({ key, period }, index) => (
                    <button type="button" className={shuttleView.visiblePeriod === key ? 'active' : ''} onClick={() => setSelectedPeriod(key)} key={key}>
                      <span>{t('时段')} {index + 1}</span><strong>{periodLabel(period, language)}</strong>
                    </button>
                  ))}
                </div>
              ) : null}

              <div className="shuttle-weekday-options" aria-label={t('选择星期')}>
                {SHUTTLE_WEEKDAYS.map((weekday) => (
                  <button type="button" className={selectedWeekday === weekday.key ? 'active' : ''} onClick={() => setSelectedWeekday(weekday.key)} key={weekday.key}>
                    {language === 'en' ? weekday.english : weekday.label}
                    {currentWeekday === weekday.key ? <small>{t('今')}</small> : null}
                  </button>
                ))}
              </div>

              <div className="shuttle-route-list">
                {shuttleView.routes.length ? shuttleView.routes.map((route) => (
                  <article key={`${route.from}-${route.to}`}>
                    <header><div><strong>{route.from} <b>→</b> {route.to}</strong><span>{route.stop ? <><MapPin size={13} />{route.stop}</> : periodLabel(shuttleView.period, language)}</span></div><small>{selectedWeekday === currentWeekday ? t('今天') : t('所选星期')}</small></header>
                    {route.departures.length ? <ol>{route.departures.map((departure) => (
                      <li className={`${departure.departed ? 'departed' : ''}${departure.next ? ' next' : ''}`} key={departure.departureTime}>
                        <time>{departure.departureTime}</time>
                        <div><strong>{departure.departed ? t('已过发车时间') : departure.next ? t('下一班') : t('计划班次')}</strong><span>{departure.service.vehicle} × {departure.service.count}</span></div>
                        {departure.next ? <CheckCircle2 size={18} /> : <Clock3 size={18} />}
                      </li>
                    ))}</ol> : <p className="query-empty">{t('当天暂无班车')}</p>}
                  </article>
                )) : <p className="query-empty">{t(
                  shuttleView.periods.length
                    ? '今日没有生效的班车时刻表'
                    : '暂无可安全展示的结构化班次',
                )}</p>}
              </div>

              <p className="query-source-note">
                {t('第三方来源：北京邮电大学后勤部，经 Where To Study 服务端结构化整理；法定节假日及临时调整请以原文为准。')}
                {' '}<a href="https://where-to-study.cn/api/shuttle-bus" target="_blank" rel="noreferrer">API</a>
              </p>
            </>
          ) : null}
        </div>
      ) : (
        <div className="query-events" role="tabpanel">
          <header className="query-section-header">
            <div><span>{t('公开活动与校内通知')}</span><h2>{t('按截止时间查找重要事件')}</h2></div>
            <button type="button" onClick={loadImportantEvents} disabled={eventsLoading} aria-label={t('刷新重要事件')}><RefreshCw className={eventsLoading ? 'spin' : ''} size={17} /></button>
          </header>
          <div className="event-query-controls">
            <label className="event-query-search"><Search size={17} /><input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder={t('搜索赛事、会议、学校、方向…')} /></label>
            <label><span>{t('类型')}</span><select value={eventType} onChange={(event) => { setEventType(event.target.value); setCategory('all') }}><option value="all">{t('全部类型')}</option>{eventOptions.types.map((type) => <option value={type} key={type}>{typeLabel(type, t)}</option>)}</select></label>
            <label><span>{t('分类')}</span><select value={category} onChange={(event) => setCategory(event.target.value)}><option value="all">{t('全部分类')}</option>{eventOptions.categories.map((value) => <option value={value} key={value}>{value}</option>)}</select></label>
            <label><span>{t('来源')}</span><select value={eventSource} onChange={(event) => { setEventSource(event.target.value); setCategory('all') }}><option value="all">{t('全部来源')}</option><option value="public">{t('公开活动')}</option><option value="school">{t('校内通知')}</option></select></label>
            <div className="event-expired-toggle"><span>{t('显示已结束')}</span><button type="button" role="switch" className="settings-switch" aria-checked={includeExpired} onClick={() => setIncludeExpired((value) => !value)}><span aria-hidden="true" /></button></div>
          </div>
          {eventsLoading && !importantEvents ? <div className="query-loading"><Loader2 className="spin" />{t('正在更新重要事件…')}</div> : null}
          {eventsError ? <QueryError fallback="重要事件暂时无法读取。" language={language} message={eventsError} onRetry={loadImportantEvents} t={t} /> : null}
          <div className="event-query-summary"><strong>{t('按 DDL 由近到远')}</strong><span>{t('{count} 条结果', { count: filteredEvents.length })}</span></div>
          <div className="important-event-list">
            {visibleEvents.map((item) => {
              const favorite = importantEventFavorite(item)
              const selected = isFavorite(favorite)
              const details = [item.organizer, item.level, item.location].filter(Boolean)
              return (
                <article className={item.source_type === 'school_notice' ? 'school' : item.event_type} key={`${item.source_type}-${item.id}-${item.primary_deadline}`}>
                  <div className="important-event-main">
                    <div className="important-event-kicker"><span>{item.source_type === 'school_notice' ? t('校内通知') : typeLabel(item.event_type, t)}</span><small>{item.deadline_label || t('最近节点')}</small></div>
                    <h3>{item.official_url ? <a href={item.official_url} target="_blank" rel="noreferrer">{item.name}<ExternalLink size={14} /></a> : item.name}</h3>
                    {details.length ? <p>{details.join(' · ')}</p> : null}
                    <div className="important-event-tags">{(item.categories || []).slice(0, 4).map((value) => <span key={value}>{value}</span>)}{(item.tags || []).slice(0, 2).map((value) => <span className="rank" key={value}>{value}</span>)}</div>
                  </div>
                  <div className="important-event-deadline"><strong>{formatDeadline(item.primary_deadline, language)}</strong><span>{item.source_name || (item.source_type === 'school_notice' ? t('北京邮电大学教学云平台') : 'Contest DDL')}</span></div>
                  <button type="button" className={`deadline-favorite-button ${selected ? 'active' : ''}`} aria-label={selected ? t('取消收藏') : t('收藏')} aria-pressed={selected} onClick={() => onToggleFavorite(favorite)}><Star size={18} fill={selected ? 'currentColor' : 'none'} /></button>
                </article>
              )
            })}
            {!eventsLoading && !eventsError && visibleEvents.length === 0 ? <p className="query-empty">{t('没有符合条件的重要事件')}</p> : null}
          </div>
          {visibleCount < filteredEvents.length ? <button type="button" className="event-load-more" onClick={() => setVisibleCount((count) => count + 50)}>{t('显示更多')}</button> : null}
          {favoriteOnlyMissing.length ? <p className="query-source-note">{t('另有 {count} 条已收藏事件因当前筛选或来源变化未列出，可在收藏管理中查看。', { count: favoriteOnlyMissing.length })}</p> : null}
          <p className="query-source-note">{t('第三方来源：Contest DDL 与校内竞赛通知脚本；不包含课程作业 DDL，所有时间请以官方原文为准。')} <a href="https://where-to-study.cn/api/contest-events" target="_blank" rel="noreferrer">contest-events API</a> · <a href="https://where-to-study.cn/api/contest-notices" target="_blank" rel="noreferrer">contest-notices API</a></p>
        </div>
      )}
    </section>
  )
}
