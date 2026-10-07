import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyzeRustTestCredentials, isSafeTrackedRustPath } from '../scripts/check-test-credentials.mjs';
import { withoutLocalGitEnvironment } from '../scripts/security-preflight.mjs';

// Git hooks export repository-local selectors. Never let them select a parent
// repository while creating or inspecting this test's disposable repositories.
const localGitNames = execFileSync('git', ['rev-parse', '--local-env-vars'], { encoding: 'utf8' }).trim().split(/\r?\n/);
const fixtureEnvironment = withoutLocalGitEnvironment(process.env, localGitNames);

const scan = code => analyzeRustTestCredentials(`#[cfg(test)] mod tests {\n${code}\n}`);
const helper = `fn temporary_password(label: &str) -> String {
 static SEED: std::sync::OnceLock<String> = std::sync::OnceLock::new();
 let seed = SEED.get_or_init(|| {
 let mut bytes = [0_u8; 16];
 getrandom::fill(&mut bytes).expect("synthetic RNG failure");
 bytes.iter().map(|byte| format!("{byte:02x}")).collect()
 });
 format!("synthetic-{label}-{seed}")
}`;

test('only test code, not comments or raw JSON, is inspected', () => {
  assert.deepEqual(analyzeRustTestCredentials('fn prod() { let password = "fixed"; }'), []);
  assert.deepEqual(scan('// let password = "fixed";\n/* outer /* let password = "fixed"; */ */\nlet json = r###"{"password":"fixed"}"###;'), []);
  assert.equal(scan('let character = \'"\'; let password = "fixed";').length, 1);
  assert.equal(analyzeRustTestCredentials('fn test_case() { let password = "fixed"; }', 'crate/tests/integration.rs').length, 1);
  assert.deepEqual(analyzeRustTestCredentials('fn test_case() { let password = "fixed"; }', 'crate/src/contest.rs'), []);
});
test('known credential slots reject nested and multiline fixed expressions without exposing values', () => {
  const findings = scan('let password: String =\n Some(String::from(("synthetic-fixed"))).into();\nlet cloudPassword = "other".to_owned();\nRequest { secret: String::from("fixed"), }');
  assert.equal(findings.length, 3);
  assert.equal(findings[0].line, 2);
  assert.ok(findings.every(item => item.rule === 'TEST_CREDENTIAL_LITERAL'));
  assert.ok(!JSON.stringify(findings).includes('synthetic-fixed'));
  assert.equal(scan('let password = r#"fixed"#;').length, 1);
  assert.equal(scan('Credentials { password: "fixed" }').length, 1);
  assert.equal(scan('let password = "}";').length, 1);
  assert.equal(analyzeRustTestCredentials('#[cfg(test)] const PASSWORD: &str = "fixed";').length, 1);
  assert.equal(scan('let cloudpassword = Some("fixed");').length, 1);
});
test('CLI scans tracked files only, rejects symlinks, and never echoes credentials', () => {
  const root = mkdtempSync(path.join(tmpdir(), 'wts-fixture-policy-'));
  const script = fileURLToPath(new URL('../scripts/check-test-credentials.mjs', import.meta.url));
  const run = () => spawnSync(process.execPath, [script, '--root', root], { encoding: 'utf8', env: fixtureEnvironment });
  try {
    execFileSync('git', ['init', '-q', root], { env: fixtureEnvironment });
    writeFileSync(path.join(root, 'safe.rs'), '#[cfg(test)] mod tests { let password = ""; }');
    writeFileSync(path.join(root, 'untracked.rs'), '#[cfg(test)] mod tests { let password = "synthetic-not-output"; }');
    execFileSync('git', ['add', 'safe.rs'], { cwd: root, env: fixtureEnvironment });
    assert.equal(run().status, 0);
    execFileSync('git', ['add', 'untracked.rs'], { cwd: root, env: fixtureEnvironment });
    const failure = run();
    assert.equal(failure.status, 1);
    assert.match(failure.stderr, /^untracked\.rs:1:TEST_CREDENTIAL_LITERAL\n$/u);
    assert.ok(!failure.stderr.includes('synthetic-not-output'));
    symlinkSync(path.join(root, 'safe.rs'), path.join(root, 'link.rs'));
    execFileSync('git', ['add', 'link.rs'], { cwd: root, env: fixtureEnvironment });
    assert.equal(run().status, 2);
    assert.equal(run().stderr, 'TEST_CREDENTIAL_CHECK_ERROR\n');
  } finally { rmSync(root, { recursive: true, force: true }); }
});
test('blank fixtures, dynamic helpers and unrelated golden vectors remain valid', () => {
  assert.deepEqual(scan('let password = " \\t\\n"; let cloud_password = Some("\\u{20}"); let secret = ""; let key = "golden-vector"; let token = "golden-vector"; let password = temporary_password("case");'), []);
});
test('factory arguments are split at their actual nesting level', () => {
  assert.deepEqual(scan('fixture_credentials("account", &temporary_password("case")); fixture_request(None);'), []);
  assert.deepEqual(scan('fixture_credentials("fixed-account", "");'), []);
  assert.equal(scan('fixture_credentials(dynamic("x", "y"), Some(String::from("fixed")));').length, 1);
  assert.equal(scan('fixture_request(\nSome(("fixed").into())\n);').length, 1);
});
test('temporary_password requires random process salt that reaches the returned fixture', () => {
  assert.deepEqual(scan(helper), []);
  assert.equal(scan('fn temporary_password(label: &str) -> String { format!("synthetic-{label}-{}", std::process::id()) }')[0].rule, 'TEST_CREDENTIAL_RNG');
  assert.equal(scan(helper.replace('synthetic-{label}-{seed}', 'synthetic-{label}-constant'))[0].rule, 'TEST_CREDENTIAL_RNG');
  assert.equal(scan(helper.replace('getrandom::fill(&mut bytes)', 'unrelated::fill(&mut bytes)'))[0].rule, 'TEST_CREDENTIAL_RNG');
  assert.equal(scan(helper.replace('let seed = SEED.get_or_init(|| {', 'getrandom::fill(&mut bytes).unwrap(); let seed = SEED.get_or_init(|| {').replace('getrandom::fill(&mut bytes).expect("synthetic RNG failure");', ''))[0].rule, 'TEST_CREDENTIAL_RNG');
  assert.equal(analyzeRustTestCredentials('#[cfg(test)] mod tests {}', 'src-tauri/src/lib.rs')[0].rule, 'TEST_CREDENTIAL_RNG');
});
test('tracked file paths cannot escape the repository or select other file types', () => {
  for (const value of ['/tmp/a.rs', '../a.rs', 'a/../b.rs', './a.rs', 'a\\b.rs', 'C:a.rs', 'a\0.rs', 'a\n.rs', 'a.js', 'a//b.rs']) assert.equal(isSafeTrackedRustPath(value), false);
  for (const value of ['src-tauri/src/lib.rs', 'space dir/测试.rs']) assert.equal(isSafeTrackedRustPath(value), true);
});
