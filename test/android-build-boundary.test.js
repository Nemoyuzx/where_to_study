import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'

const root = new URL('../', import.meta.url)
const packageJson = JSON.parse(readFileSync(new URL('package.json', root), 'utf8'))
const mainActivity = readFileSync(
  new URL(
    'native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/MainActivity.kt',
    root,
  ),
  'utf8',
)
const packageScript = readFileSync(
  new URL('scripts/native-android-package.sh', root),
  'utf8',
)
const legacyIosWorkflow = readFileSync(
  new URL('.github/workflows/build-legacy-tauri-ios.yml', root),
  'utf8',
)

test('native Android is the only Android application build entry point', () => {
  assert.match(mainActivity, /class MainActivity : Activity\(\)/)
  assert.doesNotMatch(mainActivity, /TauriActivity/)

  assert.equal(existsSync(new URL('src-tauri/gen/android', root)), false)
  assert.equal(existsSync(new URL('scripts/android-build-local.sh', root)), false)
  assert.equal(existsSync(new URL('scripts/android-build-signed.sh', root)), false)

  const scripts = packageJson.scripts
  assert.equal(scripts['native:android:build'], './scripts/native-android-build.sh')
  assert.equal(
    scripts['native:android:sign:init'],
    './scripts/native-android-signing-init.sh',
  )
  assert.equal(scripts['native:android:package'], './scripts/native-android-package.sh')
  assert.equal(
    Object.keys(scripts).some((name) => name.startsWith('tauri:android')),
    false,
  )

  assert.match(packageScript, /ANDROID_DIR="\$ROOT_DIR\/native\/android"/)
  assert.match(packageScript, /\$ANDROID_DIR\/keystore\.properties/)
  assert.doesNotMatch(packageScript, /src-tauri\/gen\/android/)
  assert.doesNotMatch(legacyIosWorkflow, /^\s*android:/m)
  assert.doesNotMatch(legacyIosWorkflow, /src-tauri\/gen\/android/)
})
