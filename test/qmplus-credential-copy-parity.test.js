import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync,readdirSync,existsSync} from 'node:fs'

const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8')
const android=read('native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/QmplusCredentialSettingsEditor.kt')
const apple=read('native/apple/Sources/Shared/QMplusCredentialSettingsEditor.swift')
const androidSettings=read('native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/SettingsPage.kt')
const appleSettings=read('native/apple/Sources/Shared/SettingsView.swift')
const body=android.slice(android.indexOf('    init {'),android.indexOf('        val watcher'))
const shortKeys=['允许官方登录页自动填写','安全保存 QMplus 登录资料','删除已保存的 QMplus 登录资料']
const independent='QMplus 使用独立的官方网页登录，与北邮教务账号无关。'
const storage='保存后会在本机安全存储中保留独立 QMplus 登录资料。首次默认开启自动填写，也可在保存前关闭。'

test('Apple and Android use the same already-translated short labels and independent-account note',()=>{
  const catalog=read('native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/NativeUiTextCatalog.kt')
  for(const key of shortKeys) {
    assert.ok(android.includes(`"${key}"`))
    assert.ok(apple.includes(`"${key}"`))
    assert.ok(catalog.includes(`"${key}" to R.string.`))
  }
  assert.ok(androidSettings.includes(`activity.uiText("${independent}")`))
  assert.ok(appleSettings.includes(`model.localized("${independent}")`))
  const directory=new URL('../native/apple/Resources/Localizations/',import.meta.url)
  const localized=readdirSync(directory).filter(n=>n.endsWith('.lproj')&&n!=='zh-Hans.lproj').map(n=>new URL(`${n}/Localizable.strings`,directory)).filter(existsSync)
  assert.ok(localized.length>=12)
  for(const file of localized)for(const key of [...shortKeys,independent])assert.ok(readFileSync(file,'utf8').includes(`"${key}" =`))
})

test('one storage notice and saved state remain while repeated operation paragraphs are removed',()=>{
  for(const source of [android,apple]) {
    assert.equal(source.split(storage).length-1,1)
    assert.equal(source.split('已在本机安全保存 QMplus 登录资料。').length-1,1)
    for(const removed of ['已保存的密码不会回显。仅更新登录资料时需要重新填写。','关闭“启用 QMplus”只暂停连接和同步','已保存的账号和密码用于自动完成官方登录','保存 QMplus 登录信息并在官方页面自动填写（可选）'])assert.ok(!source.includes(removed))
  }
})

test('editor sequence matches iOS and nested Android fields do not double the first ten-point gap',()=>{
  const order=['root.addView(LinearLayout','append(root, detail(', 'append(root, saved)', 'fields.addView(account,', 'append(fields, password)', 'append(fields, identityWarning)', 'append(fields, save); append(fields, remove)']
  for(let i=1;i<order.length;i++)assert.ok(body.indexOf(order[i-1])<body.indexOf(order[i]))
  assert.doesNotMatch(body,/append\(fields, account\)/)
  assert.match(android,/topMargin = activity\.dp\(10\)/)
  assert.match(apple,/VStack\(alignment: \.leading, spacing: 10\)/)
  const keys=[storage,'已在本机安全保存 QMplus 登录资料。','TextField(text("QMplus 微软账号")','SecureField(text("QMplus 微软密码")','保存新的登录信息会清除现有 QMplus 会话与快照，避免复用其他身份。',`Button(text("${shortKeys[1]}"))`,`Button(text("${shortKeys[2]}"))`]
  for(let i=1;i<keys.length;i++)assert.ok(apple.indexOf(keys[i-1])<apple.indexOf(keys[i]))
})

test('identity reset warning is shown only while either existing draft field is nonempty',()=>{
  assert.match(android,/identityWarning\.visibility = if \(account\.text\.toString\(\)\.trim\(\)\.isNotEmpty\(\) \|\| password\.text\.isNotEmpty\(\)\) View\.VISIBLE else View\.GONE/)
  assert.match(apple,/if !draft\.account\.trimmingCharacters\(in: \.whitespacesAndNewlines\)\.isEmpty \|\| !draft\.password\.isEmpty/)
  assert.ok(android.includes('append(fields, identityWarning)'))
  assert.ok(apple.includes('保存新的登录信息会清除现有 QMplus 会话与快照，避免复用其他身份。'))
})

test('both clients suppress only the duplicated saved-success result and keep errors visible',()=>{
  assert.match(android,/val showResult = !status\.isNullOrEmpty\(\) &&\s*!\(repository\.savedLoginStatus\.enabled && status == "已保存 QMplus 登录信息并授权官方网页自动填写"\)/)
  assert.match(android,/resultText\.visibility = if \(showResult\) View\.VISIBLE else View\.GONE/)
  assert.match(apple,/!\(authorization\.isEnabled && authorization\.statusKey == "已保存 QMplus 登录信息并授权官方网页自动填写"\)/)
  assert.ok(android.includes('editor.activity.getString(R.string.qmplus_saved_login_failed)'))
  assert.ok(android.includes('QMplus 自动填写已关闭，但保存的登录信息删除失败，请重试。'))
})

test('native switch sizing, opt-in callbacks, sample guards and secret cleanup remain',()=>{
  assert.match(android,/minimumHeight = activity\.dp\(UiMetrics\.controlHeightDp\)/)
  assert.match(android,/LinearLayout\.LayoutParams\(0, ViewGroup\.LayoutParams\.WRAP_CONTENT, 1f\)/)
  assert.match(android,/if \(!enabled\) disable\(\) else update\(\)/)
  assert.match(android,/secret\.fill\('\\u0000'\); password\.text\.clear\(\); update\(\)/)
  assert.match(android,/if \(!root\.isAttachedToWindow \|\| !optIn\.isChecked\) return/)
  assert.match(apple,/\.fixedSize\(\)\.layoutPriority\(1\)/)
  assert.match(apple,/setContentCompressionResistancePriority\(\.required, for: \.horizontal\)/)
  assert.match(apple,/if enabled \{ draft\.wantsToSave = true \}/)
  assert.match(apple,/else \{ disable\(\); draft\.disableSaving\(\) \}/)
  assert.match(apple,/_ = save\(draft\.account, draft\.password\)/)
  assert.match(apple,/\.disabled\(sampleMode \|\| draft\.account/)
})
