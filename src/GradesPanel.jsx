import { uiText } from './ui-text.js'
import { uiDateLocale } from './ui-languages.js'
import { useEffect, useRef, useState } from 'react'
import { GraduationCap, RefreshCw, Settings2 } from 'lucide-react'

export function GradeCard({ item, words }) {
  const metadata = [item.semester_name, item.course_attribute, item.course_nature, item.exam_nature, item.grade_status]
    .filter(value => value !== '' && value != null)
  return <article className="query-grade-card">
    <header><strong>{item.name}</strong><span className="query-grade-score" aria-label={`${words.score}: ${item.score === '' || item.score == null ? '—' : item.score}`}>{item.score === '' || item.score == null ? '—' : item.score}</span></header>
    <div className="query-grade-metadata">
      <span>{words.credits} · {item.credits === '' || item.credits == null ? '—' : item.credits}{item.course_code ? ` · ${item.course_code}` : ''}</span>
      {metadata.length > 0 ? <span> · {metadata.join(' · ')}</span> : null}
    </div>
  </article>
}

export function groupGradesBySemester(items) {
  const groups=new Map()
  for(const item of items||[]) {
    const name=typeof item.semester_name==='string'?item.semester_name.trim():''
    if(!groups.has(name))groups.set(name,[])
    groups.get(name).push(item)
  }
  // Keep the source's term order and every record, including unknown terms.
  return [...groups].map(([name,items])=>({name,items}))
}

// Only session state: no grade/name/student-ID persistence or console output.
export default function GradesPanel({ command, language, enabled, hasAccount, onOpenAccount }) {
  const text = (zh, english) => uiText(language, zh, english)
  const words = {
    title: text('成绩查询', 'Grades'),
    account: text('请先在设置中保存教务账号，再查看本人的成绩。', 'Save an academic account in Settings to view your own grades.'),
    settings: text('前往个人账户', 'Go to account settings'),
    term: text('学年学期', 'Semester'),
    all: text('全部学期', 'All semesters'),
    best: text('最好', 'Best'),
    first: text('首次', 'First'),
    attempts: text('全部记录', 'All records'),
    records: text('成绩记录', 'Record type'),
    refresh: text('刷新成绩', 'Refresh grades'),
    loading: text('正在读取成绩…', 'Loading grades…'),
    empty: text('当前选择暂无已公布成绩，可切换“全部学期”查看。', 'No published grades in this selection. Try All semesters.'),
    average: text('平均学分绩点', 'Average grade point'),
    score: text('成绩', 'Grade'),
    credits: text('学分', 'Credits'),
    retry: text('成绩暂时无法读取，请检查教务账户后重试。', 'Unable to load grades. Check your academic account and try again.'),
    source: text('数据来源：学校教务服务。成绩仅在本机显示，不上传至本应用服务端，请以学校实际记录为准。', 'Source: the university academic service. Results are shown on this device; this app does not upload them to its servers.'),
    updated: text('更新于', 'Updated'),
  }
  const [terms, setTerms] = useState(null)
  const [term, setTerm] = useState(null)
  const [recordType, setRecordType] = useState('1')
  const [report, setReport] = useState(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [refresh, setRefresh] = useState(0)
  const request = useRef(0)
  const cache = useRef(new Map())
  useEffect(() => () => { request.current += 1; cache.current.clear() }, [])
  useEffect(() => {
    if (!hasAccount || refresh === 0) return undefined
    const id = ++request.current
    let alive = true
    const current = () => alive && request.current === id
    setLoading(true); setError(''); setReport(null)
    void (async () => {
      try {
        let selected = term
        if (!terms) {
          const metadata = await command('fetch_grade_terms')
          if (!current()) return
          setTerms(metadata)
          selected = selected ?? metadata.current_term_id
          if (term == null) {
            setTerm(selected)
            // The next effect owns the grade request; do not start a duplicate
            // request that the semester state change would immediately cancel.
            return
          }
        }
        const key = JSON.stringify([selected, recordType])
        const saved = cache.current.get(key)
        const value = saved && Date.now() - saved.at < 5 * 60_000 ? saved.value
          : await command('fetch_grades', { term_id: selected, record_type: recordType })
        if (!current()) return
        if (cache.current.size >= 8 && !cache.current.has(key)) cache.current.delete(cache.current.keys().next().value)
        cache.current.set(key, { at: Date.now(), value })
        setReport(value)
      } catch {
        if (current()) setError('unavailable')
      } finally { if (current()) setLoading(false) }
    })()
    return () => { alive = false }
    // User refresh/filter changes own retrieval, never segment visibility.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hasAccount, term, recordType, refresh])

  const change = setter => event => { request.current += 1; setReport(null); setError(''); setter(event.target.value) }
  const reload = () => { request.current += 1; cache.current.clear(); setTerms(null); setReport(null); setRefresh(x => x + 1) }
  return <div className="query-grades" role="tabpanel" hidden={!enabled} aria-label={words.title}>
    <header className="query-section-header"><h2><GraduationCap size={24} /> {words.title}</h2>
      <div className="query-grade-header-actions">
      <label className="query-grade-term-picker"><span>{words.term}</span><select aria-label={words.term} value={term ?? ''} disabled={!terms || !hasAccount} onChange={change(setTerm)}>
        <option value="">{words.all}</option>
        {(terms?.terms || []).map(item => <option key={item.id} value={item.id}>{item.name || item.id}{item.id === terms.current_term_id ? ` · ${text('当前学期', 'Current semester')}` : ''}</option>)}
      </select></label>
      <button type="button" onClick={reload} disabled={loading || !hasAccount} aria-label={words.refresh}><RefreshCw size={18} />{words.refresh}</button>
      </div>
    </header>
    {!hasAccount ? <div className="query-grade-status"><p>{words.account}</p><button type="button" className="query-action-button" onClick={onOpenAccount}><Settings2 size={16} aria-hidden="true" />{words.settings}</button></div> : <>
      {refresh === 0 && <p className="query-grade-status">{text('点击“刷新成绩”读取本人成绩。', 'Use Refresh grades to retrieve your results.')}</p>}
      <div className="query-grade-filters">
        <label>{words.records}<select aria-label={words.records} value={recordType} onChange={change(setRecordType)}>
          <option value="1">{words.best}</option><option value="0">{words.first}</option><option value="">{words.attempts}</option>
        </select></label>
      </div>
      {loading ? <p role="status">{words.loading}</p> : null}
      {error ? <div className="query-error" role="alert"><p>{words.retry}</p><button type="button" onClick={reload}>{words.refresh}</button></div> : null}
      {report ? <>
        <div className="query-grade-summary">
          <strong>{terms?.terms.find(item => item.id === report.term_id)?.name || report.term_id || words.all}</strong>
          {report.average_grade_point !== '' && report.average_grade_point != null ? <span>{words.average} · {report.average_grade_point}</span> : null}
          <small>{words.updated} {report.fetched_at && Number.isFinite(Date.parse(report.fetched_at)) ? new Intl.DateTimeFormat(uiDateLocale(language), { timeZone: 'Asia/Shanghai', dateStyle: 'medium', timeStyle: 'short' }).format(new Date(report.fetched_at)) : '—'}</small>
        </div>
        {!report.items?.length ? <div className="query-grade-status"><p>{words.empty}</p>{term ? <button type="button" onClick={() => { request.current += 1; setReport(null); setTerm('') }}>{words.all}</button> : null}</div> : term==='' ? <div className="query-grade-term-groups">
          {groupGradesBySemester(report.items).map(group=><section className="query-grade-term-group" key={group.name}>
            <h3>{group.name||text('学期未确认','Term unconfirmed')}</h3>
            <div className="query-grade-list">{group.items.map(item=><GradeCard key={item.id} item={item} words={words}/>)}</div>
          </section>)}
        </div> : <div className="query-grade-list">
          {report.items.map(item => <GradeCard key={item.id} item={item} words={words} />)}
        </div>}
      </> : null}
    </>}
    <p className="query-source">{words.source}</p>
  </div>
}
