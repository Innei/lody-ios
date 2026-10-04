import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';

test('session history restores before network, survives reconnect, and yields to fresh history', async () => {
  const db = new Map();
  let listener, cleanup, restore, states, finishPreparation;
  globalThis.__sessionCacheTest = {
    useState(value) {
      if (typeof value === 'function') value = value();
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
    prepareChatEntries: (json) =>
      new Promise((resolve) => {
        finishPreparation = () => resolve({ json });
      }),
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
    stdin: {
      contents: `export { useSessionRuntime } from './apps/mobile/src/features/sessions/useSessionRuntime.ts';
        export { prepareSessionHistory } from './apps/mobile/src/features/sessions/prepareSessionHistory.ts';
        export { clearLocal } from './apps/mobile/src/cloud/kv.ts';`,
      resolveDir: process.cwd(),
    },
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
              'export const {useState,useRef,useEffect,addDataRuntimeListener,watchSession,unwatchSession,prepareChatEntries,readLocalValue,writeLocalValue,clearLocalValues,showToast} = globalThis.__sessionCacheTest;',
          }));
        },
      },
    ],
  });
  const { useSessionRuntime, prepareSessionHistory, clearLocal } = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );
  const mount = (user = 'a', workspace = 'w', initial) => {
    states = [];
    return useSessionRuntime('s', user, workspace, true, initial);
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
  let prepared;
  const preparing = prepareSessionHistory('a', 'w', 's').then((value) => {
    prepared = value;
  });
  restore();
  await tick();
  assert.equal(
    prepared,
    undefined,
    'navigation preparation waits for native decoding',
  );
  finishPreparation();
  await preparing;
  assert.deepEqual(prepared.snapshot.entries, entries);
  assert.equal(
    prepared.snapshot.status,
    'syncing',
    'cached history is not a live connection',
  );
  assert.equal(prepared.nativeEntries.json, prepared.entriesJSON);
  const initial = {
    key: 'session:["a","w","s"]',
    generation: 0,
    snapshot: { status: 'syncing', revision: 100, entries },
  };
  const warm = mount('a', 'w', initial);
  assert.deepEqual(
    warm.snapshot.entries,
    entries,
    'cached content is present on the very first render',
  );
  assert.deepEqual(
    states[0].entries,
    entries,
    'mount effect must not clear prepared content',
  );
  emit('syncing', 1);
  assert.deepEqual(states[0].entries, entries);
  emit('live', 2, []);
  assert.deepEqual(
    states[0].entries,
    [],
    'prepared history yields to the new replica',
  );
  cleanup();
  assert.deepEqual(
    mount('other', 'w', initial).snapshot.entries,
    [],
    'prepared history is account scoped',
  );
  cleanup();
  assert.deepEqual(
    mount('a', 'other', initial).snapshot.entries,
    [],
    'prepared history is workspace scoped',
  );
  cleanup();
  assert.deepEqual(
    mount('a', 'w', { ...initial, generation: -1 }).snapshot.entries,
    [],
    'cleared cache cannot return through navigation params',
  );
  cleanup();
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
  const clearing = prepareSessionHistory('a', 'w', 's');
  restore();
  await tick();
  await clearLocal();
  finishPreparation();
  assert.equal(
    await clearing,
    undefined,
    'logout during native preparation discards the old account history',
  );
  delete globalThis.__sessionCacheTest;
});
