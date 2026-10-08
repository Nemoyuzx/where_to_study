import { uiText } from './ui-text.js'
import { uiDateLocale } from './ui-languages.js'
import { useEffect, useMemo, useRef, useState } from 'react'
import { CalendarClock, ClipboardList, ExternalLink, RefreshCw, Settings2, ChevronDown } from 'lucide-react'
import { filterAssignmentQueries } from './query-domain.js'
import {courseActivityKey} from './course-domain.js'
import {useCourseData} from './use-course-data.js'

// Kept mounted across Query segments. Opening/changing a segment never logs in;
// explicit retrieval uses the existing native, credential-scoped services.
export default function PrivateQueriesPanel({ kind, enabled, command, language, hasAccount, onOpenAccount, examSnapshot, assignmentSnapshot, courseDataOwner }) {
  const text=(zh,english,values)=>uiText(language,zh,english,values)
  const assignments = kind === 'assignments'
  const shared=useCourseData(courseDataOwner)
  const title = assignments ? (text('课程作业 DDL', 'Assignment DDL')) : (text('考试查询', 'Exams'))
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
  const available = (assignments ? shared.assignments ?? assignmentSnapshot ?? items : items) ?? (!assignments && hasAccount && snapshotState !== 'failed' ? examSnapshot?.items : null)
  const courses = useMemo(() => [...new Set((available || []).map(x => x.course_name).filter(Boolean))].sort(), [available])
  const filtered = useMemo(() => assignments ? filterAssignmentQueries(available || [], { query, course, range })
    : (available || []).filter(x => [x.name, x.room, x.seat, x.time_text].some(v => String(v || '').toLowerCase().includes(query.toLowerCase().trim()))), [assignments, available, course, query, range])
  const [limit, setLimit] = useState(30)
  useEffect(() => setLimit(30), [query, course, range, available])
  const load = async () => {
    const id = ++revision.current
    setBusy(true); setError('')
    try {
      const value = assignments ? await courseDataOwner?.refresh(true) : await command('fetch_exams', { term_id: null })
      if (revision.current !== id) return
      if(!assignments)setItems(value.items)
      setUpdated(assignments?value?.fetched_at||'':new Date().toISOString())
    } catch {
      if (revision.current === id) setError(text('读取失败，请检查网络及设置中对应的教务／教学云密码后重试。', 'Unable to retrieve data. Check your connection and the corresponding account password in Settings, then retry.'))
    } finally { if (revision.current === id) setBusy(false) }
  }
  return <div className="query-grades" hidden={!enabled} role="tabpanel" aria-label={title}>
    <header className="query-section-header"><h2>{assignments ? <ClipboardList size={22} /> : <CalendarClock size={22} />}{title}</h2>
      <button type="button" onClick={load} disabled={busy || (assignments&&shared.cloudBusy) || !hasAccount}><RefreshCw size={16} className={busy || (assignments&&shared.cloudBusy) ? 'spin' : ''} />{text('获取／刷新', 'Fetch / refresh')}</button>
    </header>
    {!hasAccount ? <div className="query-grade-status"><p>{text('请先在设置中保存个人账户；作业优先使用单独填写的教学云密码。', 'Save your academic account in Settings first. Assignments use the separate Teaching Cloud password if provided.')}</p><button type="button" className="query-action-button" onClick={onOpenAccount}><Settings2 size={16} aria-hidden="true" />{text('前往个人账户', 'Go to account settings')}</button></div> : <>
      <div className="query-grade-filters">
        <label>{text('搜索', 'Search')}<input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder={text('课程或标题', 'Course or title')} /></label>
        {assignments && <><label>{text('课程', 'Course')}<select value={course} onChange={e => setCourse(e.target.value)}><option value="">{text('全部课程', 'All courses')}</option>{courses.map(name => <option key={name}>{name}</option>)}</select></label>
          <label>{text('截止时间', 'Deadline')}<select value={range} onChange={e => setRange(e.target.value)}><option value="all">{text('全部', 'All')}</option><option value="upcoming">{text('尚未截止', 'Not yet due')}</option><option value="past">{text('已截止', 'Past')}</option></select></label></>}
      </div>
      {busy && <p role="status">{text('正在读取…', 'Loading…')}</p>}
      {error && <p role="alert">{error}</p>}
      {assignments&&shared.cacheWarning&&<p role="status">{text('本次课程数据已读取，但本地缓存未更新。重启后可能显示此前缓存。','Course data was loaded, but the local cache was not updated. A restart may show the previous cache.')}</p>}
      {snapshotState === 'failed' && <p role="alert">{text('考试同步失败，请点击刷新重试；此状态不代表没有考试。', 'Exam synchronization failed. Refresh to retry; this is not an empty exam list.')}</p>}
      {snapshotState === 'stale' && <p role="status">{text('正在显示此前缓存的考试安排，请刷新并以学校最新信息为准。', 'Showing a previously cached exam schedule. Refresh and confirm against the university service.')} {examSnapshot?.fetched_at}</p>}
      {available == null && !busy && <p className="query-grade-status">{text('点击“获取／刷新”读取数据，切换查询栏目不会重复登录。', 'Use Fetch / refresh to retrieve your data. Switching tabs will not log you in again.')}</p>}
      {available != null && !filtered.length && <p className="query-grade-status">{text('暂无符合条件的记录。', 'No matching records.')}</p>}
      <div className="query-grade-list">{filtered.slice(0, limit).map(item => <article className="query-grade-card" key={assignments?courseActivityKey(item):item.id}>
        <header><strong>{assignments ? item.title : item.name}</strong></header>
        {assignments ? <><p>{item.course_name}</p><strong>{item.deadline}</strong><small>{item.status || (text('状态未提供', 'Status not provided'))}</small></>
          : <><p>{item.date || (text('日期待定', 'Date pending'))} · {item.start_time ? `${item.start_time}–${item.end_time}` : item.time_text || (text('时间待定', 'Time pending'))}</p><small>{item.room || (text('地点待定', 'Room pending'))}{item.seat ? ` · ${text('座位', 'Seat')} ${item.seat}` : ''}</small></>}
      </article>)}</div>
      {limit < filtered.length && <button type="button" className="query-action-button" onClick={() => setLimit(v => v + 30)}><ChevronDown size={16}/>{text('加载更多', 'Show more')}</button>}
      {(assignments?shared.fetchedAt:updated)&&<small>{text('更新于','Updated')} {new Intl.DateTimeFormat(uiDateLocale(language),{dateStyle:'short',timeStyle:'short',timeZone:'Asia/Shanghai'}).format(new Date(assignments?shared.fetchedAt:updated))}</small>}
    </>}
    <p className="query-source">{assignments ? (text('第三方来源：学校教学云平台。使用已保存账户直接查询，不上传至本应用服务端。', 'Source: university Teaching Cloud. Assignments are queried directly using your saved account and are not uploaded to this app’s server.')) : (text('第三方来源：学校教务服务。考试安排也会随个人课表一起同步。', 'Source: university academic service. Exam arrangements are also synchronized when refreshing the timetable.'))} {text('显示数据仅供参考，请以学校实际安排为准。', 'For reference only; confirm against the official platform.')}</p>
    {assignments ? <a className="external-action-button" href="https://ucloud.bupt.edu.cn/uclass/" target="_blank" rel="noreferrer"><ExternalLink size={16} aria-hidden="true" />{text('打开教学云平台', 'Open Teaching Cloud Platform')}</a> : null}
  </div>
}
