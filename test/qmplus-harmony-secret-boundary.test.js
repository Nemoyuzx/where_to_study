import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const read = path => readFileSync(new URL(`../native/harmony/entry/src/main/ets/${path}`, import.meta.url), 'utf8')
const store = read('store/QMPlusSavedLoginStore.ets')
const session = read('view/QMPlusSession.ets')
const settings = read('view/SettingsView.ets')
const web = read('view/QMPlusConnectionView.ets')

test('Harmony QM saved login is a separate ASSET secret gated by a matching non-secret authorization record', () => {
  assert.match(store, /qmplus-microsoft-login-v1/)
  assert.match(store, /asset\.Tag\.SECRET/)
  assert.match(store, /asset\.Tag\.ACCESSIBILITY, asset\.Accessibility\.DEVICE_FIRST_UNLOCKED/)
  assert.match(store, /class QMPlusSavedLoginPayload \{[\s\S]*?readonly record_id: string/)
  assert.match(store, /this\.record_id = recordID/)
  assert.match(session, /qmplusAutoFillAuthorizedRecordID/)
  assert.match(session, /this\.recordIDFactory = recordIDFactory \?\? \(\(\): string => newQMPlusRecordID\(\)\)/)
  assert.match(session, /login !== null && authorization === login\.recordID/)
  assert.match(session, /this\.autoFillEnabled = false;[\s\S]*?this\.enqueueLoginMutation/)
  assert.match(session, /await this\.savedLoginStore\.clear\(\)/)
  assert.doesNotMatch(store, /private static readonly alias: string = 'bupt-jwgl'|effectiveCloudPassword|console\./)
})

test('Harmony review demo is isolated and only a verified official owner can request a login secret', () => {
  assert.match(settings, /if \(!this\.model\.isSampleMode\(\)\) \{ void this\.qmPlusSession\.restoreSavedLoginStatus\(\); \}/)
  assert.match(settings, /onQMPlusRuntimeScopeChanged\(\): void \{[\s\S]*?this\.qmPlusPasswordDraft = ''/)
  assert.match(settings, /\.id\('settings\.qmplus\.logout'\)\s*\.enabled\(!this\.model\.isSampleMode\(\)\)/)
  assert.match(web, /if \(!this\.model\.isSampleMode\(\)\) \{ void this\.session\.restoreSavedLoginStatus\(\); \}/)
  assert.match(web, /sameAuthPage\(owner: number, page: number, url: string, nonce: string\): boolean/)
  assert.match(web, /QMPlusAuthNavigationPolicy\.isKnownMicrosoftPage\(url\)/)
  assert.match(web, /installed !== 'AUTH_INSTALLED'/)
  assert.match(web, /this\.session\.authorizedPasswordFor\(account, authorization\)/)
  assert.match(web, /this\.session\.authorizedAccountHint\(authorization\)/)
  assert.match(web, /this\.session\.captureLoginAuthorization\(loginOwner\)/)
  assert.match(web, /this\.session\.isAuthorizationCurrent\(this\.authAuthorization\)/)
  assert.match(session, /authorization\.settingsRevision === this\.loginSettingsRevision/)
  assert.match(session, /login\.recordID !== authorization\.recordID \|\| consent !== authorization\.recordID/)
  assert.match(session, /owner\.sessionID === this\.sessionID/)
  assert.match(web, /if \(!this\.sameAuthPage\(owner, page, url, nonce\)\) \{ return; \}/)
  assert.doesNotMatch(web, /registerJavaScriptProxy|document\.cookie|console\.(?:log|info)/)
  assert.doesNotMatch(web, /enableAutoFill\(false\)/)
})

test('Harmony QM auth consumer owns one official document and clears every old async owner', () => {
  assert.match(web, /qmLoginPage: string = 'https:\/\/qmplus\.qmul\.ac\.uk\/login\/index\.php'/)
  assert.match(web, /qmSAMLStart: string = 'https:\/\/qmplus\.qmul\.ac\.uk\/auth\/saml2\/login\.php'/)
  assert.match(web, /this\.authSAMLStarted = true;[\s\S]*?this\.controller\.loadUrl\(QMPlusAuthNavigationPolicy\.qmSAMLStart\)/)
  assert.match(web, /url !== this\.authURL/)
  assert.match(web, /page === this\.pageRevision && url === this\.safeCurrentURL\(\)/)
  assert.match(web, /owner === this\.authPresentationRevision &&[\s\S]*?page === this\.pageRevision/)
  assert.match(web, /this\.invalidateAuth\(\);[\s\S]*?this\.mounted = false/)
  assert.match(web, /this\.cancelAuthDelay\(\)/)
  assert.match(web, /installed !== 'AUTH_INSTALLED'/)
  assert.match(web, /this\.authLedger\.claimUsername\(nonce\)[\s\S]*?this\.fillAuth\(owner, page, url, nonce, account, null\)/)
  assert.match(web, /this\.authLedger\.claimPassword\(nonce, state\.accountMatch\)[\s\S]*?this\.fillAuth\(owner, page, url, nonce, account, password\)/)
  assert.match(web, /this\.authLedger\.recordUsernameSubmission\(nonce, code\)/)
  assert.match(web, /this\.authLedger\.usernameSubmitted\(nonce\)/)
  assert.match(web, /location\.href!==/)
  assert.doesNotMatch(web, /registerJavaScriptProxy|document\.cookie|console\.(?:log|info)/)
})

test('Harmony retires same-document ACKs on navigation while preserving presentation claims and manual stop', () => {
  const invalidate = web.match(/private invalidateAuth\(\): void \{([\s\S]*?)\n  \}/)?.[1]
  assert.ok(invalidate)
  assert.match(invalidate, /this\.authLedger\.beginDocument\(\)/)
  assert.doesNotMatch(invalidate, /this\.authLedger\.begin\(\)|usernameClaimed = false|passwordClaimed = false/)
  const newDocument = web.match(/beginDocument\(\): void \{([\s\S]*?)\n  \}/)?.[1]
  assert.ok(newDocument)
  assert.match(newDocument, /submittedUsernameDocument = ''/)
  assert.doesNotMatch(newDocument, /active = true|usernameClaimed = false|passwordClaimed = false/)
  assert.match(web, /this\.authLedger\.stop\(\);[\s\S]*?this\.invalidateAuth\(\);[\s\S]*?this\.session\.presentLogin\(\)/)
  assert.match(web, /afterPassword = true;[\s\S]*?await this\.waitForAuthStep\(\);[\s\S]*?continue/)
})
