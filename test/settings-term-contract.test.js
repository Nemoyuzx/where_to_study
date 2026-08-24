import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const schema = JSON.parse(readFileSync(
  new URL('../contracts/v1/where-to-study.schema.json', import.meta.url),
  'utf8',
))

test('settings contracts allow empty term defaults while schedules stay authoritative', () => {
  for (const definitionName of ['saved_settings', 'save_settings_request']) {
    const definition = schema.$defs[definitionName]
    assert.equal(definition.properties.term_id.type, 'string')
    assert.equal(definition.properties.term_id.minLength, undefined)
    assert.equal(
      definition.properties.term_id.pattern,
      '^(?:|[0-9]{4}-[0-9]{4}-[12])$',
    )
    assert.deepEqual(definition.properties.term_start_date.anyOf, [
      { const: '' },
      { type: 'string', format: 'date' },
    ])
  }

  const schedule = schema.$defs.schedule.properties
  assert.equal(schedule.term_id.minLength, 1)
  assert.equal(schedule.term_id.pattern, '^[0-9]{4}-[0-9]{4}-[12]$')
  assert.equal(schedule.term_start_date.format, 'date')
  assert.equal(schedule.term_start_date.anyOf, undefined)
})
