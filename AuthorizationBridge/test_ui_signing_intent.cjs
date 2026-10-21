// Regression for the signing intent mismatch with TEST TSA + Windows demo signer.
// Verify the *actual* JS metadata capture expression, plus both consumers.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const source = fs.readFileSync(path.join(__dirname, '..', 'authorization_pdf_v326.js'), 'utf8');
const snapshot = source.match(/const signingDetails = Object\.freeze\(\{[\s\S]*?\n      \}\);/);
assert.ok(snapshot, 'Signing metadata must be captured exactly once before local approval');
const capture = new Function(
  'testMode', 'localTestTsa', 'document', 'authAppendEarEnabled',
  snapshot[0] + '\nreturn signingDetails;'
);
function inspect(testSigner, localTsa, reason = '  Autorizace dokumentace  ') {
  const values = {
    'auth-reason': reason,
    'auth-location': ' Praha ',
    'auth-contact': '  ',
  };
  const doc = { getElementById(id) { return { value: values[id] }; } };
  return capture(testSigner, localTsa, doc, () => false);
}

const localTsa = inspect(false, true);
const localSigner = inspect(true, true);
const production = inspect(false, false);
for (const details of [localTsa, localSigner]) {
  assert.equal(details.reason, 'TEST – Autorizace dokumentace');
  assert.equal(details.location, 'Praha');
  assert.equal(details.contact, '');
  assert.equal(details.append_ear, false);
  assert.ok(Object.isFrozen(details));
}
assert.equal(production.reason, 'Autorizace dokumentace');
const approval = source.match(/const signingIntent = \{([\s\S]*?)\n        \};/);
const final = source.match(/const meta = \{([\s\S]*?)\n      \};\n\n      const fd = new FormData\(\);/);
assert.ok(approval, 'Missing confirmation signing intent');
assert.ok(final, 'Missing final signing metadata');
assert.match(approval[1], /\.\.\.signingDetails,/);
assert.match(final[1], /\.\.\.signingDetails,/);
assert.doesNotMatch(final[1], /reason:\s*\(\(testMode\s*\|\|\s*localTestTsa/);
console.log('TEST TSA / Windows demo signer: approved and submitted signing details are identical.');
