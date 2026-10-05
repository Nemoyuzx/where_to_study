import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import {transformSync} from 'esbuild'
import React from 'react'
import * as jsxRuntime from 'react/jsx-runtime'
import {renderToStaticMarkup} from 'react-dom/server'
import * as icons from 'lucide-react'
import * as planner from '../src/planner-domain.js'
import * as dateLocales from '../src/ui-languages.js'
import * as labels from '../src/ui-text.js'
import * as query from '../src/query-domain.js'

const source=readFileSync(new URL('../src/QueryHub.jsx',import.meta.url),'utf8')
const css=readFileSync(new URL('../src/App.css',import.meta.url),'utf8')
const dependencies={'react':React,'react/jsx-runtime':jsxRuntime,'lucide-react':icons,
  './planner-domain.js':planner,'./ui-languages.js':dateLocales,'./ui-text.js':labels,'./query-domain.js':query}
const module={exports:{}}
const code=transformSync(source,{loader:'jsx',jsx:'automatic',format:'cjs',target:'es2022'}).code
new Function('require','module','exports',code)(name=>{
  assert.ok(Object.hasOwn(dependencies,name),`unexpected dependency ${name}`)
  return dependencies[name]
},module,module.exports)
const Card=module.exports.ShuttleFullTimetableCard
const props={title:'完整班车时刻表',description:'按运行时段、方向和星期查看计划班次。',
  sourceURL:'https://example.invalid/shuttle-notice',sourceLabel:'后勤部原文',
  children:React.createElement('table',null,React.createElement('tbody',null,
    React.createElement('tr',null,React.createElement('td',null,'08:00'))))}

function descendants(node) {
  if(Array.isArray(node))return node.flatMap(descendants)
  if(!React.isValidElement(node))return []
  return [node,...descendants(node.props.children)]
}
function interactiveCard(initialProps) {
  // Invoke the real component with a local hook dispatcher; no browser/DOM or effects.
  const internals=React.__CLIENT_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE
  assert.ok(internals)
  let value
  const dispatcher={useState(initial){
    if(value===undefined)value=typeof initial==='function'?initial():initial
    return [value,next=>{value=typeof next==='function'?next(value):next}]
  },useId:()=> 'shuttle-fixture-details'}
  return {render(){const prior=internals.H;internals.H=dispatcher
    try{return Card(initialProps)}finally{internals.H=prior}
  }}
}

test('full timetable renders collapsed with a labelled control, inert retained content and an always-visible source',()=>{
  const markup=renderToStaticMarkup(React.createElement(Card,props))
  assert.match(markup,/aria-label="完整班车时刻表"/)
  assert.match(markup,/aria-expanded="false"/)
  assert.match(markup,/aria-hidden="true" inert=""/)
  assert.match(markup,/<table><tbody><tr><td>08:00<\/td>/)
  assert.match(markup,/<header[^>]*>[\s\S]*href="https:\/\/example\.invalid\/shuttle-notice"[\s\S]*后勤部原文/)
  const controls=[...markup.matchAll(/aria-controls="([^"]+)"/g)].map(match=>match[1])
  assert.equal(controls.length,1)
  assert.ok(markup.includes(`id="${controls[0]}"`))
  assert.match(markup,/weather-strip-chevron/)
})

test('expand and collapse update only disclosure state and preserve the timetable children and source',()=>{
  let requests=0
  const instance=interactiveCard({...props,command:()=>{requests++;throw new Error('unexpected request')}})
  function render(){
    const tree=instance.render(),nodes=descendants(tree)
    const button=nodes.find(node=>node.type==='button')
    const reveal=nodes.find(node=>node.props.className?.includes('weather-strip-reveal')&&node.props.inert!==undefined)
    const content=nodes.find(node=>node.props.id===button.props['aria-controls'])
    const link=nodes.find(node=>node.type==='a')
    assert.equal(content.props.children,props.children)
    assert.equal(link.props.href,props.sourceURL)
    return {button,reveal}
  }
  const closed=render()
  assert.equal(closed.button.props['aria-expanded'],false)
  assert.equal(closed.reveal.props.inert,true)
  closed.button.props.onClick()
  const expanded=render()
  assert.equal(expanded.button.props['aria-expanded'],true)
  assert.equal(expanded.reveal.props['aria-hidden'],false)
  assert.equal(expanded.reveal.props.inert,false)
  assert.ok(expanded.reveal.props.className.includes('expanded'))
  expanded.button.props.onClick()
  const collapsed=render()
  assert.equal(collapsed.button.props['aria-expanded'],false)
  assert.equal(collapsed.reveal.props.inert,true)
  assert.equal(requests,0)
})

test('independent cards have unique controlled regions and share default state across layouts',()=>{
  const markup=renderToStaticMarkup(React.createElement('div',null,
    React.createElement(Card,{...props,key:'mobile'}),React.createElement(Card,{...props,key:'desktop'})))
  const controls=[...markup.matchAll(/aria-controls="([^"]+)"/g)].map(match=>match[1])
  assert.equal(new Set(controls).size,2)
  assert.equal([...markup.matchAll(/aria-expanded="false"/g)].length,2)
  for(const id of controls)assert.ok(markup.includes(`id="${id}"`))
  const component=source.slice(source.indexOf('export function ShuttleFullTimetableCard'),source.indexOf('export default function QueryHub'))
  assert.doesNotMatch(component,/command\(|fetch\(|useEffect|matchMedia|innerWidth|setShuttle|[▼▲▾▴]/)
  assert.match(component,/<ChevronDown[^>]*className="weather-strip-chevron"/)
  assert.match(css,/\.weather-strip-toggle\[aria-expanded='true'\] \.weather-strip-chevron\s*\{\s*transform: rotate\(180deg\)/)
  assert.match(css,/@media \(prefers-reduced-motion: reduce\)\s*\{\s*\.weather-strip-reveal,\s*\.weather-strip-chevron\s*\{\s*transition: none/)
})
