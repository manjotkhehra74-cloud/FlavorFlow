'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { parseIsoDate, addMonths, normalizePackagingType, normalizeGrossWeight } = require('../drum_utils');

test('product shelf-life expiry adds whole months and clamps month-end safely', () => {
  assert.equal(addMonths('2025-01-31', 18), '2026-07-31');
  assert.equal(addMonths('2024-02-29', 12), '2025-02-28');
  assert.equal(addMonths('2025-08-31', 6), '2026-02-28');
});

test('date parser rejects impossible or non-ISO dates', () => {
  assert.deepEqual(parseIsoDate('2025-02-28'), { year: 2025, month: 2, day: 28 });
  assert.equal(parseIsoDate('2025-02-29'), null);
  assert.equal(parseIsoDate('28-02-2025'), null);
  assert.throws(() => addMonths('not-a-date', 18), /valid YYYY-MM-DD/);
  assert.throws(() => addMonths('2025-01-01', 0), /integer from 1 to 240/);
});

test('packaging and per-drum gross weights are validated and normalized', () => {
  assert.equal(normalizePackagingType('aseptic_bag'), 'aseptic_bag');
  assert.equal(normalizePackagingType('liner_bag'), 'liner_bag');
  assert.throws(() => normalizePackagingType('carton'), /Packaging must be/);
  assert.equal(normalizeGrossWeight('202.3456'), 202.346);
  assert.throws(() => normalizeGrossWeight(0), /greater than 0 kg/);
  assert.throws(() => normalizeGrossWeight('bad'), /greater than 0 kg/);
});
