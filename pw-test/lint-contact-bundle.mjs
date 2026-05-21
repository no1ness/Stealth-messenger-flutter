#!/usr/bin/env node
//
// Regression guard for the pw-test contact-bundle migration.
//
// Background: contacts used to be added by raw user_id (UUID). Local-first
// E2E now requires a contact bundle (`stealth:<base64url(JSON)>` carrying
// userId, nickname, AND publicKey) — see .ai-factory/rules/base.md and
// .ai-factory/DESCRIPTION.md. Every pw-test script that adds a contact
// MUST resolve the bundle via:
//   - `readContactBundle(page)` from ./contact-bundle-helper.mjs, OR
//   - an internal helper like `getContactBundle()` that validates the
//     `stealth:` prefix (e.g. appium-call-test.mjs), OR
//   - a direct `"stealth:..."` literal.
//
// This linter scans every `pw-test/*.mjs` (except itself and the
// helper). A file that calls `addContact(...)` but shows no evidence
// of bundle-aware resolution is flagged as a regression candidate.
//
// Heuristic — false-positive friendly by design:
//   - Files without `addContact(` calls are skipped entirely.
//   - Files with `addContact(` must show at least ONE of:
//       * `readContactBundle` (the canonical helper)
//       * `getContactBundle` (per-file internal helper, e.g. appium-call-test)
//       * a literal `"stealth:..."` substring anywhere
//   - Otherwise the file fails with a clear remediation hint.
//
// Run from repo root: `node pw-test/lint-contact-bundle.mjs`

import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PW_TEST_DIR = dirname(fileURLToPath(import.meta.url));
const SELF = 'lint-contact-bundle.mjs';
const HELPER = 'contact-bundle-helper.mjs';

const files = readdirSync(PW_TEST_DIR)
  .filter((f) => f.endsWith('.mjs'))
  .filter((f) => f !== SELF && f !== HELPER)
  .sort();

const ADD_CONTACT = /\baddContact\s*\(/;
const READ_HELPER = /\breadContactBundle\b/;
const GET_HELPER = /\bgetContactBundle\b/;
const STEALTH_LITERAL = /["'`]stealth:[^"'`]+/;

let touched = 0;
let clean = 0;
const failures = [];

for (const filename of files) {
  const fullPath = join(PW_TEST_DIR, filename);
  const content = readFileSync(fullPath, 'utf8');

  if (!ADD_CONTACT.test(content)) {
    // File does not deal with contact-add at all — out of scope.
    continue;
  }
  touched += 1;

  const hasRead = READ_HELPER.test(content);
  const hasGet = GET_HELPER.test(content);
  const hasLiteral = STEALTH_LITERAL.test(content);

  if (hasRead || hasGet || hasLiteral) {
    clean += 1;
    continue;
  }

  // Locate the first `addContact(` line for a clear error pointer.
  const lines = content.split('\n');
  let lineNumber = 0;
  for (let i = 0; i < lines.length; i++) {
    if (ADD_CONTACT.test(lines[i])) {
      lineNumber = i + 1;
      break;
    }
  }

  failures.push({
    file: filename,
    line: lineNumber,
    reason:
      'calls addContact() but shows no evidence of bundle resolution. ' +
      'Import { readContactBundle } from "./contact-bundle-helper.mjs" ' +
      'and pass its result instead of a raw user_id.',
  });
}

if (failures.length > 0) {
  console.error('pw-test/lint-contact-bundle: FAIL');
  for (const f of failures) {
    const where = f.line > 0 ? `${f.file}:${f.line}` : f.file;
    console.error(`  ${where}: ${f.reason}`);
  }
  console.error(
    `\n${failures.length} file(s) failed, ${clean}/${touched} contact-touching files clean.`,
  );
  process.exit(1);
}

console.log(
  `OK: ${clean}/${touched} contact-touching pw-test files clean (no raw-UUID add-contact paths).`,
);
process.exit(0);
