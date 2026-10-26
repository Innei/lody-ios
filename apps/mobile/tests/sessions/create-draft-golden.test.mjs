import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { pendingSessionFromDraft } from '../../src/features/sessions/createDraft.ts';
import { setLocale } from '../../src/lib/i18n/index.ts';

const read = (name) =>
  JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url)));
const cases = read('create-draft.json');
const golden = read('create-draft.golden.json');

setLocale('en');

test('the JS draft record matches the golden the native CreateDraftRecord check pins', () => {
  for (const { name, draft, payload, createdAt } of cases) {
    const { record, created } = pendingSessionFromDraft(
      draft,
      payload,
      createdAt,
    );
    assert.equal(JSON.stringify(record), golden[name].record, name);
    assert.equal(JSON.stringify(created), golden[name].created, name);
  }
});
