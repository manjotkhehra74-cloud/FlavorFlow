'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { parseRegisterReadings } = require('../drum_ocr');

test('register OCR parser returns numbered weight suggestions and missing numbers without saving anything', () => {
  const draft = parseRegisterReadings([
    { text: 'Drum No. 1 225.4 kg', confidence: 96 },
    { text: '2 226,75', confidence: 91 },
    { text: '3 228.1 kg', confidence: 42 },
    { text: '4 999.0 kg', confidence: 99 },
  ], 1, 3);

  assert.deepEqual(draft.readings.map(({ fill_number, gross_weight_kg }) => [fill_number, gross_weight_kg]), [
    [1, 225.4],
    [2, 226.75],
    [3, 228.1],
  ]);
  assert.equal(draft.readings[0].uncertain, false);
  assert.equal(draft.readings[2].uncertain, true);
  assert.deepEqual(draft.missing_numbers, []);
  assert.equal(draft.review_required, true);
});

test('register OCR parser flags duplicate and implausible readings and reports gaps', () => {
  const draft = parseRegisterReadings([
    { text: '10 15.0', confidence: 95 },
    { text: '10 215.0', confidence: 80 },
    { text: '12 215.0', confidence: 90 },
  ], 10, 12);

  assert.equal(draft.readings.length, 2);
  assert.equal(draft.readings[0].fill_number, 10);
  assert.equal(draft.readings[0].uncertain, true);
  assert.match(draft.readings[0].uncertainty_reasons.join(' '), /Multiple readings/);
  assert.deepEqual(draft.missing_numbers, [11]);
});
