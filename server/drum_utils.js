'use strict';

function parseIsoDate(value) {
  const text = String(value || '').trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  return { year, month, day };
}

function addMonths(dateText, months) {
  const source = parseIsoDate(dateText);
  if (!source) throw new TypeError('Date must be a valid YYYY-MM-DD value.');
  const amount = Number(months);
  if (!Number.isInteger(amount) || amount < 1 || amount > 240) {
    throw new RangeError('Shelf life must be an integer from 1 to 240 months.');
  }

  const absoluteMonth = source.year * 12 + (source.month - 1) + amount;
  const year = Math.floor(absoluteMonth / 12);
  const monthIndex = absoluteMonth % 12;
  const lastDay = new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
  const day = Math.min(source.day, lastDay);
  return `${String(year).padStart(4, '0')}-${String(monthIndex + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

function normalizePackagingType(value) {
  const type = String(value || '').trim().toLowerCase();
  if (type === 'aseptic_bag' || type === 'liner_bag') return type;
  throw new TypeError('Packaging must be aseptic_bag or liner_bag.');
}

function normalizeGrossWeight(value) {
  const weight = Number(value);
  if (!Number.isFinite(weight) || weight <= 0 || weight > 100000) {
    throw new TypeError('Each filled drum needs a gross weight greater than 0 kg and at most 100000 kg.');
  }
  return Math.round(weight * 1000) / 1000;
}

module.exports = { parseIsoDate, addMonths, normalizePackagingType, normalizeGrossWeight };
