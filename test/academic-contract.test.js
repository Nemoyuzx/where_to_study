import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { transformSync } from 'esbuild'
import { courseTimeBounds, FALLBACK_SLOTS, getWeekState } from '../src/planner-domain.js'

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8')
const fixture = name => JSON.parse(read(`../contracts/v1/fixtures/${name}.json`))
const schema = JSON.parse(read('../contracts/v1/where-to-study.schema.json'))
const contract = read('../contracts/v1/README.md')
const schedule = fixture('schedule-exams.synthetic')
const projection = fixture('course-exam.synthetic')
const terms = fixture('grade-terms.synthetic')
const grades = fixture('grade-report.synthetic')
const rawGrades = fixture('sjd-grades.synthetic')
const rawExams = fixture('sjd-exams.synthetic')

// Deliberately bounded test helper for the keywords used by these definitions,
// not an exported JSON Schema validator. Independent assertions below also pin
// the security enums, old required fields, and runtime consumer behavior.
function validDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const date = new Date(`${value}T00:00:00Z`)
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value
}

function matches(value, rule) {
  if (rule.$ref && !matches(value, schema.$defs[rule.$ref.split('/').at(-1)])) return false
  if (rule.anyOf && !rule.anyOf.some(branch => matches(value, branch))) return false
  if (rule.allOf && !rule.allOf.every(branch => matches(value, branch))) return false
  if (rule.if) {
    const branch = matches(value, rule.if) ? rule.then : rule.else
    if (branch && !matches(value, branch)) return false
  }
  if ('const' in rule && value !== rule.const) return false
  if (rule.enum && !rule.enum.includes(value)) return false
  const types = rule.type == null ? [] : [].concat(rule.type)
  const typeMatches = type => type === 'null' ? value === null
    : type === 'array' ? Array.isArray(value)
      : type === 'integer' ? Number.isInteger(value)
        : type === 'object' ? value !== null && typeof value === 'object' && !Array.isArray(value)
          : typeof value === type
  if (types.length && !types.some(typeMatches)) return false
  if (typeof value === 'string') {
    if (rule.minLength != null && value.length < rule.minLength) return false
    if (rule.maxLength != null && value.length > rule.maxLength) return false
    if (rule.pattern && !new RegExp(rule.pattern).test(value)) return false
    if (rule.format === 'date' && !validDate(value)) return false
    if (rule.format === 'date-time' && (!validDate(value.slice(0, 10)) || !Number.isFinite(Date.parse(value)))) return false
  }
  if (typeof value === 'number') {
    if (rule.minimum != null && value < rule.minimum) return false
    if (rule.maximum != null && value > rule.maximum) return false
  }
  if (Array.isArray(value)) {
    if (rule.maxItems != null && value.length > rule.maxItems) return false
    if (rule.uniqueItems && new Set(value.map(item => JSON.stringify(item))).size !== value.length) return false
    if (rule.items && !value.every(item => matches(item, rule.items))) return false
  } else if (value && typeof value === 'object') {
    if (rule.required?.some(key => !Object.hasOwn(value, key))) return false
    if (rule.additionalProperties === false && Object.keys(value).some(key => !(key in (rule.properties || {})))) return false
    for (const [key, child] of Object.entries(rule.properties || {})) {
      if (Object.hasOwn(value, key) && !matches(value[key], child)) return false
    }
  }
  return true
}
const conforms = (name, value) => matches(value, schema.$defs[name])

// Compile the existing pure ArkTS consumer modules, without replacing parser
// algorithms with a JS copy and without loading any platform/network module.
const harmonyRoot = '../native/harmony/entry/src/main/ets/'
const pureModules = [
  'common/Utf8', 'common/Sha1', 'common/JsonUtil', 'common/StrictDates',
  'common/AcademicModels', 'net/SjdErrors', 'net/parsers/SjdAcademicParser',
]
const pureSource = pureModules.map(path => read(`${harmonyRoot}${path}.ets`)
  .replace(/^import\s[\s\S]*?;\s*$/gm, '')).join('\n')
const { code } = transformSync(pureSource, { loader: 'ts', format: 'esm' })
const { ExamSchedule, SJDAcademicParser } = await import(
  `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`,
)

test('academic additions preserve old required fields and normalized v1 fixtures', () => {
  assert.deepEqual(schema.$defs.schedule.required, ['term_id', 'term_start_date', 'fetched_at', 'courses'])
  assert.deepEqual(schema.$defs.course.required, [
    'id', 'name', 'teacher', 'room', 'week_text', 'week_numbers', 'exam_week_numbers',
    'weekday', 'start_slot', 'end_slot', 'section_text', 'time_range',
  ])
  for (const [name, file] of [['schedule', 'schedule'], ['classrooms_cache', 'classrooms'], ['holidays', 'holidays']]) {
    assert.ok(conforms(name, fixture(file)), `${file}: old fixture must remain valid`)
  }
  assert.ok(conforms('schedule', { ...fixture('schedule'), exam_schedule: null }))
  assert.ok(conforms('schedule', schedule))
  assert.ok(conforms('course', projection))
  assert.ok(conforms('grade_terms', terms))
  assert.ok(conforms('grade_report', grades))
  assert.equal(conforms('course', { ...fixture('schedule').courses[0], start_slot: -1 }), false)
})

test('exam schema distinguishes verified fresh/stale cache from an unavailable result', () => {
  const exams = schedule.exam_schedule
  assert.deepEqual(schema.$defs.exam_schedule.properties.status.enum, ['fresh', 'stale', 'failed'])
  assert.ok(conforms('exam_schedule', { ...exams, status: 'stale' }))
  assert.ok(conforms('exam_schedule', { ...exams, items: [] }))
  assert.ok(conforms('exam_schedule', { ...exams, status: 'failed', fetched_at: '', items: [] }))
  assert.equal(conforms('exam_schedule', { ...exams, status: 'failed' }), false)
  assert.equal(conforms('exam_schedule', { ...exams, status: 'unknown' }), false)
  assert.equal(conforms('exam_schedule', { ...exams, account_key: '' }), false)
  assert.equal(conforms('exam_schedule', { ...exams, account_key: 'synthetic-plaintext-account' }), false)
  assert.ok(conforms('exam_schedule', { ...exams, account_key: 'a'.repeat(40) }))
  assert.ok(conforms('exam_schedule', { ...exams, account_key: 'b'.repeat(64) }))
  assert.equal(conforms('exam_schedule', { ...exams, fetched_at: '' }), false)
  assert.equal(conforms('exam_schedule', { ...exams, fetched_at: '2026-09-12T08:00:00.123+08:00' }), false)
})

test('exam fields allow explicit pending values without accepting invalid time syntax', () => {
  const timed = schedule.exam_schedule.items[0]
  const pending = schedule.exam_schedule.items[2]
  const undated = schedule.exam_schedule.items[3]
  assert.ok(conforms('exam_arrangement', pending))
  assert.ok(conforms('exam_arrangement', undated))
  assert.equal(conforms('exam_arrangement', { ...timed, date: '2026-02-30' }), false)
  assert.equal(conforms('exam_arrangement', { ...timed, start_time: '24:00' }), false)
  assert.equal(conforms('exam_arrangement', { ...timed, end_time: '24:30' }), false)
  assert.ok(conforms('exam_arrangement', { ...timed, start_time: '23:15', end_time: '24:00' }))
  assert.equal(conforms('course', { ...projection, event_kind: 'exam_week' }), false)
  assert.deepEqual(schema.$defs.course.properties.event_kind.enum, ['exam', null])
  assert.match(schema.$defs.course.properties.exam_week_numbers.description, /must not infer exam-week/)
})

test('grade requests preserve current versus all semesters and best versus all records', () => {
  for (const request of [{}, { term_id: null }, { term_id: '' }, { term_id: terms.current_term_id }]) {
    assert.ok(conforms('grade_request', request))
  }
  for (const record_type of ['1', '0', '', null]) assert.ok(conforms('grade_request', { record_type }))
  assert.equal(conforms('grade_request', { record_type: 'best' }), false)
  assert.equal(conforms('grade_request', { term_id: '../other' }), false)
  assert.equal(conforms('grade_request', { xs0101id: 'synthetic-other-student' }), false)
  assert.equal(conforms('grade_report', { ...grades, record_type: null }), false)
  assert.ok(conforms('grade_report', { ...grades, items: [] }))
  assert.equal(conforms('grade_item', { ...grades.items[0], score: 0 }), false)
  assert.ok(conforms('grade_item', { ...grades.items[0], score: null }))
  assert.ok(conforms('grade_item', { id: 'synthetic-unpublished', name: '合成未公布示例' }))
})

test('private response and credential fields cannot enter normalized academic records', () => {
  for (const [name, value] of [['grade_report', grades], ['grade_item', grades.items[0]], ['exam_schedule', schedule.exam_schedule]]) {
    assert.equal(schema.$defs[name].additionalProperties, false)
    for (const key of ['account', 'password', 'token', 'cookie', 'student_name', 'student_id', 'raw_response']) {
      assert.equal(conforms(name, { ...value, [key]: 'synthetic-forbidden-value' }), false, `${name}.${key}`)
    }
  }
  for (const item of [...grades.items, ...schedule.exam_schedule.items]) assert.match(item.name, /合成.*非真实/)
  assert.match(contract, /教务密码时，即使独立教学云密码未变/)
  assert.match(contract, /fetch_grade_terms/)
  assert.match(contract, /fetch_grades/)
  assert.match(contract, /node --test test\/academic-contract\.test\.js/)
})

test('shared exam fixture round trips through the actual Harmony JSON consumer', () => {
  const decoded = ExamSchedule.fromJson(schedule.exam_schedule)
  assert.ok(decoded)
  assert.deepEqual(decoded.toJson(), schedule.exam_schedule)
  assert.equal(ExamSchedule.fromJson(undefined), null)
  assert.equal(ExamSchedule.fromJson(null), null)
  assert.equal(ExamSchedule.fromJson({ ...schedule.exam_schedule, account_key: '' }), null)
  const failed = ExamSchedule.fromJson({ ...schedule.exam_schedule, status: 'failed', items: [] })
  assert.deepEqual(failed.items, [])
  const parsed = SJDAcademicParser.exams(JSON.stringify(rawExams), schedule.term_id,
    schedule.exam_schedule.account_key, schedule.fetched_at)
  assert.deepEqual(parsed.items.map(item => {
    const { id, ...fields } = item.toJson()
    assert.ok(id.length > 0)
    return fields
  }), schedule.exam_schedule.items.map(({ id, ...fields }) => fields))
})

test('shared upstream grade fixture preserves zero, text, pending and semester metadata', () => {
  const parsed = SJDAcademicParser.grades(JSON.stringify(rawGrades), '', '', grades.fetched_at)
  assert.equal(parsed.averageGradePoint, null)
  assert.deepEqual(parsed.items.map(item => item.score), ['0', '通过', null])
  assert.deepEqual(parsed.items.map(item => item.credits), ['0', '2.5', null])
  assert.deepEqual(parsed.items.map(item => item.semesterName), grades.items.map(item => item.semester_name))
  const edited = structuredClone(rawGrades)
  edited.data[0].achievement[0].fraction = '通过'
  const updated = SJDAcademicParser.grades(JSON.stringify(edited), '', '', grades.fetched_at)
  assert.equal(updated.items[0].id, parsed.items[0].id, 'published score changes must retain the school record identity')
  assert.equal(SJDAcademicParser.grades('{"code":1,"data":[]}', '', '1', grades.fetched_at).items.length, 0)
  assert.throws(() => SJDAcademicParser.grades('{"code":0,"data":[]}', '', '1', grades.fetched_at))
})

test('projected fixture feeds exact-time consumers while raw schedule remains untouched', () => {
  assert.equal(courseTimeBounds(projection, FALLBACK_SLOTS).startMinutes, 510)
  assert.equal(courseTimeBounds(projection, FALLBACK_SLOTS).endMinutes, 607)
  assert.equal(getWeekState([projection], schedule.term_start_date, projection.event_date).dayCourses.length, 1)
  assert.equal(getWeekState([projection], schedule.term_start_date, '2026-09-08').dayCourses.length, 0)
  assert.ok(schedule.courses.every(course => course.event_kind == null))
  const androidCodec = read('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/ScheduleStore.kt')
  const appleModels = read('../native/apple/Sources/Shared/Models.swift')
  const rustModels = read('../src-tauri/src/models.rs')
  assert.match(androidCodec, /root\.optJSONObject\("exam_schedule"\)/)
  assert.match(appleModels, /var examSchedule: ExamSchedule\? = nil/)
  assert.match(appleModels, /case examSchedule = "exam_schedule"/)
  assert.match(rustModels, /#\[serde\(default[^\]]*\)\]\s*pub exam_schedule: Option<crate::academic::ExamSchedule>/)
})
