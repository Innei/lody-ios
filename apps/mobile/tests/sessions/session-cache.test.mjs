import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';

test('session history restores before network, survives reconnect, and yields to fresh history', async () => {
  const db = new Map();
  let listener, cleanup, restore, states;
  globalThis.__sessionCacheTest = {
    useState(value) {
      const index = states.push(value) - 1;
      return [
        value,
        (next) => {
          states[index] =
            typeof next === 'function' ? next(states[index]) : next;
        },
      ];
    },
    useRef: (current) => ({ current }),
    useEffect: (effect) => {
      cleanup = effect();
    },
    addDataRuntimeListener: (callback) => {
      listener = callback;
      return { remove() {} };
    },
    watchSession: async () => {},
    unwatchSession: async () => {},
    readLocalValue: (key) =>
      new Promise((resolve) => {
        restore = () => resolve(db.get(key) ?? null);
      }),
    writeLocalValue: async () => {
      assert.fail('page must not persist runtime snapshots');
    },
    clearLocalValues: async () => db.clear(),
    showToast() {},
  };
  const bundle = await build({
    entryPoints: ['apps/mobile/src/features/sessions/useSessionRuntime.ts'],
    bundle: true,
    format: 'esm',
    write: false,
    plugins: [
      {
        name: 'native-and-hooks',
        setup(build) {
          build.onResolve({ filter: /^(react|@lody-ios\/kit)$/ }, () => ({
            path: 'mock',
            namespace: 'test',
          }));
          build.onLoad({ filter: /.*/, namespace: 'test' }, () => ({
            contents:
              'export const {useState,useRef,useEffect,addDataRuntimeListener,watchSession,unwatchSession,readLocalValue,writeLocalValue,clearLocalValues,showToast} = globalThis.__sessionCacheTest;',
          }));
        },
      },
    ],
  });
  const { useSessionRuntime } = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );
  const mount = (user = 'a', workspace = 'w') => {
    states = [];
    return useSessionRuntime('s', user, workspace);
  };
  const tick = () => new Promise((resolve) => setImmediate(resolve));
  const entries = [
    { id: 'message', items: [{ type: 'text', text: 'saved conversation' }] },
  ];
  const emit = (status, revision, values = [], generation = 1) =>
    listener({
      sessionId: 's',
      generation,
      state: 'live',
      session: JSON.stringify({ v: 1, status, revision, entries: values }),
    });
  // Swift owns persistence now; the hook only reads its account-scoped snapshot.
  db.set(
    'session:["a","w","s"]',
    JSON.stringify({ v: 1, status: 'live', revision: 100, entries }),
  );
  mount();
  emit('live', 100, entries);
  await tick();
  cleanup();
  const second = mount();
  emit('syncing', 1);
  restore();
  await tick();
  assert.deepEqual(states[0].entries, entries);
  assert.equal(states[0].status, 'syncing');
  assert.equal(
    second.cursor.current.revision,
    1,
    'cached cursor cannot reject new replica',
  );
  emit('offline', 2);
  assert.deepEqual(states[0].entries, entries);
  assert.equal(states[0].status, 'offline');
  emit('live', 3, []);
  assert.deepEqual(
    states[0].entries,
    [],
    'authoritative empty history replaces cache',
  );
  await tick();
  cleanup();
  mount();
  emit('live', 4, entries);
  restore();
  await tick();
  assert.deepEqual(
    states[0].entries,
    entries,
    'late disk read cannot overwrite network',
  );
  emit('syncing', 1, [], 2);
  emit('offline', 2, [], 2);
  assert.deepEqual(
    states[0].entries,
    entries,
    'runtime recovery keeps last history',
  );
  cleanup();
  mount('other');
  restore();
  await tick();
  assert.deepEqual(states[0].entries, [], 'account isolation');
  cleanup();
  mount('a', 'other');
  restore();
  await tick();
  assert.deepEqual(states[0].entries, [], 'workspace isolation');
  cleanup();
  mount();
  cleanup();
  restore();
  await tick();
  assert.deepEqual(
    states[0].entries,
    [],
    'late restore after unmount is ignored',
  );
  delete globalThis.__sessionCacheTest;
});
