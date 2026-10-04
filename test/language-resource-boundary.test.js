import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const rust = readFileSync(new URL('../src-tauri/src/lib.rs', import.meta.url), 'utf8')

test('tray locale, date and local edits cannot implicitly fetch an academic schedule', () => {
  const loader = rust.slice(rust.indexOf('async fn load_today_course_content('), rust.indexOf('fn local_tray_course_content('))
  const local = loader.slice(loader.indexOf('if local_only {'), loader.indexOf('let (request, account_scope'))
  assert.match(local, /return local_tray_course_content\(/)
  assert.match(local, /load_current_schedule\(&app\)/)
  assert.doesNotMatch(local, /fetch_schedule|apply_saved_credentials|await|load_saved_credentials/)
  const language = rust.slice(rust.indexOf('fn set_interface_language('), rust.indexOf('fn show_main_window('))
  assert.match(language, /DESKTOP_INTERFACE_LANGUAGE\.swap/)
  assert.match(language, /refresh_tray_courses\(app, true\)/)
  const explicit = rust.slice(rust.indexOf('fn setup_tray('), rust.indexOf('static HIDE_TO_TRAY_NOTIFIED'))
  assert.match(explicit, /"refresh_today" => refresh_tray_courses\(app\.clone\(\), false\)/)
  assert.match(explicit, /refresh_tray_courses\(app\.app_handle\(\)\.clone\(\), true\)/)
})

test('successful schedule publication updates the tray locally and older work cannot replace it', () => {
  const fetch = rust.slice(rust.indexOf('async fn fetch_schedule('), rust.indexOf('struct CourseEditRequest'))
  assert.match(fetch, /refresh_tray_courses\(app\.clone\(\), true\)/)
  const refresh = rust.slice(rust.indexOf('fn refresh_tray_courses('), rust.indexOf('fn setup_tray('))
  assert.match(refresh, /TRAY_REFRESH_REVISION\.fetch_add/)
  assert.match(refresh, /if TRAY_REFRESH_REVISION\.load\(Ordering::SeqCst\) != refresh_revision \{\s*return Ok\(\(\)\)/)
  const loader = rust.slice(rust.indexOf('async fn load_today_course_content('), rust.indexOf('fn local_tray_course_content('))
  // A remote result saved after a language task must get a new local-only
  // publication, rather than disappear behind the older task's revision fence.
  assert.match(loader, /\}\) \{\s*Ok\(effective\) => \{[\s\S]*?if TRAY_REFRESH_REVISION\.load\(Ordering::SeqCst\) != requested_refresh_revision \{\s*refresh_tray_courses\(app\.clone\(\), true\);\s*\}\s*effective/)
})
