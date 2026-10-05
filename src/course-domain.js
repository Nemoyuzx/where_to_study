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
