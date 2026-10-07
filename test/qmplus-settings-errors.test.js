import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import {uiText} from '../src/ui-text.js'
import {qmplusSettingsErrorKey, qmplusSettingsErrorText} from '../src/qmplus-settings-errors.js'

const restart = 'QMplus 网页会话需要清理，请重新启动应用。'
const generic = 'QMplus 安全设置未能保存，请重试。'
const component = readFileSync(new URL('../src/QmplusLoginSettings.jsx', import.meta.url), 'utf8')

function connectFixture(options = {}, operation = async () => {}) {
  const start = component.indexOf('  async function connect(')
  assert.notEqual(start, -1)
  const open = component.indexOf('{', start)
  let depth = 1, end = open + 1
  for (; depth > 0 && end < component.length; end++) {
    if (component[end] === '{') depth++
    if (component[end] === '}') depth--
  }
  assert.equal(depth, 0)
  const owner = {current:7}, errors = [], calls = [], events = []
  const setError = value => { errors.push(value); events.push(['error', value]) }
  const command = (...args) => { calls.push(args); events.push(['command', ...args]); return operation(...args) }
  const flags = {native:true, busy:false, enabled:true, featureBusy:false, ...options}
  const connect = new Function('native', 'busy', 'enabled', 'featureBusy', 'owner', 'setError', 'command', 'qmplusSettingsErrorKey', `${component.slice(start, end)}; return connect`)(
    flags.native, flags.busy, flags.enabled, flags.featureBusy, owner, setError, command, qmplusSettingsErrorKey,
  )
  return {connect, owner, errors, calls, events}
}

function deferred() {
  let resolve, reject
  const promise = new Promise((yes, no) => { resolve = yes; reject = no })
  return {promise, resolve, reject}
}

test('QMplus restart barrier preserves existing Chinese and English catalog messages', () => {
  assert.equal(qmplusSettingsErrorKey(restart), restart)
  assert.equal(qmplusSettingsErrorKey(new Error(restart)), restart)
  assert.equal(qmplusSettingsErrorText('zh-Hans', restart), restart)
  assert.equal(qmplusSettingsErrorText('en', restart), 'The QMplus web session needs to be cleared. Please restart the app.')
  assert.equal(qmplusSettingsErrorText('en', restart), uiText('en', restart))
})

test('only exact prerequisite and secure-storage errors select existing static catalog keys', () => {
  for (const [error, key, english] of [
    ['QMplus 尚未启用。', '启用 QMplus', 'Enable QMplus'],
    ['请先保存 QMplus 账号和密码。', '安全保存 QMplus 登录资料', 'Save QMplus Login Securely'],
    ['无法读取 QMplus 安全存储。', '无法读取 QMplus 安全存储。', 'Unable to read QMplus secure storage.'],
  ]) {
    assert.equal(qmplusSettingsErrorKey(error), key)
    assert.equal(qmplusSettingsErrorText('zh-Hans', error), key)
    assert.equal(qmplusSettingsErrorText('en', error), english)
  }
})

test('unknown errors and sensitive suffixes never become displayed or translated content', () => {
  const sensitive = 'student@example.invalid password=SYNTHETIC_PRIVATE https://example.invalid/?token=SYNTHETIC_TOKEN'
  for (const failure of [sensitive, new Error(sensitive), {message:sensitive}, null, undefined, 17,
    `${restart} ${sensitive}`, `${sensitive}${restart}`, ` ${restart}`, `${restart}\n`,
    {toString() { throw Error('must not coerce unknown failures') }},
    {get message() { throw Error('must not invoke error accessors') }},
    new Proxy({}, {getOwnPropertyDescriptor() { throw Error('must not leak descriptor errors') }}),
    Object.create({get message() { throw Error('must not invoke inherited error accessors') }}),
  ]) {
    assert.equal(qmplusSettingsErrorKey(failure), generic)
    assert.equal(qmplusSettingsErrorText('zh-Hans', failure), generic)
    assert.equal(qmplusSettingsErrorText('en', failure), 'Unable to save QMplus security settings. Please retry.')
  }
})

test('actual Connect and manual continuation preserve command payloads and display the restart reason', async () => {
  for (const manual of [false, true]) {
    const h = connectFixture({}, async () => { throw restart })
    if (manual) await h.connect(true)
    else await h.connect()
    const request = manual ? {manual:true} : undefined
    assert.deepEqual(h.calls, [['connect_qmplus', request]])
    assert.deepEqual(h.events, [['error', ''], ['command', 'connect_qmplus', request], ['error', restart]])
    assert.equal(uiText('en', h.errors.at(-1)), 'The QMplus web session needs to be cleared. Please restart the app.')
  }
})

test('actual Connect retry clears the previous error before invoking the next command', async () => {
  const retry = deferred()
  let attempts = 0
  const h = connectFixture({}, () => ++attempts === 1 ? Promise.reject(restart) : retry.promise)
  await h.connect()
  assert.equal(h.errors.at(-1), restart)
  const next = h.connect()
  assert.deepEqual(h.events.slice(-2), [['error', ''], ['command', 'connect_qmplus', undefined]])
  assert.equal(h.errors.at(-1), '')
  retry.resolve()
  await next
  assert.deepEqual(h.errors, ['', restart, ''])
})

test('actual Connect ignores late failures after owner replacement or component cleanup', async () => {
  const cleanupSource = component.match(/return\(\)=>\{owner\.current\+\+;release\?\.\(\)\}/)?.[0]
  assert.ok(cleanupSource, 'the real component cleanup must revoke the old owner')
  for (const unmount of [false, true]) {
    const pending = deferred()
    const h = connectFixture({}, () => pending.promise)
    const work = h.connect(true)
    if (unmount) {
      let released = 0
      const cleanup = new Function('owner', 'release', cleanupSource.replace('return', 'return '))(h.owner, () => { released++ })
      cleanup()
      assert.equal(released, 1)
    } else h.owner.current++
    pending.reject(restart)
    await work
    assert.deepEqual(h.errors, [''])
    assert.deepEqual(h.calls, [['connect_qmplus', {manual:true}]])
  }
})

test('actual Connect guards prevent both command invocation and error changes while unavailable', async () => {
  for (const flags of [{native:false}, {busy:true}, {enabled:false}, {featureBusy:true}]) {
    const h = connectFixture(flags, async () => { throw Error('must not invoke a blocked command') })
    await h.connect()
    await h.connect(true)
    assert.deepEqual(h.calls, [])
    assert.deepEqual(h.errors, [])
  }
})

test('actual Connect exposes only the generic key for an unknown sensitive failure', async () => {
  const h = connectFixture({}, async () => { throw new Error('student@example.invalid https://example.invalid/?token=SYNTHETIC_PRIVATE') })
  await h.connect()
  assert.deepEqual(h.errors, ['', generic])
})
