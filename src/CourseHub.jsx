import {useEffect,useState,useRef} from 'react'
import {listen} from '@tauri-apps/api/event'
import {BookOpen,CheckCircle2,CalendarClock,Clock3,RefreshCw,ExternalLink,ChevronRight,X} from 'lucide-react'
import GradesPanel from './GradesPanel.jsx'
import PrivateQueriesPanel from './PrivateQueriesPanel.jsx'
import {assignmentsForCourse,isEbuCourse,submissionCounts,courseTimestamp,courseActivityKey,CourseRequestOwner} from './course-domain.js'

function time(value,en) {
  const date=new Date(courseTimestamp(value))
  return value&&Number.isFinite(date.getTime())?new Intl.DateTimeFormat(en?'en-GB':'zh-CN',{timeZone:'Asia/Shanghai',dateStyle:'medium',timeStyle:'short'}).format(date):(en?'Not announced':'未公布')
}

function CourseRow({course,items,en,source,onOpen}) {
  const counts=submissionCounts(items)
  return <button type="button" className="course-list-row" onClick={onOpen}>
    <span className="course-list-icon" aria-hidden="true"><BookOpen size={23}/></span>
    <span className="course-list-content"><strong>{course.name||course.id}</strong><span className="course-list-chips">
      {(course.teacher_names||[]).map(name=><span className="course-chip" key={name}><BookOpen size={13}/>{name}</span>)}
      {source==='qmplus'&&course.short_name&&<span className="course-chip">{course.short_name}</span>}
      {source==='qmplus'&&course.current_term_status==='unknown'&&<span className="course-chip">{en?'Term unconfirmed':'学期未确认'}</span>}
      {source==='qmplus'&&course.current_term_status==='other'&&<span className="course-chip">{en?'Other term':'其他学期'}</span>}
      {counts.pending>0&&<span className="course-chip"><Clock3 size={13}/>{en?'Pending':'待交'} {counts.pending}</span>}
      {counts.submitted>0&&<span className="course-chip"><CheckCircle2 size={13}/>{en?'Submitted':'已交'} {counts.submitted}</span>}
    </span></span><ChevronRight className="course-list-chevron" size={18} aria-hidden="true"/>
  </button>
}

function CourseDetail({course,source,items,en,busy,error,onRefresh,onClose}) {
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
      <header><div><small>{source==='qmplus'?'QMplus':(en?'Teaching Cloud Platform':'教学云平台')}</small><h2 id="course-detail-title">{course.name||course.id}</h2></div><button ref={close} type="button" onClick={onClose} aria-label={en?'Close course details':'关闭课程详情'}><X size={18}/></button></header>
      <div className="course-detail-body">
        {(course.teacher_names||[]).length>0&&<p>{course.teacher_names.join(' · ')}</p>}
        {source==='ucloud'&&<button type="button" className="query-action-button" disabled={busy} onClick={onRefresh}><RefreshCw size={16}/>{en?'Fetch / refresh assignments':'获取／刷新课程作业'}</button>}
        {busy&&<p role="status">{en?'Loading…':'正在读取…'}</p>}{error&&<p role="alert">{error}</p>}
        {items===null&&<p>{en?'Assignments have not been retrieved. No submission counts are inferred.':'尚未获取课程作业，不推测待交或已交数量。'}</p>}
        {source==='qmplus'&&course.current_term_status!=='current'?<p>{en?'This course is not confirmed as current. Its activities were not retrieved; consult the official course page.':'此课尚未确认属于本学期，未读取其活动，请在官方课程页核对。'}</p>:items?.length===0&&<p>{en?'No published activities in the synchronized result. This does not mean all work is complete.':'同步结果中没有本课已发布活动，不代表所有作业已完成。'}</p>}
        {(items||[]).slice(0,limit).map(item=><article className="course-activity" key={courseActivityKey(item)}>
          <strong>{item.kind==='quiz'?'Quiz':(item.kind==='assignment'?'Assignment':(en?'Assignment':'课程作业'))} · {item.title}</strong>
          {item.kind==='quiz'?<p>{en?'Opens':'开放'}：{time(item.opens_at,en)}<br/>{en?'Closes':'关闭'}：{time(item.closes_at,en)}{item.time_limit_seconds!=null&&<><br/>{en?'Attempt time limit':'作答限时'}：{item.time_limit_seconds} {en?'seconds':'秒'}</>}</p>
            :<p>{en?'Deadline':'截止'}：{time(item.due_at||item.deadline,en)}{item.cutoff_at&&<><br/>{en?'Cutoff':'最终截止'}：{time(item.cutoff_at,en)}</>}</p>}
          {item.status&&item.status!=='unknown'&&<small>{item.status}</small>}
          {item.detail_status&&item.detail_status!=='available'&&<p>{en?'Details are restricted or unavailable. Confirm on the official platform.':'详情受限或暂不可用，请以官方平台为准。'}</p>}
          {item.raw_time_text&&<p>{item.raw_time_text}</p>}
          {item.url&&<a href={item.url} target="_blank" rel="noreferrer"><ExternalLink size={14}/>{en?'Official activity':'官方活动详情'}</a>}
        </article>)}
        {items?.length>limit&&<button type="button" onClick={()=>setLimit(value=>value+30)}>{en?'Show more':'加载更多'}</button>}
        <p className="query-source">{en?'Counts refer only to synchronized assignments with explicit submission states. Dates use Beijing time; London daylight saving is respected.':'数量仅统计已同步且明确提交状态的作业。时间按北京时间展示，伦敦时间遵守夏令时。'}</p>
        {course.url&&<a className="external-action-button" href={course.url} target="_blank" rel="noreferrer"><ExternalLink size={16}/>{source==='qmplus'?(en?'QMplus course page':'QMplus 课程页'):(en?'Open Teaching Cloud Platform':'打开教学云平台')}</a>}
      </div>
    </section>
  </div>
}

export default function CourseHub({command,language,hasAcademicAccount,onOpenAccount,examSnapshot}) {
  const en=language==='en'
  const [tab,setTab]=useState('courses'),[courses,setCourses]=useState(null),[qm,setQm]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState('')
  const [assignmentItems,setAssignmentItems]=useState(null),[selection,setSelection]=useState(null),[detailBusy,setDetailBusy]=useState(false),[detailError,setDetailError]=useState('')
  const owner=useRef(null)
  if(!owner.current)owner.current=new CourseRequestOwner()
  const previousAccount=useRef(hasAcademicAccount)
  async function loadQM() {
    const revision=owner.current.next('qm')
    try {const value=await command('load_qmplus');if(owner.current.accepts('qm',revision))setQm(value)}catch{}
  }
  async function reload(force=false) {
    const revision=owner.current.next('directory')
    setBusy(true);setError('')
    void loadQM()
    try {
      const value=hasAcademicAccount?await command('fetch_course_list',{payload:{force}}):[]
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
    } catch {if(owner.current.accepts('detail',detailRevision))setDetailError(en?'Unable to retrieve assignments. Check your Teaching Cloud password in Settings.':'课程作业获取失败，请检查设置中的教学云平台密码。')}
    finally {if(owner.current.accepts('detail',detailRevision))setDetailBusy(false)}
  }
  function open(source,course) {owner.current.next('detail');setSelection({source,id:course.id});setDetailError('');setDetailBusy(false)}
  function closeDetail(){owner.current.next('detail');setSelection(null);setDetailBusy(false);setDetailError('')}
  const eligibleQmCourses=(qm?.courses||[]).filter(isEbuCourse)
  const qmCourses=eligibleQmCourses.filter(course=>course.current_term_status==='current')
  const otherQmCourses=eligibleQmCourses.filter(course=>course.current_term_status!=='current')
  const selectedCourse=selection&&(selection.source==='qmplus'?eligibleQmCourses:courses||[]).find(course=>course.id===selection.id)
  const qmActivities=course=>course.current_term_status==='current'?(qm?.activities||[]).filter(item=>item.course_id===course.id):[]
  const cloudActivities=course=>assignmentsForCourse(assignmentItems,course,courses||[])
  useEffect(()=>{if(selection&&!selectedCourse)closeDetail()},[selection,selectedCourse])
  const tabs=[['courses',BookOpen,en?'My courses':'本学期课程'],['grades',CheckCircle2,en?'Grades':'成绩查询'],['exams',CalendarClock,en?'Exams':'考试查询'],['assignments',Clock3,en?'Assignments':'课程作业']]
  return <section className="course-hub">
    <div className="query-hub-segments" role="tablist" aria-label={en?'Course services':'课程服务'}>{tabs.map(([key,Icon,label])=><button role="tab" aria-selected={key===tab} className={key===tab?'active':''} key={key} onClick={()=>setTab(key)}><Icon size={17}/>{label}</button>)}</div>
    <GradesPanel command={command} language={language} enabled={tab==='grades'} hasAccount={hasAcademicAccount} onOpenAccount={onOpenAccount}/>
    {['exams','assignments'].map(kind=><PrivateQueriesPanel key={kind} kind={kind} enabled={tab===kind} command={command} language={language} hasAccount={hasAcademicAccount} onOpenAccount={onOpenAccount} examSnapshot={examSnapshot} assignmentSnapshot={assignmentItems} onAssignmentRequest={()=>owner.current.next('assignments')} onAssignmentSnapshot={(value,revision)=>{if(owner.current.accepts('assignments',revision))setAssignmentItems(value)}}/>)}
    {tab==='courses'&&<>
      <header className="query-section-header"><div><h2>{en?'Teaching Cloud courses':'教学云平台课程'}</h2>{courses!==null&&<small>{courses.length} {en?'courses':'门'}</small>}</div><button disabled={busy} onClick={()=>reload(true)}><RefreshCw size={16}/>{en?'Refresh':'刷新'}</button></header>
      {error&&<p role="alert">{error}</p>}{!hasAcademicAccount&&<button onClick={onOpenAccount}>{en?'Configure academic account':'前往个人账户'}</button>}
      <div className="course-list">{(courses||[]).map(course=><CourseRow key={course.id} course={course} items={cloudActivities(course)} en={en} source="ucloud" onOpen={()=>open('ucloud',course)}/>)}</div>
      {courses?.length===0&&<p>{en?'No current courses returned.':'当前接口没有返回课程。'}</p>}
      <header className="query-section-header"><div><h2>QMplus · {en?'EBU courses':'EBU 课程'}</h2>{qm&&<small>{qmCourses.length} {en?'courses':'门'}</small>}</div><div className="course-actions"><button onClick={()=>command('connect_qmplus').catch(e=>setError(String(e)))}><ExternalLink size={16}/>{en?'Connect / sync':'连接／同步'}</button><button onClick={()=>reload()}><RefreshCw size={16}/>{en?'Load synchronized data':'读取同步结果'}</button></div></header>
      {qm?.partial&&<p role="status">{en?'Partial synchronization; previous data and its original timestamp may be retained.':'同步不完整，可能保留上次成功数据及其原同步时间。'}</p>}
      {!qm&&<p>{en?'Connect QMplus in Settings and complete official SSO/MFA.':'请在设置连接 QMplus，并在官方网页完成 SSO／MFA。'}</p>}
      <div className="course-list">{qmCourses.map(course=><CourseRow key={course.id} course={course} items={qmActivities(course)} en={en} source="qmplus" onOpen={()=>open('qmplus',course)}/>)}</div>
      {otherQmCourses.length>0&&<details className="course-other-terms"><summary>{en?'Other / unconfirmed EBU courses':'其他／学期未确认的 EBU 课程'} ({otherQmCourses.length})</summary><div className="course-list">{otherQmCourses.map(course=><CourseRow key={course.id} course={course} items={[]} en={en} source="qmplus" onOpen={()=>open('qmplus',course)}/>)}</div></details>}
      {qm&&<small>{en?'Last synchronized':'最近同步'}：{time(qm.fetched_at,en)} · QMplus</small>}
    </>}
    {selectedCourse&&<CourseDetail key={`${selection.source}:${selection.id}`} course={selectedCourse} source={selection.source} items={selection.source==='qmplus'?qmActivities(selectedCourse):cloudActivities(selectedCourse)} en={en} busy={detailBusy} error={detailError} onRefresh={refreshAssignments} onClose={closeDetail}/>}
  </section>
}
