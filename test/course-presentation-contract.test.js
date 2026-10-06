import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import {transformSync} from 'esbuild'
import React from 'react'
import * as jsxRuntime from 'react/jsx-runtime'
import * as icons from 'lucide-react'
import * as courseDomain from '../src/course-domain.js'
import * as locales from '../src/ui-languages.js'
import * as labels from '../src/ui-text.js'

const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8')
const courseSource=read('src/CourseHub.jsx')
function load(source,extra={}) {
  const module={exports:{}}
  const dependencies={'react':React,'react/jsx-runtime':jsxRuntime,'lucide-react':icons,
    './course-domain.js':courseDomain,'./ui-languages.js':locales,'./ui-text.js':labels,
    './use-course-data.js':{useCourseData:()=>({courses:null,assignments:null,qm:null})},
    './AnimatedDisclosure.jsx':({children})=>children,
    '@tauri-apps/api/event':{listen:()=>{throw new Error('unexpected event subscription')}},
    './GradesPanel.jsx':()=>null,'./PrivateQueriesPanel.jsx':()=>null,...extra}
  const code=transformSync(source,{loader:'jsx',jsx:'automatic',format:'cjs',target:'es2022'}).code
  new Function('require','module','exports',code)(name=>{
    assert.ok(Object.hasOwn(dependencies,name),`unexpected dependency ${name}`)
    return dependencies[name]
  },module,module.exports)
  return module.exports
}
// Export the private row only in this in-memory fixture, not the product API.
const {CourseRow,calendarCourseForAssignment}=load(`${courseSource}\nexport {CourseRow}`)
const {groupGradesBySemester}=load(read('src/GradesPanel.jsx'))
function descendants(node) {
  if(Array.isArray(node))return node.flatMap(descendants)
  if(!React.isValidElement(node))return []
  return [node,...descendants(node.props.children)]
}

test('course disclosure and info are sibling controls; folding keeps data and never requests it',()=>{
  let expanded=false,opens=0,requests=0
  const items=[{id:'activity-fixture',title:'Fixture task',deadline:'2026-10-09 12:00:00'}]
  const props={course:{id:'course-fixture',name:'Fixture course'},items,language:'en',source:'ucloud',
    onOpen:()=>{opens++},onRefresh:()=>{requests++}}
  const internals=React.__CLIENT_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE
  const dispatcher={useState:()=>[expanded,next=>{expanded=next(expanded)}],useId:()=> 'fixture-details'}
  function render() {
    const previous=internals.H;internals.H=dispatcher
    let tree
    try{tree=CourseRow(props)}finally{internals.H=previous}
    const nodes=descendants(tree)
    const main=nodes.find(node=>node.props.className==='course-list-row')
    const info=nodes.find(node=>node.props.className==='course-info-button')
    const reveal=nodes.find(node=>node.props.id===main.props['aria-controls'])
    assert.equal(descendants(main).filter(node=>node.type==='button').length,1)
    assert.equal(nodes.find(node=>node.props.items===items)?.props.items,items)
    assert.equal(reveal.props.expanded,expanded)
    const trailing=nodes.find(node=>node.props.className==='course-row-trailing')
    assert.equal(descendants(trailing).filter(node=>node.type==='button').length,2)
    return {main,info}
  }
  const initial=render();assert.equal(initial.main.props['aria-expanded'],false)
  initial.main.props.onClick();assert.equal(render().main.props['aria-expanded'],true)
  render().main.props.onClick();assert.equal(render().main.props['aria-expanded'],false)
  assert.equal(requests,0);assert.equal(opens,0)
  render().info.props.onClick();assert.equal(opens,1);assert.equal(expanded,false)
})

test('calendar course details reject ambiguous names, duplicate IDs and mismatched ID fallback',()=>{
  const first={id:'a',name:'Same'},second={id:'b',name:'Same'}
  assert.equal(calendarCourseForAssignment({course_id:'a',course_name:'Renamed'},[first,second]),first)
  assert.equal(calendarCourseForAssignment({course_id:'missing',course_name:'Same'},[first]),null)
  assert.equal(calendarCourseForAssignment({course_name:' Same '},[first]),first)
  assert.equal(calendarCourseForAssignment({course_name:'Same'},[first,second]),null)
  assert.equal(calendarCourseForAssignment({course_id:'a'},[first,{...first}]),null)
  assert.equal(calendarCourseForAssignment({},[first]),null)
})

test('QM calendar point opens the complete cached QM course without a cloud refresh or network request',()=>{
  const course={id:'ebu',name:'EBU Fixture',current_term_status:'current'}
  const activities=[{id:'a',course_id:'ebu',kind:'assignment',title:'Assignment'},{id:'q',course_id:'ebu',kind:'quiz',title:'Quiz'}]
  const {CalendarAssignmentCourseDetail}=load(courseSource,{'./use-course-data.js':{useCourseData:()=>({courses:[],assignments:[],qm:{courses:[course],activities}})}})
  const internals=React.__CLIENT_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE,previous=internals.H
  internals.H={useMemo:work=>work(),useEffect:()=>{}}
  let tree
  try{tree=CalendarAssignmentCourseDetail({item:{...activities[1],source:'qmplus'},language:'en',hasAcademicAccount:true,courseDataOwner:{refresh:()=>{throw Error('unexpected cloud request')},syncQM:()=>{throw Error('unexpected sync')}},onClose:()=>{}})}finally{internals.H=previous}
  assert.equal(tree.props.source,'qmplus');assert.equal(tree.props.course,course)
  assert.deepEqual(tree.props.items.map(item=>item.id),['a','q'])
  assert.equal(tree.props.onRefresh,undefined)
})

test('calendar details resolve any original teaching class ID to the complete current course group',()=>{
  const first={id:'a',name:'Same',teacher_names:['First']},second={id:'b',name:' Same ',teacher_names:['Second']}
  const groups=courseDomain.groupTeachingCloudCourses([first,second])
  assert.equal(calendarCourseForAssignment({course_id:'b',course_name:'Old name'},groups),groups[0])
  assert.equal(calendarCourseForAssignment({course_name:' Same '},groups),groups[0])
  assert.equal(calendarCourseForAssignment({course_id:'missing',course_name:'Same'},groups),null)
})

test('Teaching Cloud card, disclosure and info use one grouped projection with all teachers and assignments',()=>{
  const data={courses:[{id:'a',name:'Same',teacher_names:['First']},{id:'b',name:' Same ',teacher_names:['Second','First']}],
    assignments:[{id:'one',course_id:'a',status:'未提交'},{id:'two',course_id:'b',status:'已提交'}],qm:null}
  const {default:Hub,CourseRow:Row,CourseDetail:Detail,CourseActivityBody:Body}=load(
    `${courseSource}\nexport {CourseRow,CourseActivityBody}`,
    {'./use-course-data.js':{useCourseData:()=>data}})
  const internals=React.__CLIENT_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE
  const state=[],refs=[]
  function render(component,props) {
    let stateIndex=0,refIndex=0
    const previous=internals.H
    internals.H={useState:initial=>{
      const index=stateIndex++
      if(!(index in state))state[index]=initial
      return [state[index],value=>{state[index]=typeof value==='function'?value(state[index]):value}]
    },useRef:initial=>refs[refIndex++]||=( {current:initial} ),useEffect:()=>{},useMemo:fn=>fn(),useId:()=> 'merged-course'}
    try{return component(props)}finally{internals.H=previous}
  }
  const props={command:()=>{throw Error('unexpected fetch')},language:'en',hasAcademicAccount:true,qmplusEnabled:false}
  const rows=descendants(render(Hub,props)).filter(node=>node.type===Row)
  assert.equal(rows.length,1)
  assert.deepEqual(rows[0].props.course.teacher_names,['First','Second'])
  assert.deepEqual(rows[0].props.items,data.assignments)
  rows[0].props.onOpen()
  const detail=descendants(render(Hub,props)).find(node=>node.type===Detail)
  assert.ok(detail)
  assert.equal(detail.props.course.presentation_key,rows[0].props.course.presentation_key)
  assert.deepEqual(detail.props.items,data.assignments)
  const previous=internals.H
  internals.H={useState:initial=>[initial,()=>{}],useId:()=> 'merged-course-body'}
  try {
    const body=descendants(Row(rows[0].props)).find(node=>node.type===Body)
    assert.deepEqual(body.props.items,data.assignments)
    assert.deepEqual(courseDomain.submissionCounts(body.props.items),{pending:1,submitted:1})
  }finally{internals.H=previous}
  data.courses=[...data.courses].reverse()
  assert.deepEqual(descendants(render(Hub,props)).find(node=>node.type===Detail).props.items,data.assignments)
})

test('all-semester grade groups retain source order and unknown terms without inferring IDs',()=>{
  const items=[{id:'one',semester_name:'Autumn',score:0},{id:'two',semester_name:'Spring',score:'A'},
    {id:'three',semester_name:'Autumn',score:'B'},{id:'four',semester_name:''},{id:'five'}]
  const groups=groupGradesBySemester(items)
  assert.deepEqual(groups.map(group=>group.name),['Autumn','Spring',''])
  assert.deepEqual(groups.map(group=>group.items.map(item=>item.id)),[['one','three'],['two'],['four','five']])
  assert.equal(groups[0].items[0],items[0]);assert.equal(items[0].score,0)
})

test('language completion waits for native ACK, fonts and whole-UI three-frame stability',()=>{
  const app=read('src/App.jsx'),hook=read('src/use-language-transition.js')
  assert.match(app,/Promise\.all\(\[command\('set_interface_language',uiLanguage\),document\.fonts\?\.ready/)
  assert.match(app,/languageReadinessRef\.current\.target===target && languageReadinessRef\.current\.ready/)
  assert.match(hook,/document\.createTreeWalker\(root,NodeFilter\.SHOW_ELEMENT/)
  assert.match(hook,/\['H1','H2','H3','LABEL','BUTTON','SELECT','INPUT','P','SMALL','A','SPAN'\]/)
  assert.match(hook,/return stable>=3/)
  assert.doesNotMatch(hook,/element\.value|innerHTML|outerHTML|console\./)
  assert.match(app,/languageTransition\.overlay\.completed \? t\('完成'\) : 'Switching…'/)
  assert.match(app,/revision:languageTransition\.currentRevision\(\)/)
  assert.match(app,/languageTransition\.cancel\(marker\.revision\)/)
})

test('calendar all-day keyboard handling leaves assignment child buttons native activation intact',()=>{
  const app=read('src/App.jsx')
  const cell=app.slice(app.indexOf('key={`all-day-${dateString}`}'),app.indexOf('{summary.visible.map((item) =>'))
  assert.match(cell,/onKeyDown=\{\(event\) => \{\s*if \(event\.target !== event\.currentTarget\) return\s*if \(event\.key === 'Enter' \|\| event\.key === ' '\)/)
})
