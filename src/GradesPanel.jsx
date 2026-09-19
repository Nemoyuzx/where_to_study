import { useEffect, useRef, useState } from 'react'
import { GraduationCap, RefreshCw } from 'lucide-react'

// Only session state: no grade/name/student-ID persistence or console output.
export default function GradesPanel({ command, language, enabled, hasAccount, onOpenAccount }) {
  const en = language === 'en'
  const words = en ? {
    title: 'Grades', account: 'Save an academic account in Settings to view your own grades.',
    settings: 'Account settings', term: 'Semester', all: 'All semesters', best: 'Best', first: 'First',
    attempts: 'All records', records: 'Record type', refresh: 'Refresh grades', loading: 'Loading grades…',
    empty: 'No published grades in this selection. Try All semesters.', average: 'Average grade point',
    score: 'Grade', credits: 'Credits', retry: 'Unable to load grades. Check your academic account and try again.',
    source: 'Source: the university academic service. Results are shown on this device; this app does not upload them to its servers.',
    updated: 'Updated',
  } : {
    title: '成绩查询', account: '请先在设置中保存教务账号，再查看本人的成绩。', settings: '个人账户设置',
    term: '学年学期', all: '全部学期', best: '最好', first: '首次', attempts: '全部记录', records: '成绩记录',
    refresh: '刷新成绩', loading: '正在读取成绩…', empty: '当前选择暂无已公布成绩，可切换“全部学期”查看。',
    average: '平均学分绩点', score: '成绩', credits: '学分', retry: '成绩暂时无法读取，请检查教务账户后重试。',
    source: '数据来源：学校教务服务。成绩仅在本机显示，不上传至本应用服务端，请以学校实际记录为准。', updated: '更新于',
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
    if (!enabled || !hasAccount) return undefined
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
    // Metadata is deliberately loaded only on entry/explicit refresh.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, hasAccount, term, recordType, refresh])

  const change = setter => event => { request.current += 1; setReport(null); setError(''); setter(event.target.value) }
  const reload = () => { request.current += 1; cache.current.clear(); setTerms(null); setReport(null); setRefresh(x => x + 1) }
  return <div className="query-grades" role="tabpanel" hidden={!enabled} aria-label={words.title}>
    <header className="query-section-header"><h2><GraduationCap size={24} /> {words.title}</h2>
      <button type="button" onClick={reload} disabled={loading || !hasAccount} aria-label={words.refresh}><RefreshCw size={18} /></button>
    </header>
    {!hasAccount ? <div className="query-grade-status"><p>{words.account}</p><button type="button" onClick={onOpenAccount}>{words.settings}</button></div> : <>
      <div className="query-grade-filters">
        <label>{words.term}<select aria-label={words.term} value={term ?? ''} disabled={!terms} onChange={change(setTerm)}>
          <option value="">{words.all}</option>
          {(terms?.terms || []).map(item => <option key={item.id} value={item.id}>{item.name || item.id}</option>)}
        </select></label>
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
          <small>{words.updated} {report.fetched_at && Number.isFinite(Date.parse(report.fetched_at)) ? new Intl.DateTimeFormat(en ? 'en-GB' : 'zh-CN', { timeZone: 'Asia/Shanghai', dateStyle: 'medium', timeStyle: 'short' }).format(new Date(report.fetched_at)) : '—'}</small>
        </div>
        {!report.items?.length ? <div className="query-grade-status"><p>{words.empty}</p>{term ? <button type="button" onClick={() => { request.current += 1; setReport(null); setTerm('') }}>{words.all}</button> : null}</div> : <div className="query-grade-list">
          {report.items.map(item => <article className="query-grade-card" key={item.id}>
            <header><strong>{item.name}</strong><span className="query-grade-score" aria-label={`${words.score}: ${item.score === '' || item.score == null ? '—' : item.score}`}>{item.score === '' || item.score == null ? '—' : item.score}</span></header>
            <p>{words.credits} · {item.credits === '' || item.credits == null ? '—' : item.credits}{item.course_code ? ` · ${item.course_code}` : ''}</p>
            {item.semester_name ? <small>{item.semester_name}</small> : null}
            <small>{[item.course_attribute, item.course_nature, item.exam_nature, item.grade_status].filter(Boolean).join(' · ')}</small>
          </article>)}
        </div>}
      </> : null}
    </>}
    <p className="query-source">{words.source}</p>
  </div>
}
