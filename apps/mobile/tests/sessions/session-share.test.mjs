import assert from 'node:assert/strict';
import test from 'node:test';
import { sessionShareUrl } from '../../src/features/sessions/sessionShare.ts';

test('session share urls match the desktop web session path', () => {
  assert.equal(
    sessionShareUrl({ id: 'workspace', slug: 'work' }, 'session'),
    'https://lody.ai/work/sessions/session',
  );
  assert.equal(
    sessionShareUrl({ id: 'workspace', slug: '  work  ' }, 'session'),
    'https://lody.ai/work/sessions/session',
  );
});

test('session share urls fall back to the workspace id when slug is missing', () => {
  assert.equal(
    sessionShareUrl({ id: 'workspace', slug: null }, 'session'),
    'https://lody.ai/workspace/sessions/session',
  );
  assert.equal(
    sessionShareUrl({ id: 'workspace', slug: '   ' }, 'session'),
    'https://lody.ai/workspace/sessions/session',
  );
});

test('session share urls reject path-breaking identifiers', () => {
  assert.equal(
    sessionShareUrl({ id: 'workspace', slug: 'work/other' }, 'session'),
    undefined,
  );
  assert.equal(
    sessionShareUrl({ id: 'workspace', slug: 'work' }, 'session/extra'),
    undefined,
  );
  assert.equal(
    sessionShareUrl({ id: 'workspace', slug: 'work' }, 'session?x=1'),
    undefined,
  );
  assert.equal(sessionShareUrl({ id: '', slug: null }, 'session'), undefined);
  assert.equal(
    sessionShareUrl({ id: 'workspace', slug: 'work' }, ''),
    undefined,
  );
});
