import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
const read=name=>readFileSync(new URL(`../src/${name}`,import.meta.url),'utf8')

test('disclosure keeps actual children and cancels/reverses only presentation work',()=>{
  const source=read('AnimatedDisclosure.jsx')
  assert.match(source,/aria-hidden=\{!expanded\} inert=\{!expanded\}/)
  assert.match(source,/node\.getBoundingClientRect\(\)\.height/)
  assert.match(source,/animation\.finished\.then\(\(\)=>\{if\(work\.current\?\.animation===animation\)finish\(\)/)
  assert.match(source,/resize\?\.disconnect\(\);stop\(\);node\.style\.height/)
  assert.match(source,/prefers-reduced-motion: reduce/)
  assert.doesNotMatch(source,/fetch\(|command\(|invoke\(|localStorage|password|account/)
})

test('completion uses an original drawn ring/check and dwells only after target readiness',()=>{
  const mark=read('LanguageCompletionMark.jsx'),css=read('App.css'),controller=read('language-transition.js')
  assert.match(mark,/cx="32" cy="32" r="24"/)
  assert.match(mark,/d="M18 33 L27 41 L45 23"/)
  assert.match(css,/language-ring-draw 360ms/)
  assert.match(css,/language-check-draw 380ms 240ms/)
  assert.match(controller,/this\.after\(800, revision/)
  assert.match(controller,/this\.after\(5000, revision, \(\) => this\.finish\(false\)\)/)
  assert.doesNotMatch(mark,/Apple|SF.?Symbol|http|image|img/)
})
