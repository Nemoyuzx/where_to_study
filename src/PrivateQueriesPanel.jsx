import { useEffect, useMemo, useRef, useState } from 'react'
import { CalendarClock, ClipboardList, RefreshCw } from 'lucide-react'
import { filterAssignmentQueries } from './query-domain.js'

// Kept mounted across Query segments. Opening/changing a segment never logs in;
// explicit retrieval uses the existing native, credential-scoped services.
export default function PrivateQueriesPanel({ kind, enabled, command, language, hasAccount, onOpenAccount, examSnapshot }) {
  const en = language === 'en'
  const assignments = kind === 'assignments'
  const title = assignments ? (en ? 'Assignment DDL' : '课程作业 DDL') : (en ? 'Exams' : '考试查询')
  const [items, setItems] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [query, setQuery] = useState('')
  const [course, setCourse] = useState('')
  const [range, setRange] = useState('all')
  const [updated, setUpdated] = useState('')
  const revision = useRef(0)
  useEffect(() => () => { revision.current += 1 }, [])
  useEffect(() => {
    if (!hasAccount) { revision.current += 1; setItems(null); setError(''); setBusy(false) }
  }, [hasAccount])
  const snapshotState = !assignments && items == null && hasAccount ? examSnapshot?.status : null
  const available = items ?? (!assignments && hasAccount && snapshotState !== 'failed' ? examSnapshot?.items : null)
  const courses = useMemo(() => [...new Set((available || []).map(x => x.course_name).filter(Boolean))].sort(), [available])
  const filtered = useMemo(() => assignments ? filterAssignmentQueries(available || [], { query, course, range })
    : (available || []).filter(x => [x.name, x.room, x.seat, x.time_text].some(v => String(v || '').toLowerCase().includes(query.toLowerCase().trim()))), [assignments, available, course, query, range])
  const [limit, setLimit] = useState(30)
  useEffect(() => setLimit(30), [query, course, range, available])
  const load = async () => {
    const id = ++revision.current
    setBusy(true); setError('')
    try {
      const value = assignments ? await command('fetch_assignment_list', { force: true }) : await command('fetch_exams', { term_id: null })
      if (revision.current !== id) return
      setItems(assignments ? value : value.items)
      setUpdated(new Intl.DateTimeFormat(en ? 'en-GB' : 'zh-CN', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Asia/Shanghai' }).format(new Date()))
    } catch {
      if (revision.current === id) setError(en ? 'Unable to retrieve data. Check your connection and the corresponding account password in Settings, then retry.' : '读取失败，请检查网络及设置中对应的教务／教学云密码后重试。')
    } finally { if (revision.current === id) setBusy(false) }
  }
  return <div className="query-grades" hidden={!enabled} role="tabpanel" aria-label={title}>
    <header className="query-section-header"><h2>{assignments ? <ClipboardList size={22} /> : <CalendarClock size={22} />}{title}</h2>
      <button type="button" onClick={load} disabled={busy || !hasAccount}><RefreshCw size={16} className={busy ? 'spin' : ''} />{en ? 'Fetch / refresh' : '获取／刷新'}</button>
    </header>
    {!hasAccount ? <div className="query-grade-status"><p>{en ? 'Save your academic account in Settings first. Assignments use the separate Teaching Cloud password if provided.' : '请先在设置中保存个人账户；作业优先使用单独填写的教学云密码。'}</p><button type="button" onClick={onOpenAccount}>{en ? 'Account settings' : '个人账户设置'}</button></div> : <>
      <div className="query-grade-filters">
        <label>{en ? 'Search' : '搜索'}<input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder={en ? 'Course or title' : '课程或标题'} /></label>
        {assignments && <><label>{en ? 'Course' : '课程'}<select value={course} onChange={e => setCourse(e.target.value)}><option value="">{en ? 'All courses' : '全部课程'}</option>{courses.map(name => <option key={name}>{name}</option>)}</select></label>
          <label>{en ? 'Deadline' : '截止时间'}<select value={range} onChange={e => setRange(e.target.value)}><option value="all">{en ? 'All' : '全部'}</option><option value="upcoming">{en ? 'Upcoming' : '尚未截止'}</option><option value="past">{en ? 'Past' : '已截止'}</option></select></label></>}
      </div>
      {busy && <p role="status">{en ? 'Loading…' : '正在读取…'}</p>}
      {error && <p role="alert">{error}</p>}
      {snapshotState === 'failed' && <p role="alert">{en ? 'Exam synchronization failed. Refresh to retry; this is not an empty exam list.' : '考试同步失败，请点击刷新重试；此状态不代表没有考试。'}</p>}
      {snapshotState === 'stale' && <p role="status">{en ? 'Showing a previously cached exam schedule. Refresh and confirm against the university service.' : '正在显示此前缓存的考试安排，请刷新并以学校最新信息为准。'} {examSnapshot?.fetched_at}</p>}
      {available == null && !busy && <p className="query-grade-status">{en ? 'Use Fetch / refresh to retrieve your data. Switching tabs will not log you in again.' : '点击“获取／刷新”读取数据，切换查询栏目不会重复登录。'}</p>}
      {available != null && !filtered.length && <p className="query-grade-status">{en ? 'No matching records.' : '暂无符合条件的记录。'}</p>}
      <div className="query-grade-list">{filtered.slice(0, limit).map(item => <article className="query-grade-card" key={item.id}>
        <header><strong>{assignments ? item.title : item.name}</strong></header>
        {assignments ? <><p>{item.course_name}</p><strong>{item.deadline}</strong><small>{item.status || (en ? 'Status not provided' : '状态未提供')}</small></>
          : <><p>{item.date || (en ? 'Date pending' : '日期待定')} · {item.start_time ? `${item.start_time}–${item.end_time}` : item.time_text || (en ? 'Time pending' : '时间待定')}</p><small>{item.room || (en ? 'Room pending' : '地点待定')}{item.seat ? ` · ${en ? 'Seat' : '座位'} ${item.seat}` : ''}</small></>}
      </article>)}</div>
      {limit < filtered.length && <button type="button" onClick={() => setLimit(v => v + 30)}>{en ? 'Show more' : '加载更多'}</button>}
      {updated && <small>{en ? 'Updated' : '更新于'} {updated}</small>}
    </>}
    <p className="query-source">{assignments ? (en ? 'Source: university Teaching Cloud. Assignments are queried directly using your saved account and are not uploaded to this app’s server.' : '第三方来源：学校教学云平台。使用已保存账户直接查询，不上传至本应用服务端。') : (en ? 'Source: university academic service. Exam arrangements are also synchronized when refreshing the timetable.' : '第三方来源：学校教务服务。考试安排也会随个人课表一起同步。')} {en ? 'For reference only; confirm against the official platform.' : '显示数据仅供参考，请以学校实际安排为准。'}</p>
  </div>
}
