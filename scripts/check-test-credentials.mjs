// Narrow regression guard for known synthetic test credential patterns, not a Rust parser or CodeQL substitute.
import { execFileSync } from 'node:child_process';
import { lstatSync, readFileSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const helperPaths = new Set(['classrooms', 'lib', 'session_cache', 'settings_store'].map(name => `src-tauri/src/${name}.rs`));
export function isSafeTrackedRustPath(value) {
  return typeof value === 'string' && value.endsWith('.rs') && !/[\\:\x00-\x1f\x7f]/u.test(value) && !path.posix.isAbsolute(value) && value.split('/').every(part => part && part !== '.' && part !== '..');
}

// Keep string tokens separate: neither comments nor raw JSON contents become code.
function lex(source) {
  const tokens = [];
  let i = 0;
  const push = (kind, start, end, value) => tokens.push({ kind, start, end, value });
  while (i < source.length) {
    if (/\s/u.test(source[i])) { i++; continue; }
    if (source.startsWith('//', i)) { const end = source.indexOf('\n', i); i = end < 0 ? source.length : end; continue; }
    if (source.startsWith('/*', i)) {
      i += 2; let depth = 1;
      while (i < source.length && depth) {
        if (source.startsWith('/*', i)) { depth++; i += 2; }
        else if (source.startsWith('*/', i)) { depth--; i += 2; } else i++;
      }
      continue;
    }
    // Character literals are not string credentials (lifetimes do not match).
    const character = /^'(?:\\(?:u\{[\da-f_]+\}|x[\da-f]{2}|.)|[^'\\])'/iu.exec(source.slice(i));
    if (character) { push('raw', i, i + character[0].length, ''); i += character[0].length; continue; }
    const raw = /^(?:br|r)(#*)"/u.exec(source.slice(i));
    if (raw) {
      const start = i; const terminator = `"${raw[1]}`;
      const end = source.indexOf(terminator, i + raw[0].length);
      i = end < 0 ? source.length : end + terminator.length;
      push(raw[0].startsWith('br') ? 'raw' : 'string', start, i, source.slice(start + raw[0].length, end < 0 ? source.length : end)); continue;
    }
    if (source[i] === '"' || source.startsWith('b"', i)) {
      const start = i; const byte = source[i] === 'b'; if (byte) i++;
      i++; let value = '';
      while (i < source.length && source[i] !== '"') {
        if (source[i] === '\\') {
          i++; const escaped = source[i++];
          if (escaped === 'u' && source[i] === '{') {
            const end = source.indexOf('}', ++i); const hex = source.slice(i, end).replaceAll('_', '');
            value += /^[\da-f]+$/iu.test(hex) ? String.fromCodePoint(Number.parseInt(hex, 16)) : '?'; i = end + 1;
          } else if (escaped === 'x') { value += String.fromCharCode(Number.parseInt(source.slice(i, i + 2), 16)); i += 2; }
          else value += ({ n: '\n', r: '\r', t: '\t', '0': '\0' })[escaped] ?? escaped;
        } else value += source[i++];
      }
      if (source[i] === '"') i++;
      push(byte ? 'raw' : 'string', start, i, value); continue;
    }
    const identifier = /^[A-Za-z_][A-Za-z_0-9]*/u.exec(source.slice(i));
    if (identifier) { const start = i; i += identifier[0].length; push('id', start, i, identifier[0]); }
    else { push('punct', i, i + 1, source[i]); i++; }
  }
  return tokens;
}
function matching(tokens, start) {
  const close = { '(': ')', '[': ']', '{': '}' }[tokens[start]?.value];
  if (!close) return start;
  let depth = 1;
  for (let i = start + 1; i < tokens.length; i++) {
    if (tokens[i].kind !== 'punct') continue;
    if (tokens[i].value === tokens[start].value) depth++;
    if (tokens[i].value === close && --depth === 0) return i;
  }
  return tokens.length - 1;
}
function split(tokens, start, end, separators = new Set([',', ';', '}'])) {
  const result = []; let begin = start;
  for (let i = start; i < end; i++) {
    if (tokens[i].kind !== 'punct') continue;
    if (['(', '[', '{'].includes(tokens[i].value)) { i = matching(tokens, i); continue; }
    if (separators.has(tokens[i].value)) { result.push(tokens.slice(begin, i)); begin = i + 1; }
  }
  result.push(tokens.slice(begin, end)); return result;
}
function fixedValue(tokens) {
  let t = tokens;
  while (t[0]?.value === '&') t = t.slice(1);
  for (const method of ['into', 'to_owned', 'to_string']) {
    if (t.slice(-4).map(x => x.value).join('') === `.${method}()`) return fixedValue(t.slice(0, -4));
  }
  if (t.length === 1 && t[0].kind === 'string') return t[0].value.trim().length > 0;
  if (t[0]?.value === '(' && matching(t, 0) === t.length - 1) return fixedValue(t.slice(1, -1));
  const open = t.findIndex(x => x.value === '(');
  if (open >= 0 && ['Some', 'String::from'].includes(t.slice(0, open).map(x => x.value).join('')) && matching(t, open) === t.length - 1) return fixedValue(t.slice(open + 1, -1));
  return false;
}
function testRanges(tokens) {
  const ranges = [];
  for (let i = 0; i < tokens.length; i++) {
    if (tokens.slice(i, i + 7).map(x => x.value).join('') !== '#[cfg(test)]') continue;
    let body = i + 7;
    while (body < tokens.length && !['{', ';'].includes(tokens[body].value)) body++;
    if (tokens[body]?.value === '{') ranges.push([body + 1, matching(tokens, body)]);
    else if (tokens[body]?.value === ';') ranges.push([i + 7, body]);
  }
  return ranges;
}
function validHelper(body) {
  // Deliberately validate the shared, reviewed OnceLock/128-bit helper shape;
  // alternative RNG implementations require a reviewed policy extension.
  const code = body.map(t => t.kind === 'string' ? '"STRING"' : t.value).join(' ');
  const buffer = /let mut (\w+) = \[ 0 _u8 ; 1 6 \]/u.exec(code)?.[1];
  const seed = /let (\w+) = (\w+) \. get_or_init/u.exec(code);
  if (!buffer || !seed) return false;
  const [ , salt, storage ] = seed;
  const format = body.findLastIndex(t => t.value === 'format');
  const output = body.slice(format).find(t => t.kind === 'string')?.value ?? '';
  const initializer = code.slice(code.indexOf(`${storage} . get_or_init`), code.indexOf('format ! ( "STRING" )', code.indexOf('. collect ( )')));
  return code.includes(`static ${storage} :`) && code.includes('OnceLock') &&
    code.includes(`getrandom : : fill ( & mut ${buffer} )`) &&
    code.includes(`${buffer} . iter ( )`) && code.includes('. collect ( )') &&
    initializer.includes(`getrandom : : fill ( & mut ${buffer} )`) &&
    output.includes(`{${salt}}`) && output.includes('{label}') &&
    !code.includes('process : : id');
}
export function analyzeRustTestCredentials(source, file = 'fixture.rs') {
  const tokens = lex(source); const findings = []; const seen = new Set(); const helpers = new Set();
  const report = (token, rule) => {
    const line = source.slice(0, token?.start ?? 0).split('\n').length;
    const key = `${line}:${rule}`;
    if (!seen.has(key)) { seen.add(key); findings.push({ path: file, line, rule }); }
  };
  // Cargo integration test files are entirely test code, even without cfg(test).
  const ranges = file.split('/').slice(0, -1).includes('tests') ? [[0, tokens.length]] : testRanges(tokens);
  for (const [start, end] of ranges) {
    for (let i = start; i < end; i++) {
      const token = tokens[i];
      if (token.value === 'fn' && tokens[i + 1]?.value === 'temporary_password') {
        helpers.add(token.start); let begin = i + 2; while (begin < end && tokens[begin].value !== '{') begin++;
        if (!validHelper(tokens.slice(begin + 1, matching(tokens, begin)))) report(token, 'TEST_CREDENTIAL_RNG');
      }
      const normalized = token.value.replace(/([a-z0-9])([A-Z])/gu, '$1_$2').toLowerCase();
      if (token.kind === 'id' && /(?:^|_)(?:password|cloudpassword|passwd|secret)(?:_|$)/u.test(normalized)) {
        let value = i + 1;
        if (tokens[value]?.value === ':') {
          value++;
          // A typed local binding has '=' after its type; a struct field does not.
          const expression = split(tokens, value, end)[0];
          const equals = expression.findIndex(t => t.value === '=');
          if (equals >= 0) value += equals + 1;
        } else if (tokens[value]?.value === '=') value++; else continue;
        if (fixedValue(split(tokens, value, end)[0])) report(token, 'TEST_CREDENTIAL_LITERAL');
      }
      if (['fixture_credentials', 'fixture_request'].includes(token.value) && tokens[i - 1]?.value !== 'fn' && tokens[i + 1]?.value === '(') {
        const args = split(tokens, i + 2, matching(tokens, i + 1));
        if (fixedValue(args[token.value === 'fixture_credentials' ? 1 : 0] ?? [])) report(token, 'TEST_CREDENTIAL_FACTORY');
      }
    }
  }
  if (helperPaths.has(file) && helpers.size !== 1) report(tokens[0], 'TEST_CREDENTIAL_RNG');
  return findings;
}
export function checkRepository(root) {
  const base = realpathSync(root);
  const paths = execFileSync('git', ['ls-files', '-z', '--', '*.rs'], { cwd: base, encoding: 'utf8' }).split('\0').filter(Boolean);
  return paths.flatMap(file => {
    if (!isSafeTrackedRustPath(file)) throw new Error('TEST_CREDENTIAL_PATH');
    const target = path.join(base, file);
    if (lstatSync(target).isSymbolicLink() || !realpathSync(target).startsWith(`${base}${path.sep}`)) throw new Error('TEST_CREDENTIAL_PATH');
    return analyzeRustTestCredentials(readFileSync(target, 'utf8'), file);
  });
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2);
    if (args.length && (args.length !== 2 || args[0] !== '--root')) throw new Error('TEST_CREDENTIAL_ARGUMENTS');
    const findings = checkRepository(args[1] ?? process.cwd());
    for (const finding of findings) console.error(`${finding.path}:${finding.line}:${finding.rule}`);
    process.exitCode = findings.length ? 1 : 0;
  } catch { console.error('TEST_CREDENTIAL_CHECK_ERROR'); process.exitCode = 2; }
}
