// Presentation derives only from already verified source fields. Never join
// different teaching platforms or infer submission from quiz completion.
export function isEbuCourse(course) {
  return typeof course?.name === 'string' && /^EBU/i.test(course.name.trim())
}

export function assignmentsForCourse(items, course, directory) {
  if (!Array.isArray(items)) return null
  const name = course.name?.trim()
  const uniqueName = name && directory.filter(c => c.name?.trim() === name).length === 1
  return items.filter(item => item.course_id != null
    ? String(item.course_id) === String(course.id)
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
