'use strict';

let workerPromise = null;
let recognitionQueue = Promise.resolve();

function normalizeLineRecords(lines) {
  if (Array.isArray(lines)) {
    return lines.map((line) => (typeof line === 'string'
      ? { text: line, confidence: 0 }
      : { text: String((line && line.text) || ''), confidence: Number(line && line.confidence) || 0 }));
  }
  return String(lines || '').split(/\r?\n/).map((text) => ({ text, confidence: 0 }));
}

/**
 * Turn OCR lines into suggestions only. The caller must keep every result in a
 * reviewable draft; low-confidence, implausible and duplicate readings are
 * explicitly marked for a human to check before any stock write.
 */
function parseRegisterReadings(lines, fillNumberFrom, fillNumberTo) {
  const from = Number(fillNumberFrom);
  const to = Number(fillNumberTo);
  const rangeValid = Number.isSafeInteger(from) && from > 0 && Number.isSafeInteger(to) && to >= from;
  const candidates = [];

  for (const line of normalizeLineRecords(lines)) {
    const text = line.text.trim();
    if (!text) continue;
    const tokens = text.match(/\d+(?:[.,]\d+)?/g) || [];
    if (tokens.length < 2 || !/^\d+$/.test(tokens[0])) continue;

    const fillNumber = Number(tokens[0]);
    const grossWeightKg = Number(tokens[1].replace(',', '.'));
    if (!Number.isSafeInteger(fillNumber) || fillNumber <= 0 || !Number.isFinite(grossWeightKg) || grossWeightKg <= 0) continue;
    if (rangeValid && (fillNumber < from || fillNumber > to)) continue;

    const confidence = Math.max(0, Math.min(100, Number(line.confidence) || 0));
    const reasons = [];
    if (confidence < 65) reasons.push('Low OCR confidence');
    if (grossWeightKg < 30 || grossWeightKg > 1000) reasons.push('Weight is outside the usual drum range');
    if (tokens.length > 2) reasons.push('More than two numbers were read on this line');
    candidates.push({
      fill_number: fillNumber,
      gross_weight_kg: Math.round(grossWeightKg * 1000) / 1000,
      confidence,
      uncertain: reasons.length > 0,
      uncertainty_reasons: reasons,
      source_text: text.slice(0, 180),
    });
  }

  const byNumber = new Map();
  for (const reading of candidates) {
    const previous = byNumber.get(reading.fill_number);
    if (!previous) {
      byNumber.set(reading.fill_number, reading);
      continue;
    }
    const chosen = reading.confidence > previous.confidence ? reading : previous;
    chosen.uncertain = true;
    chosen.uncertainty_reasons = [...new Set([
      ...chosen.uncertainty_reasons,
      'Multiple readings were found for this drum number',
    ])];
    byNumber.set(reading.fill_number, chosen);
  }

  const readings = [...byNumber.values()].sort((a, b) => a.fill_number - b.fill_number);
  const missingNumbers = rangeValid
    ? Array.from({ length: Math.min(to - from + 1, 500) }, (_, index) => from + index)
      .filter((number) => !byNumber.has(number))
    : [];
  return { readings, missing_numbers: missingNumbers, review_required: true };
}

async function getWorker() {
  if (!workerPromise) {
    workerPromise = (async () => {
      const { createWorker, OEM } = require('tesseract.js');
      const english = require('@tesseract.js-data/eng');
      const worker = await createWorker(english.code, OEM.LSTM_ONLY, {
        langPath: english.langPath,
        gzip: english.gzip,
        logger: () => {},
      });
      await worker.setParameters({
        tessedit_pageseg_mode: '6',
        preserve_interword_spaces: '1',
      });
      return worker;
    })().catch((error) => {
      workerPromise = null;
      throw error;
    });
  }
  return workerPromise;
}

async function recognizeRegisterImage(imageBuffer, fillNumberFrom, fillNumberTo) {
  const job = recognitionQueue.then(async () => {
    const worker = await getWorker();
    const { data } = await worker.recognize(imageBuffer, {}, { text: true, blocks: true });
    const lines = [];
    for (const block of (data.blocks || [])) {
      for (const paragraph of (block.paragraphs || [])) {
        for (const line of (paragraph.lines || [])) lines.push({ text: line.text, confidence: line.confidence });
      }
    }
    if (!lines.length) lines.push(...normalizeLineRecords(data.text));
    return {
      ...parseRegisterReadings(lines, fillNumberFrom, fillNumberTo),
      line_count: lines.length,
    };
  });
  recognitionQueue = job.then(() => undefined, () => undefined);
  return job;
}

module.exports = { parseRegisterReadings, recognizeRegisterImage };
