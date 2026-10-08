import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'

const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8').replace(/\r\n/g,'\n')
const source=read('src-tauri/src/qmplus.rs')
const start=source.indexOf('#[cfg(target_os = "linux")]\nfn prepare_hidden_qmplus_layout')
const end=source.indexOf('#[cfg(not(target_os = "linux"))]',start)
const helper=source.slice(start,end)

test('hidden Linux layout uses synchronous native allocation without showing or focusing a top-level',()=>{
  assert.ok(start>=0&&end>start)
  assert.match(helper,/gtk::is_initialized_main_thread\(\)/)
  assert.match(helper,/if window\.is_visible\(\)[\s\S]*?return Ok\(\(\)\)/)
  assert.match(helper,/\.inner_size\(\)[\s\S]*?\.to_logical::<i32>\(scale\)/)
  assert.match(helper,/!scale\.is_finite\(\) \|\| scale <= 0\.0/)
  assert.match(helper,/size\.width > 1[\s\S]*?1000/)
  assert.match(helper,/size\.height > 1[\s\S]*?760/)
  assert.match(helper,/window\.default_vbox\(\)/)
  assert.match(helper,/child\.type_\(\)\.name\(\) == "WebKitWebView"/)
  assert.match(helper,/if views\.next\(\)\.is_some\(\)/)
  assert.match(helper,/container\.size_allocate\(&allocation\);\s*view\.size_allocate\(&allocation\)/)
  assert.doesNotMatch(helper,/\.show\(|\.show_all\(|\.present\(|\.set_focus\(|\.grab_focus\(|\.navigate\(|\.eval\(/)
  assert.doesNotMatch(helper,/\.with_webview\(|spawn|timeout|sleep|credential|cookie|load_named|save_named/)
})

test('initial build and hidden view reuse allocate before navigation or authentication scripts',()=>{
  const connect=source.slice(source.indexOf('fn connect_qmplus_on_main('),source.indexOf('fn arm_quiet_deadline('))
  assert.match(connect,/\.visible\(!quiet\)\s*\.inner_size\(1000\.0, 760\.0\)/)
  assert.match(connect,/if prepare_hidden_qmplus_layout\(&window\)\.is_err\(\) \{\s*require_manual\(&app, &window, "LAYOUT_UNAVAILABLE"\);\s*return Err\("QMplus 页面不可用。"\.into\(\)\);\s*\}\s*window\s*\.navigate\(/)
  assert.match(connect,/\.build\(\)[\s\S]*?if prepare_hidden_qmplus_layout\(&window\)\.is_err\(\)/)
  const finished=connect.slice(connect.indexOf('if p.event() == tauri::webview::PageLoadEvent::Finished'))
  const allocation=finished.indexOf('prepare_hidden_qmplus_layout(&window)')
  assert.ok(allocation>=0&&allocation<finished.indexOf('if official_qm_page(&current)'))
  assert.ok(allocation<finished.indexOf('const install={AUTH_SCRIPT}'))
  assert.match(finished,/prepare_hidden_qmplus_layout\(&window\)\.is_err\(\)[\s\S]*?"LAYOUT_UNAVAILABLE"\);\s*return;/)
})

test('allocation stays Linux-only and reuses the already locked GTK package',()=>{
  assert.match(source.slice(end),/^#\[cfg\(not\(target_os = "linux"\)\)\]\s*fn prepare_hidden_qmplus_layout\(_window:[\s\S]*?Ok\(\(\)\)/)
  const manifest=read('src-tauri/Cargo.toml')
  assert.match(manifest,/\[target\.'cfg\(target_os = "linux"\)'\.dependencies\]\s*gtk = "=0\.18\.2"/)
  assert.match(read('src-tauri/Cargo.lock'),/name = "gtk"\nversion = "0\.18\.2"/)
  assert.equal((manifest.match(/^gtk = /gm)||[]).length,1)
})

test('native allocation leaves strict form geometry, identity budgets and bounded settling intact',()=>{
  const auth=read('contracts/qmplus/qmplus-auth.js')
  assert.match(auth,/visible\(submit, 60, 20, true\)/)
  assert.match(auth,/document\.elementFromPoint\(rect\.left \+ rect\.width \/ 2, rect\.top \+ rect\.height \/ 2\)/)
  assert.match(auth,/visible\(field, 80, 20, true\)/)
  assert.match(source,/settling\+\+<16/)
  assert.match(source,/require_current_profile\(&app, &state\)/)
  assert.match(source,/credential_revision != crate::qmplus_login::revision\(\)/)
  assert.match(source,/auth\.ledger\.claim\(/)
})
