import assert from 'node:assert/strict';
import { mock, test } from 'node:test';
import {
  inboxSections,
  projectSections,
  searchSections,
  sessionRow,
} from '../../src/features/sessions/inbox.ts';
import { withSessionViews } from '../../src/features/sessions/sessionViews.ts';

const disk = new Map();
let generation = 0;
let restore;
let failWrite = false;
mock.module('../../src/cloud/kv.ts', {
  namedExports: {
    localGeneration: () => generation,
    readLocal: async (key) => {
      const value = disk.get(key) ?? null;
      if (restore) await restore;
      return value;
    },
    writeLocal: async (key, value, expected) => {
      if (failWrite) throw new Error('disk full');
      if (generation === expected) disk.set(key, structuredClone(value));
    },
  },
});
const { createSessionViewStore, getSessionViewStore } =
  await import('../../src/features/sessions/sessionViewStore.ts');

let focusEffect;
const appListeners = new Set();
const AppState = {
  currentState: 'active',
  addEventListener: (_, callback) => {
    appListeners.add(callback);
    return { remove: () => appListeners.delete(callback) };
  },
};
mock.module('react-native', { namedExports: { AppState } });
mock.module('react', { namedExports: { useCallback: (callback) => callback } });
mock.module('expo-router', {
  namedExports: {
    useFocusEffect: (effect) => {
      focusEffect = effect;
    },
  },
});
mock.module('../../src/ui/toast.ts', { namedExports: { showToast: () => {} } });
const { useSessionViewed } =
  await import('../../src/features/sessions/useSessionViewed.ts');

test('only a focused session advances local viewing; background messages remain unseen', async () => {
  const store = getSessionViewStore('focus-user', 'focus-workspace');
  await store.ready;
  useSessionViewed('focus-user', 'focus-workspace', 's', 100);
  assert.deepEqual(
    store.getSnapshot(),
    {},
    'mounting a background route is not viewing',
  );
  let blur = focusEffect();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(store.getSnapshot().s, 100);
  blur();
  assert.equal(appListeners.size, 0);
  useSessionViewed('focus-user', 'focus-workspace', 's', 200);
  assert.equal(
    store.getSnapshot().s,
    100,
    'background catalog updates do not advance viewing',
  );
  AppState.currentState = 'background';
  blur = focusEffect();
  assert.equal(
    store.getSnapshot().s,
    100,
    'a focused route in a background app is not viewed',
  );
  AppState.currentState = 'active';
  appListeners.forEach((callback) => callback('active'));
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(
    store.getSnapshot().s,
    200,
    'foreground updates advance the visible watermark',
  );
  assert.deepEqual(disk.get('session-views:["focus-user","focus-workspace"]'), {
    s: 200,
  });
  blur();
  assert.equal(appListeners.size, 0);
});

const now = Date.parse('2026-09-11T12:00:00Z');
const session = (id, extra = {}) => ({
  id,
  title: id,
  machineId: 'm',
  projectId: 'p',
  status: 'completed',
  createdAt: new Date(now).toISOString(),
  pinned: false,
  archived: false,
  lastMessageAt: now - 60_000,
  ...extra,
});
const source = {
  projects: [{ id: 'p', name: 'Project', machineId: 'm', rootPath: '/tmp/p' }],
  sessions: [
    session('older', { lastMessageAt: now - 120_000 }),
    session('newer'),
    session('chat', { projectId: 'm:unassigned' }),
  ],
  machineIds: ['m'],
};
const builders = {
  activity: (data) => inboxSections(data, { accent: 'blue', now }),
  chat: (data) => inboxSections(data, { accent: 'blue', now, chatOnly: true }),
  projects: (data) => projectSections(data, 'blue', {}, now),
  search: (data) => searchSections(data, 'e', 'blue'),
  projectOrArchive: (data) => [
    {
      id: 'sessions',
      rows: data.sessions.map((s) => sessionRow(s, 'blue', '', now)),
    },
  ],
};
const order = (sections) =>
  sections.map((s) => [s.id, s.rows.map((r) => r.id)]);

test('viewing unbolds every list host without moving rows or removing the explicit read action', () => {
  const viewed = withSessionViews(
    source,
    Object.fromEntries(source.sessions.map((s) => [s.id, s.lastMessageAt])),
  );
  for (const [host, build] of Object.entries(builders)) {
    const before = build(source),
      after = build(viewed);
    assert.deepEqual(order(after), order(before), host);
    for (const row of after
      .flatMap((s) => s.rows)
      .filter((r) => source.sessions.some((s) => s.id === r.id))) {
      assert.equal(row.unread, false, host);
      assert.ok(
        row.actions.some((a) => a.id === 'read'),
        host,
      );
    }
  }
  assert.equal(source.sessions[0].lastReadAt, undefined);
  assert.equal(source.sessions[0].lastViewedMessageAt, undefined);
  const fresh = withSessionViews(
    { ...source, sessions: [session('newer', { lastMessageAt: now })] },
    { newer: now - 60_000 },
  );
  assert.equal(builders.activity(fresh)[0].rows[0].unread, true);
  const read = withSessionViews(
    { ...source, sessions: [session('newer', { lastReadAt: now })] },
    {},
  );
  assert.equal(builders.activity(read)[0].id, 'today');
  assert.equal(builders.activity(read)[0].rows[0].unread, false);
  assert.deepEqual(
    builders.activity(read)[0].rows[0].actions.map((a) => a.id),
    ['archive'],
  );
});

test('view watermarks survive a fresh store and preserve new messages despite clock skew', async () => {
  const store = createSessionViewStore('restart');
  await store.markViewed('s', 100);
  await store.markViewed('s', 90);
  const restarted = createSessionViewStore('restart');
  await restarted.ready;
  assert.deepEqual(restarted.getSnapshot(), { s: 100 });
  const data = { ...source, sessions: [session('s', { lastMessageAt: 101 })] };
  assert.equal(
    builders.activity(withSessionViews(data, restarted.getSnapshot()))[0]
      .rows[0].unread,
    true,
  );
});

test('late restoration merges all sessions without losing a newer local view', async () => {
  disk.set('late', { older: 400, newer: 100 });
  let release;
  restore = new Promise((resolve) => {
    release = resolve;
  });
  const store = createSessionViewStore('late');
  const write = store.markViewed('newer', 200);
  assert.equal(store.getSnapshot().newer, 200);
  release();
  restore = undefined;
  await write;
  assert.deepEqual(disk.get('late'), { older: 400, newer: 200 });
});

test('account and workspace isolation, logout fences late restores and writes', async () => {
  await getSessionViewStore('a', 'w').markViewed('s', 100);
  for (const [user, workspace] of [
    ['b', 'w'],
    ['a', 'other'],
    ['', 'w'],
  ]) {
    const store = getSessionViewStore(user, workspace);
    await store.ready;
    assert.deepEqual(store.getSnapshot(), {});
  }
  let release;
  restore = new Promise((resolve) => {
    release = resolve;
  });
  const old = createSessionViewStore('logout');
  const write = old.markViewed('s', 200);
  generation++;
  disk.clear();
  release();
  restore = undefined;
  await write;
  await old.markViewed('s', 300);
  assert.equal(disk.has('logout'), false);
  const next = getSessionViewStore('a', 'w');
  await next.ready;
  assert.deepEqual(next.getSnapshot(), {});
});

test('invalid persisted values are ignored and save failures reach the caller', async () => {
  disk.set('invalid', { valid: 20, bad: '200', infinity: Infinity });
  const store = createSessionViewStore('invalid');
  await store.ready;
  assert.deepEqual(store.getSnapshot(), { valid: 20 });
  await store.markViewed('empty');
  await store.markViewed('bad', NaN);
  failWrite = true;
  await assert.rejects(store.markViewed('s', 100), /disk full/);
  failWrite = false;
  await store.markViewed('s', 100);
  assert.equal(disk.get('invalid').s, 100, 'reopening retries a failed save');
});
