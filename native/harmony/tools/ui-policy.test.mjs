import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const views = fileURLToPath(new URL('../entry/src/main/ets/view/', import.meta.url));
const read = name => readFileSync(join(views, name), 'utf8');
function files(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry =>
    entry.isDirectory() ? files(join(directory, entry.name)) : entry.name.endsWith('.ets') ? [join(directory, entry.name)] : []);
}
// Preserve positions while excluding comments and quoted UI labels from the
// component inventory. Fluent attributes are balanced independently of bodies.
function codeOnly(source) {
  return source.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|`(?:\\.|[^`\\])*`/g,
    value => value.replace(/[^\n]/g, ' '));
}
function endOf(code, begin, open, close) {
  assert.equal(code[begin], open);
  let depth = 0;
  for (let index = begin; index < code.length; index++) {
    if (code[index] === open) depth++;
    if (code[index] === close && --depth === 0) return index + 1;
  }
  throw new Error('Unbalanced component source');
}
function scrollAttributes(source) {
  const code = codeOnly(source);
  const result = [];
  for (const match of code.matchAll(/\b(Scroll|List|Swiper)\s*\(/g)) {
    let position = endOf(code, code.indexOf('(', match.index), '(', ')');
    while (/\s/.test(code[position] ?? '') && position < code.length) position++;
    if (code[position] !== '{') continue;
    position = endOf(code, position, '{', '}');
    const begin = position;
    while (true) {
      const attribute = /^\s*\.\s*\w+\s*\(/.exec(code.slice(position));
      if (!attribute) break;
      position = endOf(code, position + attribute[0].lastIndexOf('('), '(', ')');
    }
    result.push({ kind: match[1], line: code.slice(0, match.index).split('\n').length, attributes: code.slice(begin, position) });
  }
  return result;
}

test('every user scroll has explicit boundary feedback, including short content', () => {
  let count = 0;
  for (const file of files(views)) {
    for (const component of scrollAttributes(readFileSync(file, 'utf8'))) {
      const label = `${file}:${component.line} ${component.kind}`;
      assert.match(component.attributes, /\.edgeEffect\(EdgeEffect\.(?:Spring|Fade),\s*\{\s*alwaysEnabled:\s*true\s*\}\)/, label);
      count++;
    }
  }
  assert.ok(count >= 20, 'Inventory must cover the real page, calendar and dialog scrollers');
});
test('calendar feedback does not add spring displacement to month detail or timeline gestures', () => {
  const mobile = read('calendar/MobileTeachingCalendarView.ets');
  const timeline = mobile.slice(mobile.indexOf('Scroll(interactive ? this.timelineScroller'), mobile.indexOf(".id('calendar.mobile.timeline-scroll')"));
  const details = mobile.slice(mobile.indexOf('List({ space: 0, scroller: interactive ?'), mobile.indexOf(".id('calendar.mobile.month-page."));
  for (const code of [timeline, details]) assert.match(code, /\.edgeEffect\(EdgeEffect\.Fade, \{ alwaysEnabled: true \}\)/);
  assert.match(details, /\.enableScrollInteraction\(interactive && this\.monthDetailsScrollEnabled\)/);
  assert.match(mobile, /\.parallelGesture\(/);
});
test('QM settings put the trailing disclosure and connection before credential opt-in and fields', () => {
  const source = read('SettingsView.ets');
  const qm = source.slice(source.indexOf('  qmPlusConnectionSurface() {'), source.indexOf('  accountSurface() {'));
  const connect = qm.indexOf(".id('settings.qmplus.connect')");
  const optIn = qm.indexOf(".id('settings.qmplus.autofill')");
  const account = qm.indexOf("'settings.qmplus.account'");
  const save = qm.indexOf(".id('settings.qmplus.save-login')");
  assert.ok(connect > 0 && connect < optIn && optIn < account && account < save);
  assert.match(qm, /\}\.layoutWeight\(1\)[\s\S]*?\.id\('settings.qmplus.details-toggle'\)/);
  assert.match(qm, /if \(this\.qmPlusSession\.savedLoginAvailable \? this\.qmPlusSession\.autoFillEnabled : this\.session\.qmPlusSaveLoginSelected\) \{/);
  assert.match(qm, /DisclosureClip\(\{ expanded: this\.session\.qmplusDetailsExpanded \}\)/);
});
