import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
const read=name=>readFileSync(new URL(`../src-tauri/src/${name}.rs`,import.meta.url),'utf8')
const section=(source,start,end)=>{const first=source.indexOf(start),last=source.indexOf(end,first+start.length);assert.ok(first>=0&&last>first);return source.slice(first,last)}

test('cache metadata holds opaque ownership only and bounded business files use private atomic writes',()=>{
  const cache=read('course_cache_store')
  const owner=section(cache,'struct CloudOwner','struct CloudEnvelope')
  assert.deepEqual([...owner.matchAll(/\b([a-z_]+):\s*(?:u8|String)/g)].map(value=>value[1]),['schema_version','owner_epoch'])
  assert.match(cache,/const LIMIT: usize = 512 \* 1024/)
  assert.match(cache,/from_mode\(0o700\)/);assert.match(cache,/from_mode\(0o600\)/)
  assert.match(cache,/temporary\.persist\(path\)/);assert.match(cache,/file\.sync_all\(\)/)
  assert.doesNotMatch(cache,/CredentialManager|credential_store::load|cookies\(\)|get_cookie|password_hash/)
  const rotate=section(cache,'pub fn rotate_cloud_owner','fn clear_file')
  assert.ok(rotate.indexOf('clear_file(')<rotate.indexOf('CLOUD_OWNER_BLOCKED.store(false'))
  const load=section(cache,'pub fn load_cloud','pub fn save_cloud')
  assert.match(load,/envelope\.account_scope == scope/);assert.match(load,/envelope\.owner_epoch == epoch/)
  assert.match(cache,/normalized_deadline\(&item\.deadline\)/)
  assert.match(cache,/["']<!doctype["']/)
})

test('credential mutation retires memory and durably rotates the business owner before vault commit',()=>{
  const source=read('lib')
  const save=section(source,'fn save_saved_settings_sync','fn clear_account_scoped_caches')
  assert.match(save,/LOCAL_DATA\.update_account_scope_at/)
  assert.ok(save.indexOf('assignments::clear_cache()')<save.indexOf('course_cache_store::rotate_cloud_owner(&app)?'))
  assert.ok(save.indexOf('course_cache_store::rotate_cloud_owner(&app)?')<save.indexOf('settings_store::commit_save'))
  const fetch=section(source,'async fn read_or_fetch_cloud_catalogue','async fn fetch_exams')
  assert.match(fetch,/LOCAL_DATA\s*\.with_current_account/)
  assert.match(fetch,/ensure_credential_revision\(revision\)/)
  assert.match(fetch,/cache_only/);assert.match(fetch,/CourseQueryResult::Directory/)
})

test('course and assignment views share successful and failed native catalogue attempts',()=>{
  const source=read('assignments')
  const fetch=section(source,'pub async fn fetch_catalogue','pub fn credential_revision')
  assert.match(fetch,/ASSIGNMENT_FETCH\.lock\(\)\.await/)
  assert.match(fetch,/return attempt\.result\.clone\(\)/)
  assert.match(fetch,/Duration::from_secs\(120\)/)
  assert.match(fetch,/COURSE_CACHE\.save/);assert.match(fetch,/ASSIGNMENT_CACHE\.save/)
  assert.match(source,/Ok\(\(courses, merge_items\(all_items\)\)\)/)
})

test('QM background uses bounded fixed entry proofs and never presents manual verification automatically',()=>{
  const source=read('qmplus')
  assert.match(source,/const APPROVED_LOGIN_ENTRY/)
  assert.match(source,/"guest" \| "guest_sso" \| "guest_login"/)
  assert.match(source,/"\/", "\/my", "\/my\/"/)
  assert.match(source,/ConnectRequest/)
  const manual=section(source,'fn require_manual','fn require_challenge')
  assert.match(manual,/cancel_autofill\(app\)/)
  assert.match(manual,/window\.hide\(\)/)
  assert.doesNotMatch(manual,/show_login\(|window\.show\(/)
  const challenge=section(source,'fn require_challenge','fn suspend_autofill')
  assert.match(challenge,/challenge_presented\.store\(true/)
  assert.match(challenge,/!app_is_backgrounded\(app\)/)
  assert.match(challenge,/show_login\(window\)/)
  assert.match(source,/Duration::from_secs\(130\)/)
  const cache=read('course_cache_store')
  assert.match(cache,/crate::qmplus_profile::current\(app, Some\(profile\)\)/)
  assert.match(cache,/envelope\.profile_id != profile/)
})
