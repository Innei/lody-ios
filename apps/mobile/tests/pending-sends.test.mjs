import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
};
const record = (id, phase = 'waiting') => ({
  session: { id, title: 'Draft' },
  send: {
    id: `turn-${id}`,
    text: 'hello',
    attachments: [
      { id: 'file', uri: 'file:///draft', name: 'draft.txt', kind: 'file' },
    ],
    phase,
    choice: {},
  },
});

test('pending sends publish before durable writes, merge hydration, isolate scopes and never restore dispatch in flight', async () => {
  const disk = new Map();
  const hydration = deferred();
  let generation = 0;
  let blockWrite;
  const writes = [];
  globalThis.__pendingLocal = {
    localGeneration: () => generation,
    readLocal: (key) =>
      key === 'pending-sends:u:w'
        ? hydration.promise
        : Promise.resolve(disk.get(key)),
    writeLocal: async (key, records, version) => {
      writes.push({ key, records });
      if (blockWrite) await blockWrite.promise;
      if (version === generation) disk.set(key, records);
    },
  };
  const bundle = await build({
    entryPoints: [
      new URL('../src/cloud/send/pendingSends.ts', import.meta.url).pathname,
    ],
    bundle: true,
    format: 'esm',
    write: false,
    plugins: [
      {
        name: 'local',
        setup(b) {
          b.onResolve({ filter: /^(react|.*\/kv\.ts)$/ }, ({ path }) => ({
            path,
            namespace: 'mock',
          }));
          b.onLoad({ filter: /.*/, namespace: 'mock' }, ({ path }) => ({
            contents:
              path === 'react'
                ? 'export function useSyncExternalStore() {}'
                : 'export const {localGeneration,readLocal,writeLocal}=globalThis.__pendingLocal;',
          }));
        },
      },
    ],
  });
  const { getPendingSendStore } = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );
  const store = getPendingSendStore('u', 'w');
  const draft = record('new');
  blockWrite = deferred();
  const put = store.put(draft);
  draft.send.text = 'mutated outside store';
  assert.equal(store.getSnapshot().records[0].send.text, 'hello');
  assert.equal(writes.length, 0);
  hydration.resolve([
    record('old', 'sending'),
    record('creating', 'creating'),
    record('failed', 'failed'),
  ]);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(store.getSnapshot().ready, true);
  assert.deepEqual(
    store.getSnapshot().records.map((item) => item.send.phase),
    ['unknown', 'unknown', 'failed', 'waiting'],
  );
  assert.equal(writes.length, 1);
  assert.equal(disk.size, 0);
  blockWrite.resolve();
  await put;
  blockWrite = undefined;
  assert.equal(disk.get('pending-sends:u:w').length, 4);
  assert.equal(
    disk.get('pending-sends:u:w')[2].send.attachments[0].uri,
    'file:///draft',
  );
  const first = store.put(record('new', 'sending'));
  const second = store.put(record('new', 'uploaded'));
  await Promise.all([first, second]);
  assert.deepEqual(
    writes.slice(-2).map((write) => write.records.at(-1).send.phase),
    ['sending', 'uploaded'],
  );
  assert.notEqual(getPendingSendStore('other', 'w'), store);
  const failure = deferred();
  blockWrite = failure;
  const failedWrite = store.put(record('failed-write'));
  failure.reject(new Error('disk full'));
  await assert.rejects(failedWrite, /disk full/);
  blockWrite = undefined;
  await store.remove('failed-write');
  assert.equal(
    disk
      .get('pending-sends:u:w')
      .some((item) => item.session.id === 'failed-write'),
    false,
  );
  generation++;
  await assert.rejects(store.put(record('stale')), /scope_expired/);
  assert.notEqual(getPendingSendStore('u', 'w'), store);
  delete globalThis.__pendingLocal;
});
