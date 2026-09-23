import assert from 'node:assert/strict';
import test from 'node:test';
import { createPrefsKey } from '../../src/features/sessions/createPrefs.ts';

test('preserves the storage key shared by the app and snapshot publisher', () => {
  assert.equal(createPrefsKey('user', 'workspace'), 'create:user:workspace');
  assert.notEqual(
    createPrefsKey('other', 'workspace'),
    createPrefsKey('user', 'workspace'),
  );
  assert.notEqual(
    createPrefsKey('user', 'other'),
    createPrefsKey('user', 'workspace'),
  );
});
