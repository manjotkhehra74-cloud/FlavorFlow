'use strict';

// Aggregate opening balances transcribed from the production/dispatch report.
// The duplicate Pear Pulp page is counted once; both distinct Red Chilli rows
// are retained and combined by product name in the app.
const SNAPSHOT_DATE = '2026-10-22';
const OPENING_DRUM_BALANCES = [
  { productName: 'Green Chilli Puree Salt Mix (10%)', drums: 5476, kg: 1211015 },
  { productName: 'Pear Pulp', drums: 6, kg: 1270 },
  { productName: 'Tomato Paste', drums: 5062, kg: 1137216 },
  { productName: 'Garlic Paste Salt Mix', drums: 478, kg: 91520.5 },
  { productName: 'Carrot Paste Salt Mix (10%)', drums: 4086, kg: 903267 },
  { productName: 'Carrot Pulp (10%)', drums: 393, kg: 84808 },
  { productName: 'Apple Paste', drums: 1655, kg: 366951 },
  { productName: 'Red Chilli Puree Salted', drums: 128, kg: 28190 },
  { productName: 'Apple Pulp', drums: 9, kg: 1722 },
  { productName: 'Guava Pulp', drums: 160, kg: 33512 },
  { productName: 'Pear Paste', drums: 2826, kg: 611688 },
];

module.exports = { SNAPSHOT_DATE, OPENING_DRUM_BALANCES };
