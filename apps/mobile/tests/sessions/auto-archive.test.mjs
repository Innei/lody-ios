import assert from 'node:assert/strict';
import { mock, test } from 'node:test';

const disk = new Map();
let generation = 0;
let fail = false;
mock.module('../../src/cloud/kv.ts', {
  namedExports: {
    localGeneration: () => generation,
    readLocal: async (key) => disk.get(key) ?? null,
    writeLocal: async (key, value, expected) => {
      if (fail) throw new Error('disk full');
      if (generation === expected) disk.set(key, structuredClone(value));
    },
  },
});
const { createAutoArchiveObserver, createAutoArchivePreferencesStore } =
  await import('../../src/features/sessions/autoArchive.ts');
const enabled = { onPrMerged: true, onPrClosed: true };
const pr = (
  status,
  url = 'https://github.com/LodyAI/Lody/pull/1',
  extra = {},
) => ({
  url,
  repository: 'LodyAI/Lody',
  number: 1,
  status,
  ...extra,
});
const session = (status, extra = {}) => ({
  id: 's',
  userId: 'owner',
  archived: false,
  pullRequests: [pr(status)],
  ...extra,
});

test('autoarchive observes a terminal PR transition only for the current user', () => {
  const observer = createAutoArchiveObserver();
  assert.deepEqual(
    observer.observe(
      [session('open'), session('open', { id: 'other', userId: 'team' })],
      'owner',
      enabled,
    ),
    [],
  );
  assert.deepEqual(
    observer
      .observe(
        [session('merged'), session('merged', { id: 'other', userId: 'team' })],
        'owner',
        enabled,
      )
      .map((s) => s.id),
    ['s'],
  );
  assert.deepEqual(observer.observe([session('merged')], 'owner', enabled), []);
});

test('startup, restoring an archived session, replacing PRs and enabling preferences never retroarchive', () => {
  const observer = createAutoArchiveObserver();
  assert.deepEqual(observer.observe([session('merged')], 'owner', enabled), []);
  assert.deepEqual(
    observer.observe([session('merged', { archived: true })], 'owner', enabled),
    [],
  );
  assert.deepEqual(observer.observe([session('merged')], 'owner', enabled), []);
  assert.deepEqual(
    observer.observe(
      [
        session('merged', {
          pullRequests: [pr('merged', 'https://github.com/LodyAI/Lody/pull/2')],
        }),
      ],
      'owner',
      enabled,
    ),
    [],
  );
  const disabled = createAutoArchiveObserver();
  disabled.observe([session('open')], 'owner', {
    onPrMerged: false,
    onPrClosed: false,
  });
  assert.deepEqual(
    disabled.observe([session('closed')], 'owner', {
      onPrMerged: false,
      onPrClosed: false,
    }),
    [],
  );
  assert.deepEqual(disabled.observe([session('closed')], 'owner', enabled), []);
  assert.deepEqual(
    createAutoArchiveObserver().observe([session('closed')], 'owner', enabled),
    [],
    'a changed workspace has its own baseline',
  );
});

test('archive flags remain independent and latest PR ordering matches the upstream legacy timestamp rule', () => {
  const observer = createAutoArchiveObserver();
  const prefs = { onPrMerged: false, onPrClosed: true };
  observer.observe([session('open')], 'owner', prefs);
  assert.deepEqual(observer.observe([session('merged')], 'owner', prefs), []);
  assert.deepEqual(
    observer.observe([session('closed')], 'owner', prefs).map((s) => s.id),
    ['s'],
  );
  const legacy = createAutoArchiveObserver();
  legacy.observe(
    [
      session('open', {
        pullRequests: [
          pr('open', undefined, { reportedAt: '2026-10-11T10:00:00Z' }),
          pr('closed', undefined, { reportedAt: '2026-10-10T10:00:00Z' }),
        ],
      }),
    ],
    'owner',
    enabled,
  );
  assert.deepEqual(
    legacy
      .observe(
        [
          session('merged', {
            pullRequests: [
              pr('merged', undefined, { reportedAt: '2026-10-11T10:00:00Z' }),
              pr('closed', undefined, { reportedAt: '2026-10-10T10:00:00Z' }),
            ],
          }),
        ],
        'owner',
        enabled,
      )
      .map((s) => s.id),
    ['s'],
  );
});

test('autoarchive preferences default off, persist per account, and retain the previous value after a failed save', async () => {
  const a = createAutoArchivePreferencesStore('a');
  await a.ready;
  assert.deepEqual(a.getSnapshot().preferences, {
    onPrMerged: false,
    onPrClosed: false,
  });
  await a.update({ onPrMerged: true, onPrClosed: false });
  const restored = createAutoArchivePreferencesStore('a');
  await restored.ready;
  assert.equal(restored.getSnapshot().preferences.onPrMerged, true);
  const b = createAutoArchivePreferencesStore('b');
  await b.ready;
  assert.deepEqual(b.getSnapshot().preferences, {
    onPrMerged: false,
    onPrClosed: false,
  });
  fail = true;
  await assert.rejects(a.update(enabled), /disk full/);
  fail = false;
  assert.deepEqual(a.getSnapshot().preferences, {
    onPrMerged: true,
    onPrClosed: false,
  });
  generation++;
  await assert.rejects(a.update(enabled), /scope_expired/);
});
