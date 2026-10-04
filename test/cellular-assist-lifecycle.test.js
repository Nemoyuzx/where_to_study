import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { transformSync } from 'esbuild'

const sourceRoot = fileURLToPath(new URL('../native/harmony/entry/src/main/ets/', import.meta.url))

// Execute the production transport code with in-memory NetworkKit responses.
// No request is sent, no preference is written, and all credentials are fixtures.
function harness({ enabled = false, wifi = true, respond }) {
  const calls = []
  const clients = []
  const http = {
    RequestMethod: { GET: 'GET', HEAD: 'HEAD', POST: 'POST' },
    AddressFamily: { DEFAULT: 0, ONLY_V4: 1 },
    HttpDataType: { ARRAY_BUFFER: 0 },
    createHttp() {
      const client = { destroyCount: 0 }
      clients.push(client)
      return {
        async request(url, options) {
          const call = {
            url, method: options.method ?? 'GET',
            preference: options.pathPreference ?? 'auto',
            family: options.addressFamily,
            hasBody: Boolean(options.extraData),
          }
          calls.push(call)
          return respond(call, calls.length)
        },
        destroy() { client.destroyCount++ },
      }
    },
  }
  class AuthenticationExpiredError extends Error {}
  const mocks = {
    '@kit.NetworkKit': {
      http,
      connection: {
        NetBearType: { BEARER_WIFI: 1 },
        getDefaultNetSync: () => ({}),
        getNetCapabilitiesSync: () => ({ bearerTypes: wifi ? [1] : [] }),
      },
    },
    '@kit.ArkTS': {
      util: { TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) } },
    },
    '@kit.PerformanceAnalysisKit': { hilog: { error() {} } },
  }
  const modules = new Map()
  function load(file) {
    if (modules.has(file)) return modules.get(file)
    const module = { exports: {} }
    modules.set(file, module.exports)
    const source = readFileSync(file, 'utf8')
    const output = transformSync(source, { loader: 'ts', format: 'cjs', target: 'es2022' }).code
    const requireMock = name => {
      if (mocks[name]) return mocks[name]
      // Session issuance is outside these transport tests. Exercise login() and
      // classrooms() directly, without loading an account or persistence layer.
      if (name.endsWith('/AuthenticatedSession')) {
        return { AuthenticatedSession: class {}, AuthenticationExpiredError, SessionLease: class {} }
      }
      if (name.endsWith('/Utf8')) return { Utf8: { bytes: text => new TextEncoder().encode(text) } }
      if (name.startsWith('.')) return load(resolve(dirname(file), `${name}.ets`))
      throw new Error(`Unexpected test dependency: ${name}`)
    }
    new Function('require', 'module', 'exports', output)(requireMock, module, module.exports)
    modules.set(file, module.exports)
    return module.exports
  }
  const cellular = load(resolve(sourceRoot, 'net/CellularAssist.ets'))
  const transport = load(resolve(sourceRoot, 'net/HttpUtil.ets'))
  const { SJDAPIClient } = load(resolve(sourceRoot, 'net/SjdApi.ets'))
  cellular.CellularAssist.enabled = enabled
  return {
    ...cellular, ...transport, SJDAPIClient, http, calls, clients, AuthenticationExpiredError,
    assertDestroyed() {
      assert.ok(clients.length > 0)
      assert.ok(clients.every(client => client.destroyCount === 1), 'Each original and fallback client must be destroyed once')
    },
  }
}

function response(responseCode = 200, text = '{}', header = {}) {
  return { responseCode, result: new TextEncoder().encode(text).buffer, header }
}
function networkError(code) { return Object.assign(new Error('Synthetic transport error'), { code }) }
const host = 'jwglweixin.bupt.edu.cn'
const firstURL = `https://${host}/first`

test('Harmony policy defaults off and excludes mutation, TLS, cancellation and consumed retries', () => {
  const h = harness({ respond: () => { throw new Error('Policy tests must not create a request') } })
  assert.equal(h.CellularAssist.enabled, false)
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE']) {
    assert.equal(h.CellularAssist.canRetry(method, true, true, 2300028, false), false)
  }
  for (const code of [401, 403, 500, 2300060, 2300058, 0]) {
    assert.equal(h.CellularAssist.canRetry('GET', true, true, code, false), false)
  }
  assert.equal(h.CellularAssist.canRetry('GET', false, true, 2300007, false), false)
  assert.equal(h.CellularAssist.canRetry('GET', true, false, 2300007, false), false)
  assert.equal(h.CellularAssist.canRetry('GET', true, true, 2300007, true), false)
  assert.equal(h.CellularAssist.canRetry('HEAD', true, true, 2300028, false), true)
  assert.equal(h.clients.length, 0)
})

test('Successful cellular fallback consumes the redirect chain budget and destroys both clients', async () => {
  const h = harness({ enabled: true, respond(call) {
    if (call.url === firstURL && call.preference === 'auto') throw networkError(2300007)
    return call.url === firstURL ? response(302, '', { Location: '/second' }) : response()
  } })
  const spec = new h.HttpRequestSpec()
  await h.HttpUtil.perform(firstURL, spec, host)
  assert.equal(spec.fallbackConsumed, true)
  assert.deepEqual(h.calls.map(call => call.preference), ['auto', 'primaryCellular', 'auto'])
  h.assertDestroyed()
})

test('A failed later redirect cannot start a second cellular fallback or compound it with IPv4', async () => {
  const h = harness({ enabled: true, respond(call) {
    if (call.preference === 'auto') throw networkError(2300007)
    return response(302, '', { Location: '/second' })
  } })
  await assert.rejects(new h.SJDAPIClient().classrooms('synthetic-token', '1'), error => error instanceof h.HttpTransportError)
  assert.equal(h.calls.filter(call => call.preference === 'primaryCellular').length, 1)
  assert.equal(h.calls.some(call => call.family === h.http.AddressFamily.ONLY_V4), false)
  assert.equal(h.calls.length, 3)
  h.assertDestroyed()
})

test('Credential POST timeout never retries on cellular or IPv4, even with the switch on', async () => {
  for (const enabled of [false, true]) {
    const h = harness({ enabled, respond() { throw networkError(2300028) } })
    await assert.rejects(new h.SJDAPIClient().login({ account: 'fixture-account', password: 'fixture-password' }),
      error => error instanceof Error && error.message.includes('2300028'))
    assert.deepEqual(h.calls.map(call => [call.method, call.family, call.hasBody, call.preference]), [['POST', 0, true, 'auto']])
    h.assertDestroyed()
  }
})

test('Read-only GET retains one IPv4 fallback when cellular has not been attempted', async () => {
  const h = harness({ respond(call) {
    if (call.family === h.http.AddressFamily.DEFAULT) throw networkError(2300028)
    return response(200, '{"code":"1","data":[]}')
  } })
  await new h.SJDAPIClient().classrooms('synthetic-token', '1')
  assert.deepEqual(h.calls.map(call => [call.method, call.family, call.hasBody, call.preference]),
    [['GET', 0, false, 'auto'], ['GET', 1, false, 'auto']])
  h.assertDestroyed()
})

test('Synthetic cancellation and TLS rejection never start a fallback and always destroy the owner', async () => {
  for (const code of [0, 2300060]) {
    const h = harness({ enabled: true, respond() { throw networkError(code) } })
    await assert.rejects(new h.SJDAPIClient().classrooms('synthetic-token', '1'),
      error => error instanceof h.HttpTransportError && error.code === code && !error.cellularAttempted)
    assert.equal(h.calls.length, 1)
    h.assertDestroyed()
  }
})

test('Fallback cancellation or timeout releases both clients and never starts an IPv4 retry', async () => {
  for (const code of [0, 2300028]) {
    const h = harness({ enabled: true, respond(call) {
      throw networkError(call.preference === 'auto' ? 2300007 : code)
    } })
    await assert.rejects(new h.SJDAPIClient().classrooms('synthetic-token', '1'),
      error => error instanceof h.HttpTransportError && error.code === code && error.cellularAttempted)
    assert.deepEqual(h.calls.map(call => call.preference), ['auto', 'primaryCellular'])
    h.assertDestroyed()
  }
})

test('HTTP authentication failures and foreign redirects are not treated as connection failures', async () => {
  const unauthorized = harness({ enabled: true, respond: () => response(401) })
  await assert.rejects(new unauthorized.SJDAPIClient().classrooms('synthetic-token', '1'),
    error => error instanceof unauthorized.AuthenticationExpiredError)
  assert.equal(unauthorized.calls.length, 1)
  unauthorized.assertDestroyed()
  const redirect = harness({ enabled: true, respond: () => response(302, '', { Location: 'https://foreign.invalid/second' }) })
  await assert.rejects(redirect.HttpUtil.perform(firstURL, new redirect.HttpRequestSpec(), host))
  assert.equal(redirect.calls.length, 1)
  redirect.assertDestroyed()
})

test('Disabling while the default request is pending prevents fallback and restores reused options', async () => {
  const disabled = harness({ enabled: true, respond() {
    disabled.CellularAssist.enabled = false
    throw networkError(2300007)
  } })
  await assert.rejects(disabled.HttpUtil.perform(firstURL, new disabled.HttpRequestSpec(), host))
  assert.equal(disabled.calls.length, 1)
  disabled.assertDestroyed()

  const reused = harness({ enabled: true, respond(call) {
    if (call.preference === 'auto') throw networkError(2300007)
    return response()
  } })
  const options = { method: 'GET', pathPreference: 'auto' }
  const original = reused.http.createHttp()
  try { await reused.CellularAssist.request(original, firstURL, options) }
  finally { original.destroy() }
  assert.equal(options.pathPreference, 'auto', 'A finished fallback must not keep routing reused caller options over cellular')
  reused.assertDestroyed()
})
