import { uiText } from './ui-text.js'
import { uiDateLocale } from './ui-languages.js'
import {useEffect,useState,useRef} from 'react'
import {listen} from '@tauri-apps/api/event'
import {BookOpen,CheckCircle2,CalendarClock,Clock3,RefreshCw,ExternalLink,ChevronRight,X} from 'lucide-react'
import GradesPanel from './GradesPanel.jsx'
import PrivateQueriesPanel from './PrivateQueriesPanel.jsx'
import {assignmentsForCourse,isEbuCourse,qmplusActivitiesForCourse,submissionCounts,courseTimestamp,courseActivityKey,CourseRequestOwner} from './course-domain.js'

function time(value,language) {
  const date=new Date(courseTimestamp(value))
  return value&&Number.isFinite(date.getTime())?new Intl.DateTimeFormat(uiDateLocale(language),{timeZone:'Asia/Shanghai',dateStyle:'medium',timeStyle:'short'}).format(date):uiText(language, '未公布', 'Not announced')
}

function CourseRow({course,items,en,language,source,onOpen}) {
  const text=(zh,english,values)=>uiText(language,zh,english,values)
  const counts=submissionCounts(items)
  return <button type="button" className="course-list-row" onClick={onOpen}>
    <span className="course-list-icon" aria-hidden="true"><BookOpen size={23}/></span>
    <span className="course-list-content"><strong>{course.name||course.id}</strong><span className="course-list-chips">
      {(course.teacher_names||[]).map(name=><span className="course-chip" key={name}><BookOpen size={13}/>{name}</span>)}
      {source==='qmplus'&&course.short_name&&<span className="course-chip">{course.short_name}</span>}
      {source==='qmplus'&&course.current_term_status==='unknown'&&<span className="course-chip">{text('学期未确认', 'Term unconfirmed')}</span>}
      {source==='qmplus'&&course.current_term_status==='other'&&<span className="course-chip">{text('其他学期', 'Other term')}</span>}
      {counts.pending>0&&<span className="course-chip"><Clock3 size={13}/>{text('待交', 'Pending')} {counts.pending}</span>}
      {counts.submitted>0&&<span className="course-chip"><CheckCircle2 size={13}/>{text('已交', 'Submitted')} {counts.submitted}</span>}
    </span></span><ChevronRight className="course-list-chevron" size={18} aria-hidden="true"/>
  </button>
}

function CourseDetail({course,source,items,en,language,busy,error,onRefresh,onClose}) {
  const text=(zh,english,values)=>uiText(language,zh,english,values)
  const dialog=useRef(null),close=useRef(null)
  const [limit,setLimit]=useState(30)
  useEffect(()=>{
    const previous=document.activeElement
    close.current?.focus()
    function keyboard(event) {
      if(event.key==='Escape'){event.preventDefault();event.stopPropagation();onClose();return}
      if(event.key!=='Tab')return
      const elements=Array.from(dialog.current?.querySelectorAll('button:not(:disabled),a[href],[tabindex="0"]')||[])
      if(!elements.length)return
      if(event.shiftKey&&document.activeElement===elements[0]){event.preventDefault();elements.at(-1).focus()}
      else if(!event.shiftKey&&document.activeElement===elements.at(-1)){event.preventDefault();elements[0].focus()}
    }
    window.addEventListener('keydown',keyboard,true)
    return()=>{window.removeEventListener('keydown',keyboard,true);if(previous?.isConnected)previous.focus();else document.querySelector('.course-hub [role="tab"][aria-selected="true"]')?.focus()}
  },[])
  return <div className="calendar-agenda-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget&&event.button===0)onClose()}}>
    <section ref={dialog} className="calendar-agenda-dialog course-detail-dialog" role="dialog" aria-modal="true" aria-labelledby="course-detail-title">
      <header><div><small>{source==='qmplus'?'QMplus':(text('教学云平台', 'Teaching Cloud Platform'))}</small><h2 id="course-detail-title">{course.name||course.id}</h2></div><button ref={close} type="button" onClick={onClose} aria-label={text('关闭课程详情', 'Close course details')}><X size={18}/></button></header>
      <div className="course-detail-body">
        {(course.teacher_names||[]).length>0&&<p>{course.teacher_names.join(' · ')}</p>}
        {source==='ucloud'&&<button type="button" className="query-action-button" disabled={busy} onClick={onRefresh}><RefreshCw size={16}/>{text('获取／刷新课程作业', 'Fetch / refresh assignments')}</button>}
        {busy&&<p role="status">{text('正在读取…', 'Loading…')}</p>}{error&&<p role="alert">{error}</p>}
        {items===null&&<p>{text('尚未获取课程作业，不推测待交或已交数量。', 'Assignments have not been retrieved. No submission counts are inferred.')}</p>}
        {source==='qmplus'&&course.current_term_status!=='current'?<p>{text('此课尚未确认属于本学期，未读取其活动，请在官方课程页核对。', 'This course is not confirmed as current. Its activities were not retrieved; consult the official course page.')}</p>:items?.length===0&&<p>{text('同步结果中没有本课已发布活动，不代表所有作业已完成。', 'No published activities in the synchronized result. This does not mean all work is complete.')}</p>}
        {(items||[]).slice(0,limit).map(item=><article className="course-activity" key={courseActivityKey(item)}>
          <strong>{item.kind==='quiz'?'Quiz':(item.kind==='assignment'?'Assignment':(text('课程作业', 'Assignment')))} · {item.title}</strong>
          {item.kind==='quiz'?<p>{text('开放时间', 'Opens')}：{time(item.opens_at,language)}<br/>{text('关闭时间', 'Closes')}：{time(item.closes_at,language)}{item.time_limit_seconds!=null&&<><br/>{text('时间限制（秒）', 'Time limit (seconds)')}：{item.time_limit_seconds}</>}</p>
            :<p>{text('截止', 'Deadline')}：{time(item.due_at||item.deadline,language)}{item.cutoff_at&&<><br/>{text('最终截止', 'Cutoff')}：{time(item.cutoff_at,language)}</>}</p>}
          {item.status&&item.status!=='unknown'&&<small>{item.status}</small>}
          {item.detail_status&&item.detail_status!=='available'&&<p>{text('详情受限或暂不可用，请以官方平台为准。', 'Details are restricted or unavailable. Confirm on the official platform.')}</p>}
          {item.raw_time_text&&<p>{item.raw_time_text}</p>}
          {item.url&&<a href={item.url} target="_blank" rel="noreferrer"><ExternalLink size={14}/>{source==='qmplus' ? text('打开 QMplus 官方活动页', 'Open official QMplus activity') : text('打开教学云平台', 'Open Teaching Cloud Platform')}</a>}
        </article>)}
        {items?.length>limit&&<button type="button" onClick={()=>setLimit(value=>value+30)}>{text('加载更多', 'Show more')}</button>}
        <p className="query-source">{text('数量仅统计已同步且明确提交状态的作业。时间按北京时间展示，伦敦时间遵守夏令时。', 'Counts refer only to synchronized assignments with explicit submission states. Dates use Beijing time; London daylight saving is respected.')}</p>
        {course.url&&<a className="external-action-button" href={course.url} target="_blank" rel="noreferrer"><ExternalLink size={16}/>{source==='qmplus'?(text('QMplus 课程页', 'QMplus course page')):(text('打开教学云平台', 'Open Teaching Cloud Platform'))}</a>}
      </div>
    </section>
  </div>
}

export default function CourseHub({command,language,hasAcademicAccount,onOpenAccount,examSnapshot,qmplusEnabled = false}) {
  const en=language==='en'
  const text=(zh,english,values)=>uiText(language,zh,english,values)
  const [tab,setTab]=useState('courses'),[courses,setCourses]=useState(null),[qm,setQm]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState('')
  const [assignmentItems,setAssignmentItems]=useState(null),[selection,setSelection]=useState(null),[detailBusy,setDetailBusy]=useState(false),[detailError,setDetailError]=useState('')
  const owner=useRef(null)
  if(!owner.current)owner.current=new CourseRequestOwner()
  const previousAccount=useRef(hasAcademicAccount)
  const qmplusEnabledRef=useRef(qmplusEnabled)
  qmplusEnabledRef.current=qmplusEnabled
  async function loadQM() {
    if(!qmplusEnabledRef.current)return
    const revision=owner.current.next('qm')
    try {const value=await command('load_qmplus');if(qmplusEnabledRef.current&&owner.current.accepts('qm',revision))setQm(value)}catch{}
  }
  async function reload(force=false) {
    const revision=owner.current.next('directory')
    setBusy(true);setError('')
    void loadQM()
    try {
      const value=hasAcademicAccount?await command('fetch_course_list',{force}):[]
      if(owner.current.accepts('directory',revision))setCourses(value)
    }catch(reason){if(owner.current.accepts('directory',revision))setError(en?'Teaching Cloud courses could not be refreshed. Previous data is retained.':String(reason?.message||reason))}
    finally{if(owner.current.accepts('directory',revision))setBusy(false)}
  }
  useEffect(()=>{owner.current.live=true;const lifecycle=owner.current.next('lifecycle');let remove
    if(window.__TAURI_INTERNALS__)listen('qmplus:changed',()=>{if(owner.current.accepts('lifecycle',lifecycle))void loadQM()})
      .then(fn=>{if(!owner.current.accepts('lifecycle',lifecycle))fn();else{remove=fn;void reload()}})
      .catch(()=>{if(owner.current.accepts('lifecycle',lifecycle))void reload()})
    else void reload()
    return()=>{owner.current.dispose();remove?.()}
  },[])
  useEffect(()=>{
    if(qmplusEnabled)void loadQM()
    else {owner.current.next('qm');if(selection?.source==='qmplus')closeDetail()}
  },[qmplusEnabled])
  useEffect(()=>{
    if(previousAccount.current===hasAcademicAccount)return
    previousAccount.current=hasAcademicAccount
    if(!hasAcademicAccount){owner.current.next('directory');owner.current.next('assignments');owner.current.next('detail');setCourses([]);setAssignmentItems(null);setDetailBusy(false);setBusy(false);setSelection(value=>value?.source==='ucloud'?null:value)}
    else void reload()
  },[hasAcademicAccount])
  async function refreshAssignments() {
    const revision=owner.current.next('assignments'),detailRevision=owner.current.detail
    setDetailBusy(true);setDetailError('')
    try {
      const items=await command('fetch_assignment_list',{force:true})
      if(owner.current.accepts('assignments',revision))setAssignmentItems(items)
    } catch {if(owner.current.accepts('detail',detailRevision))setDetailError(text('课程作业获取失败，请检查设置中的教学云平台密码。', 'Unable to retrieve assignments. Check your Teaching Cloud password in Settings.'))}
    finally {if(owner.current.accepts('detail',detailRevision))setDetailBusy(false)}
  }
  function open(source,course) {owner.current.next('detail');setSelection({source,id:course.id});setDetailError('');setDetailBusy(false)}
  function closeDetail(){owner.current.next('detail');setSelection(null);setDetailBusy(false);setDetailError('')}
  const eligibleQmCourses=(qm?.courses||[]).filter(isEbuCourse)
  const qmCourses=eligibleQmCourses.filter(course=>course.current_term_status==='current')
  const otherQmCourses=eligibleQmCourses.filter(course=>course.current_term_status!=='current')
  const selectedCourse=selection&&(selection.source==='qmplus'?(qmplusEnabled?eligibleQmCourses:[]):courses||[]).find(course=>course.id===selection.id)
  const qmActivities=course=>qmplusActivitiesForCourse(qm,course)
  const cloudActivities=course=>assignmentsForCourse(assignmentItems,course,courses||[])
  useEffect(()=>{if(selection&&!selectedCourse)closeDetail()},[selection,selectedCourse])
  const tabs=[['courses',BookOpen,text('本学期课程', 'My courses')],['grades',CheckCircle2,text('成绩查询', 'Grades')],['exams',CalendarClock,text('考试查询', 'Exams')],['assignments',Clock3,text('课程作业', 'Assignments')]]
  return <section className="course-hub">
    <div className="query-hub-segments" role="tablist" aria-label={text('课程服务', 'Course services')}>{tabs.map(([key,Icon,label])=><button role="tab" aria-selected={key===tab} className={key===tab?'active':''} key={key} onClick={()=>setTab(key)}><Icon size={17}/>{label}</button>)}</div>
    <GradesPanel command={command} language={language} enabled={tab==='grades'} hasAccount={hasAcademicAccount} onOpenAccount={onOpenAccount}/>
    {['exams','assignments'].map(kind=><PrivateQueriesPanel key={kind} kind={kind} enabled={tab===kind} command={command} language={language} hasAccount={hasAcademicAccount} onOpenAccount={onOpenAccount} examSnapshot={examSnapshot} assignmentSnapshot={assignmentItems} onAssignmentRequest={()=>owner.current.next('assignments')} onAssignmentSnapshot={(value,revision)=>{if(owner.current.accepts('assignments',revision))setAssignmentItems(value)}}/>)}
    {tab==='courses'&&<>
      <header className="query-section-header"><div><h2>{text('教学云平台课程', 'Teaching Cloud courses')}</h2>{courses!==null&&<small>{courses.length} {text('门', 'courses')}</small>}</div><button disabled={busy} onClick={()=>reload(true)}><RefreshCw size={16}/>{text('刷新', 'Refresh')}</button></header>
      {error&&<p role="alert">{error}</p>}{!hasAcademicAccount&&<button onClick={onOpenAccount}>{text('前往个人账户', 'Configure academic account')}</button>}
      <div className="course-list">{(courses||[]).map(course=><CourseRow key={course.id} course={course} items={cloudActivities(course)} en={en} language={language} source="ucloud" onOpen={()=>open('ucloud',course)}/>)}</div>
      {courses?.length===0&&<p>{text('当前接口没有返回课程。', 'No current courses returned.')}</p>}
      {qmplusEnabled&&<>
      <header className="query-section-header"><div><div className="qmplus-title"><h2>QMplus · {text('EBU 课程', 'EBU courses')}</h2><small>{text('仅适用国院','For the International School only')}</small></div>{qm&&<small>{qmCourses.length} {text('门', 'courses')}</small>}</div><div className="course-actions"><button onClick={()=>command('connect_qmplus').catch(e=>setError(String(e)))}><ExternalLink size={16}/>{text('连接／同步', 'Connect / sync')}</button><button onClick={()=>reload()}><RefreshCw size={16}/>{text('读取同步结果', 'Load synchronized data')}</button></div></header>
      {qm?.partial&&<p role="status">{text('同步不完整，可能保留上次成功数据及其原同步时间。', 'Partial synchronization; previous data and its original timestamp may be retained.')}</p>}
      {!qm&&<p>{text('请在设置连接 QMplus，并在官方网页完成 SSO／MFA。', 'Connect QMplus in Settings and complete official SSO/MFA.')}</p>}
      <div className="course-list">{qmCourses.map(course=><CourseRow key={course.id} course={course} items={qmActivities(course)} en={en} language={language} source="qmplus" onOpen={()=>open('qmplus',course)}/>)}</div>
      {otherQmCourses.length>0&&<details className="course-other-terms"><summary>{text('其他／学期未确认的 EBU 课程', 'Other / unconfirmed EBU courses')} ({otherQmCourses.length})</summary><div className="course-list">{otherQmCourses.map(course=><CourseRow key={course.id} course={course} items={[]} en={en} language={language} source="qmplus" onOpen={()=>open('qmplus',course)}/>)}</div></details>}
      {qm&&<small>{text('最近同步', 'Last synchronized')}：{time(qm.fetched_at,language)} · QMplus</small>}
      </>}
    </>}
    {selectedCourse&&<CourseDetail key={`${selection.source}:${selection.id}`} course={selectedCourse} source={selection.source} items={selection.source==='qmplus'?qmActivities(selectedCourse):cloudActivities(selectedCourse)} en={en} language={language} busy={detailBusy} error={detailError} onRefresh={refreshAssignments} onClose={closeDetail}/>}
  </section>
}
