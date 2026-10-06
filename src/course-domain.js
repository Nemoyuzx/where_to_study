// Presentation derives only from already verified source fields. Never join
// different teaching platforms or infer submission from quiz completion.
export function isEbuCourse(course) {
  return typeof course?.name === 'string' && /^EBU/i.test(course.name.trim())
}

// Cache presentation uses the same conservative policy as WTSQmProtocol and
// native snapshot readers. Never filter real assignments for missing dates.
export function isQmplusAssessmentActivity(item) {
  if (item?.kind !== 'assignment' || typeof item.title !== 'string') return true
  let normalized = '', gap = false
  for (const scalar of item.title) {
    let cp = scalar.codePointAt(0)
    if (cp >= 0xFF01 && cp <= 0xFF5E) cp -= 0xFEE0
    const separator = (cp >= 9 && cp <= 13) || cp === 0x20 || cp === 0x85 || cp === 0xA0 ||
      cp === 0x1680 || (cp >= 0x2000 && cp <= 0x200A) || cp === 0x2028 || cp === 0x2029 ||
      cp === 0x202F || cp === 0x205F || cp === 0x3000 || cp === 0xFEFF ||
      [0x5F, 0x2D, 0x2F, 0x3A, 0x2212].includes(cp) || (cp >= 0x2010 && cp <= 0x2015)
    if (separator) { gap = normalized.length > 0; continue }
    if (gap) normalized += ' '
    gap = false
    normalized += String.fromCodePoint(cp >= 0x61 && cp <= 0x7A ? cp - 0x20 : cp)
  }
  return normalized !== 'COURSEWORK MARK REVIEW REQUEST' && normalized !== 'COURSEWORK MARK REVIEW REQUEST FORM'
}

export function qmplusActivitiesForCourse(snapshot, course) {
  if (course?.current_term_status !== 'current' || !isEbuCourse(course)) return []
  return (Array.isArray(snapshot?.activities) ? snapshot.activities : [])
    .filter(item => item.course_id === course.id && isQmplusAssessmentActivity(item))
}

const shanghaiDeadlineClock=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Shanghai',calendar:'gregory',numberingSystem:'latn',hourCycle:'h23',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit'})
// A deadline is a point, never a made-up lesson duration. Date-only and raw
// human-readable QM time text cannot authorize a timed marker.
export function deadlineMoment(value,source='ucloud') {
  if(typeof value!=='string')return null
  const match=value.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})?$/)
  if(!match||(source==='qmplus'&&!match[7]))return null
  const [year,month,day,hour,minute,second]=match.slice(1,7).map(part=>Number(part||0))
  if(month<1||month>12||day<1||hour>23||minute>59||second>59)return null
  const civil=new Date(0);civil.setUTCFullYear(year,month-1,day);civil.setUTCHours(hour,minute,second,0)
  if(civil.getUTCFullYear()!==year||civil.getUTCMonth()!==month-1||civil.getUTCDate()!==day)return null
  const timestamp=courseTimestamp(value.replace(' ','T')+(match[7]?'':'+08:00'))
  if(!Number.isFinite(timestamp))return null
  const date=new Date(timestamp),parts=Object.fromEntries(shanghaiDeadlineClock.formatToParts(date).map(part=>[part.type,part.value]))
  const minutes=Number(parts.hour)*60+Number(parts.minute)+Number(parts.second)/60+date.getUTCMilliseconds()/60000
  return {date:`${parts.year}-${parts.month}-${parts.day}`,minute:minutes,clock:`${parts.hour}:${parts.minute}${Number(parts.second)?`:${parts.second}`:''}`,timestamp}
}

export function courseDeadlineMomentGroups(data) {
  const groups=new Map(),seen=new Set()
  const add=(item,source,value,courseName='')=>{
    const moment=deadlineMoment(value,source)
    if(!moment)return
    const key=JSON.stringify([source,item.course_id??null,item.kind||'assignment',item.id,moment.timestamp])
    if(seen.has(key))return
    seen.add(key)
    const groupKey=JSON.stringify([moment.date,moment.minute])
    if(!groups.has(groupKey))groups.set(groupKey,{...moment,key:groupKey,items:[]})
    groups.get(groupKey).items.push({key,source,label:item.title,clock:moment.clock,assignmentItem:{...item,source,course_name:item.course_name||courseName,deadline:value}})
  }
  for(const item of data?.assignments||[])add(item,'ucloud',item.deadline)
  for(const course of data?.qm?.courses||[])for(const item of qmplusActivitiesForCourse(data.qm,course)) {
    if(item.kind==='assignment'||item.kind==='quiz')add(item,'qmplus',item.kind==='quiz'?item.closes_at:item.due_at,course.name)
  }
  return [...groups.values()].sort((a,b)=>a.date.localeCompare(b.date)||a.minute-b.minute)
}

export function timelineForDeadlineMoments(courseHours,groups) {
  const start=Math.min(courseHours.start,...groups.map(group=>Math.floor(group.minute/60)))
  const end=Math.max(courseHours.end,...groups.map(group=>Math.floor(group.minute/60)+1))
  return {start,end,scale:(end-start)/(courseHours.end-courseHours.start)}
}

// Move only the small clock label away from a lesson title; the dot retains
// its exact minute coordinate, including when the label must sit above it.
export function deadlineMomentLabelOffset(minute,courses,start,end,pixelsPerMinute) {
  const y=(minute-start)*pixelsPerMinute,height=(end-start)*pixelsPerMinute,labelHeight=18
  // Centre an ordinary thin bar on the real moment. The existing terminal
  // hour label supplies scrollable overflow at the day end; do not pull a
  // 23:59 bar up to an earlier apparent time merely to fit its text box.
  let top=Math.max(0,y-labelHeight/2)
  for(const course of courses.filter(course=>course.timed)) {
    const header=(course.startMinutes-start)*pixelsPerMinute
    if(top+labelHeight>header&&top<header+26)top=header+28<=height-labelHeight?header+28:Math.max(0,header-labelHeight-2)
  }
  return top-y
}

export function deadlineMomentBadges(groups,courses,start,end,pixelsPerMinute) {
  const labels=groups.map(group=>({groups:[group],top:(group.minute-start)*pixelsPerMinute+deadlineMomentLabelOffset(group.minute,courses,start,end,pixelsPerMinute)})).sort((a,b)=>a.top-b.top)
  const badges=[]
  for(const label of labels) {
    const previous=badges.at(-1)
    if(previous&&label.top<previous.top+20)previous.groups.push(...label.groups)
    else badges.push(label)
  }
  return badges.map(badge=>{
    const groups=badge.groups.sort((a,b)=>a.minute-b.minute)
    return {...groups[0],key:`badge:${groups.map(group=>group.key).join('|')}`,keys:groups.map(group=>group.key),items:groups.flatMap(group=>group.items),labelTop:badge.top}
  })
}

// The Teaching Cloud directory comes from /site/list/student/current. Group
// only this current-term view; source records, IDs and cached DTOs stay intact.
export function groupTeachingCloudCourses(directory) {
  const groups = new Map()
  for (const course of directory) {
    const name = typeof course.name === 'string' ? course.name.trim() : ''
    const key = JSON.stringify(name ? ['name', name] : ['id', String(course.id)])
    let group = groups.get(key)
    if (!group) {
      group = {...course, name: name || null, presentation_key: key, source_courses: [], teacher_names: []}
      groups.set(key, group)
    }
    group.source_courses.push(course)
    for (const teacher of course.teacher_names || []) {
      const value = typeof teacher === 'string' ? teacher.trim() : ''
      if (value && !group.teacher_names.includes(value)) group.teacher_names.push(value)
    }
  }
  return [...groups.values()]
}

export function teachingCloudCourseIDs(course) {
  return (course.source_courses || [course]).map(source => String(source.id))
}

export function assignmentsForCourse(items, course, directory) {
  if (!Array.isArray(items)) return null
  const courseIDs = new Set(teachingCloudCourseIDs(course))
  const name = course.name?.trim()
  const namedCourses = name ? directory.filter(c => c.name?.trim() === name) : []
  // An ID-less legacy item may belong to the logical group when every exact
  // name match is a member. An explicit unknown ID never falls back to a name.
  const uniqueName = namedCourses.length > 0 && (course.source_courses
    ? namedCourses.every(c => teachingCloudCourseIDs(c).every(id => courseIDs.has(id)))
    : namedCourses.length === 1)
  return items.filter(item => item.course_id != null
    ? courseIDs.has(String(item.course_id))
    : uniqueName && item.course_name?.trim() === name)
}

export function submissionCounts(items) {
  const counts = {pending: 0, submitted: 0}
  if (!Array.isArray(items)) return counts
  const pending = new Set(['未提交', 'not submitted', 'nothing submitted', 'no submissions have been made yet'])
  const submitted = new Set(['已提交', 'submitted', 'submitted for grading'])
  for (const item of items) {
    if (item.kind === 'quiz') continue
    const status = typeof item.status === 'string' ? item.status.trim().toLowerCase() : ''
    if (pending.has(status)) counts.pending++
    if (submitted.has(status)) counts.submitted++
  }
  return counts
}

export function courseTimestamp(value) {
  if(typeof value!=='string')return NaN
  // The existing Teaching Cloud parser retains its official Shanghai wall
  // clock format; do not reinterpret it as the Windows/Linux user's timezone.
  const zoned=/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(?::\d{2})?$/.test(value)
    ? value.replace(' ','T')+'+08:00' : value
  return Date.parse(zoned)
}

export function courseActivityKey(item) {
  return JSON.stringify([item.course_id??null,item.kind??'assignment',item.id,item.deadline??item.due_at??null,item.closes_at??null])
}

export class CourseRequestOwner {
  live=true
  lifecycle=0
  directory=0
  qm=0
  assignments=0
  detail=0
  next(source) {return ++this[source]}
  accepts(source,revision) {return this.live&&this[source]===revision}
  dispose() {this.live=false;for(const source of ['lifecycle','directory','qm','assignments','detail'])this.next(source)}
}
