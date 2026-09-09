import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = ['../src-tauri/src/desktop_notifications.rs',
  '../src-tauri/src/desktop_notifications/linux.rs',
  '../src-tauri/src/desktop_notifications/macos.rs',
].map(path => readFileSync(new URL(path, import.meta.url), 'utf8')).join('\n')
const app = readFileSync(new URL('../src-tauri/src/lib.rs', import.meta.url), 'utf8')
const manifest = readFileSync(new URL('../src-tauri/Cargo.toml', import.meta.url), 'utf8')

test('desktop notification delivery has no detached plugin task or ignored delivery result', () => {
  assert.doesNotMatch(manifest, /^tauri-plugin-notification\s*=/m)
  assert.doesNotMatch(source, /async_runtime::spawn|std::thread::spawn/)
  assert.match(app, /deliver_with_current_preferences\(/)
  assert.match(app, /desktop_notifications::show\(/)
  assert.match(source, /notifier\.Show\(&toast\)/)
  assert.match(source, /"Notify"/)
  assert.match(source, /recv_timeout/)
})

test('desktop platform adapters retain explicit removal and safe content handling', () => {
  assert.match(source, /RemoveGroupedTagWithId/)
  assert.match(source, /"CloseNotification"/)
  assert.match(source, /removePendingNotificationRequestsWithIdentifiers/)
  assert.match(source, /removeDeliveredNotificationsWithIdentifiers/)
  assert.match(source, /escaped_notification_text\(body\)/)
  assert.match(source, /NotificationSetting::Enabled/)
  assert.match(source, /RoInitialize\(RO_INIT_MULTITHREADED\)/)
})
