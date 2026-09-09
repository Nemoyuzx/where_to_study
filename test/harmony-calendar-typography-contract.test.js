import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { transformSync } from 'esbuild'

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8')
const commonPath = '../native/harmony/entry/src/main/ets/common/'
const calendarPath = '../native/harmony/entry/src/main/ets/view/calendar/'
const policySource = read(`${commonPath}CalendarTypography.ets`)
// Execute the actual pure ArkTS policy rather than a JavaScript copy of its logic.
const { code } = transformSync(policySource, { loader: 'ts', format: 'esm' })
const { CalendarTypography } = await import(
  `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`
)
const calendarSources = Object.fromEntries([
  'ExpandedTeachingCalendarView',
  'MobileTeachingCalendarView',
  'MobileCalendarTimelineView',
].map((name) => [name, read(`${calendarPath}${name}.ets`)]))

function fontSizeCalls(source) {
  // Ignore CalendarTypography.fontSize itself while covering both chained and
  // line-separated ArkUI modifiers.
  return [...source.matchAll(/(?<![\w])\.fontSize\(/g)].map((match) => {
    const start = match.index + match[0].length
    let depth = 1
    let end = start
    while (end < source.length && depth > 0) {
      if (source[end] === '(') depth += 1
      if (source[end] === ')') depth -= 1
      end += 1
    }
    assert.equal(depth, 0, 'fontSize call must have a closing parenthesis')
    return {
      argument: source.slice(start, end - 1),
      line: source.slice(0, start).split('\n').length,
    }
  })
}

function fontSizesFor(source, context) {
  return fontSizeCalls(source).map(({ argument }) => (
    Function('CalendarTypography', `return (${argument})`).call(context, CalendarTypography)
  ))
}

function builderSource(component, name) {
  const source = calendarSources[component]
  const start = source.indexOf(`\n  ${name}(`)
  assert.ok(start >= 0, `${component}.${name} must remain covered`)
  const nextBuilder = source.indexOf('\n  @Builder', start + 1)
  return source.slice(start, nextBuilder < 0 ? undefined : nextBuilder)
}

test('Harmony calendar policy raises small PC labels and preserves larger and phone fonts', () => {
  assert.equal(CalendarTypography.minimumPcFontSize, 10)
  for (const requested of [8, 9, 9.5, 10, 10.5, 11, 14, 24]) {
    assert.equal(CalendarTypography.fontSize(requested, false), requested)
    assert.equal(CalendarTypography.fontSize(requested, true), requested < 10 ? 10 : requested)
  }
})

test('all calendar layouts apply the PC font minimum independently of window layout', () => {
  for (const [name, source] of Object.entries(calendarSources)) {
    assert.match(source, /import\s*\{\s*CalendarTypography\s*\}\s*from\s*'\.\.\/\.\.\/common\/CalendarTypography'/)
    assert.ok(
      /(?:@Local|private readonly)\s+isPc:\s*boolean\s*=\s*DeviceState\.isPc2in1\(\)/.test(source),
      `${name}: the PC typography gate must use device type, independently of window width`,
    )
    const calls = fontSizeCalls(source)
    assert.ok(calls.length > 0, `${name}: calendar typography must be scanned`)
    for (const { argument, line } of calls) {
      const requestedNumbers = [...argument.matchAll(/\b\d+(?:\.\d+)?\b/g)]
        .map(([number]) => Number(number))
      if (requestedNumbers.some((number) => number < 10)) {
        assert.match(
          argument,
          /^CalendarTypography\.fontSize\([\s\S]*,\s*this\.isPc\)$/,
          `${name}:${line}: sub-10fp requests must pass through the PC typography policy`,
        )
      }
    }
    // A narrow PC window can select a compact calendar; width alone must not
    // reintroduce small labels. Cover every current expanded/week-column branch.
    for (const expanded of [false, true]) {
      for (const showsWeekColumns of [false, true]) {
        const sizes = fontSizesFor(source, { isPc: true, expanded, showsWeekColumns })
        sizes.forEach((size, index) => {
          assert.ok(
            Number.isFinite(size) && size >= 10,
            `${name}:${calls[index].line}: PC font ${size}fp is below 10fp ` +
              `(expanded=${expanded}, showsWeekColumns=${showsWeekColumns})`,
          )
        })
      }
    }
  }
})

test('reported all-day, year, slot and course labels retain their non-PC font requests', () => {
  const fixtures = [
    ['ExpandedTeachingCalendarView', 'allDayRow', {}, [10, 9, 9, 9]],
    ['ExpandedTeachingCalendarView', 'miniMonth', {}, [15, 8]],
    ['ExpandedTeachingCalendarView', 'yearDayButton', {}, [9]],
    ['MobileCalendarTimelineView', 'slotAxisLabel', {}, [10, 9]],
    ['MobileCalendarTimelineView', 'slotGuide', {}, [9]],
    ['MobileCalendarTimelineView', 'courseBlockForExpanded', { showsWeekColumns: true }, [9, 8, 8]],
    ['MobileCalendarTimelineView', 'courseBlockForExpanded', { showsWeekColumns: false }, [11, 9, 9]],
    ['MobileCalendarTimelineView', 'courseBlockForWeek', {}, [10, 8, 10, 10, 10]],
    ['MobileTeachingCalendarView', 'weekDateStrip', {}, [9.5, 9.5]],
    ['MobileTeachingCalendarView', 'dateStripButton', {}, [11, 11, 8]],
    ['MobileTeachingCalendarView', 'weekAllDayItems', {}, [11, 9.5]],
    ['MobileTeachingCalendarView', 'miniMonth', {}, [17, 8]],
    ['MobileTeachingCalendarView', 'yearDayButton', {}, [8]],
  ]
  for (const [component, builder, context, expected] of fixtures) {
    const source = builderSource(component, builder)
    assert.deepEqual(
      fontSizesFor(source, { isPc: false, ...context }),
      expected,
      `${component}.${builder}: preserve the existing phone/tablet typography`,
    )
    assert.deepEqual(
      fontSizesFor(source, { isPc: true, ...context }),
      expected.map((size) => size < 10 ? 10 : size),
      `${component}.${builder}: every reported small label reaches the PC minimum`,
    )
  }
  assert.match(
    builderSource('ExpandedTeachingCalendarView', 'monthDayCell'),
    /Text\(this\.monthWeekLabel\(day\)\)\s*\.fontSize\(CalendarTypography\.fontSize\(8,\s*this\.isPc\)\)/,
  )
})

test('larger PC week and holiday labels have their own vertical space', () => {
  const monthCell = builderSource('ExpandedTeachingCalendarView', 'monthDayCell')
  assert.match(monthCell, /if \(!this\.isPc && this\.monthWeekLabel\(day\)\.length > 0\)/)
  const pcWeekRow = monthCell.match(/if \(this\.isPc\) \{([\s\S]*?)\n        \}/)?.[1]
  assert.ok(pcWeekRow, 'all PC month cells must reserve the week-label row')
  assert.match(pcWeekRow, /Text\(this\.monthWeekLabel\(day\)\)/)
  assert.match(pcWeekRow, /\.height\(14\)/)
  assert.match(pcWeekRow, /\.maxLines\(1\)/)
  assert.match(pcWeekRow, /\.textOverflow\(\{ overflow: TextOverflow\.Ellipsis \}\)/)
  assert.doesNotMatch(pcWeekRow, /\.position\(/)
  assert.match(
    builderSource('MobileTeachingCalendarView', 'dateStripButton'),
    /\.height\(this\.isPc \? 14 : 8\)/,
  )
})
