const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '..', 'authorization_pdf_v326.js'), 'utf8');
const match = source.match(/function authExportFileStatuses\([^)]*\)\s*\{[\s\S]*?\n  \}/);
assert.ok(match, 'Export status logic must handle partial batches');
const context = vm.createContext({});
vm.runInContext(match[0], context);
function statuses(...args) {
  return JSON.parse(JSON.stringify(context.authExportFileStatuses(...args)));
}
assert.deepEqual(statuses(3, true, 1, false), ['signed', 'error', 'error']);
assert.deepEqual(statuses(2, false, 2, false), ['signed', 'signed']);
assert.deepEqual(statuses(2, false, 2, true), ['error', 'error']);
assert.deepEqual(statuses(3, true, NaN, false), ['error', 'error', 'error']);
assert.deepEqual(statuses(3, true, 99, false), ['error', 'error', 'error']);
console.log('Partial batch UI distinguishes completed, failed and unprocessed files.');
