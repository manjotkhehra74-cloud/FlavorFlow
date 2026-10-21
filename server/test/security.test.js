'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const serverSource = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
const jwtSource = fs.readFileSync(path.join(__dirname, '..', 'jwt.js'), 'utf8');

test('API request bodies are not written to a public web-root log', () => {
  assert.doesNotMatch(serverSource, /appendFileSync[\s\S]{0,500}req\.body/);
  assert.match(serverSource, /app\.use\('\/ff-requests\.txt'/);
});

test('JWT signing requires a configured environment or protected secret file', () => {
  assert.match(jwtSource, /function loadSecret\(\)/);
  assert.doesNotMatch(jwtSource, /process\.env\.JWT_SECRET\s*\|\|\s*['"`][^'"`]{8,}['"`]/);
  assert.match(jwtSource, /\.jwt-secret/);
});
