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
  send: { id: `turn-${id}`, text: 'hello', attachments: [], phase, choice: {} },
});

test('the RN outbox mirrors the native owner, publishes before its ack and expires with the local generation', async () => {
  const native = { generation: 0, ready: false, records: [], calls: [] };
  const listeners = new Set();
  const pending = [];
  const emit = () =>
    listeners.forEach((listener) => listener({ key: 'pending-sends:u:w' }));
  globalThis.__outboxNative = {
    localStoreGeneration: () => native.generation,
    readOutboxRaw: (user, workspace) =>
      JSON.stringify(
        user === 'u' && workspace === 'w'
          ? { ready: native.ready, records: native.records }
          : { ready: false, records: [] },
      ),
    addOutboxListener(listener) {
      listeners.add(listener);
      return { remove: () => listeners.delete(listener) };
    },
    outboxPut(user, workspace, json) {
      native.calls.push(['put', user, workspace, JSON.parse(json)]);
      const ack = deferred();
      pending.push(ack);
      return ack.promise;
    },
    outboxRemove(user, workspace, id) {
      native.calls.push(['remove', user, workspace, id]);
      native.records = native.records.filter((item) => item.session.id !== id);
      return Promise.resolve();
    },
  };
  const bundle = await build({
    entryPoints: [
      new URL('../../src/cloud/send/pendingSends.ts', import.meta.url).pathname,
    ],
    bundle: true,
    format: 'esm',
    write: false,
    plugins: [
      {
        name: 'native',
        setup(b) {
          b.onResolve({ filter: /^(react|@lody-ios\/kit)$/ }, ({ path }) => ({
            path,
            namespace: 'mock',
          }));
          b.onLoad({ filter: /.*/, namespace: 'mock' }, ({ path }) => ({
            contents:
              path === 'react'
                ? 'export function useSyncExternalStore() {}'
                : 'export const {readOutboxRaw,addOutboxListener,outboxPut,outboxRemove,localStoreGeneration,readLocalValue,writeLocalValue}=globalThis.__outboxNative;',
          }));
        },
      },
    ],
  });
  const { getPendingSendStore } = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );
  const store = getPendingSendStore('u', 'w');
  let notified = 0;
  const unsubscribe = store.subscribe(() => notified++);
  assert.deepEqual(store.getSnapshot(), { records: [], ready: false });

  const draft = record('new');
  const put = store.put(draft);
  draft.send.text = 'mutated outside store';
  assert.equal(store.getSnapshot().records[0].send.text, 'hello');
  assert.equal(native.calls[0][3].send.text, 'hello');
  assert.equal(notified, 1);

  native.ready = true;
  native.records = [record('old', 'unknown')];
  emit();
  assert.deepEqual(
    store.getSnapshot().records.map((item) => item.session.id),
    ['old', 'new'],
    'an unacknowledged put stays visible over a native snapshot that predates it',
  );
  assert.equal(store.getSnapshot().ready, true);
  native.records = [record('old', 'unknown'), record('new', 'sending')];
  pending.shift().resolve();
  await put;
  assert.deepEqual(
    store.getSnapshot().records.map((item) => item.send.phase),
    ['unknown', 'sending'],
    'the native owner wins once it acknowledges the write',
  );

  const failed = store.put(record('failed-write'));
  pending.shift().reject(new Error('disk full'));
  await assert.rejects(failed, /disk full/);
  assert.equal(
    store
      .getSnapshot()
      .records.some((item) => item.session.id === 'failed-write'),
    false,
  );
  await store.remove('old');
  assert.deepEqual(native.calls.at(-1), ['remove', 'u', 'w', 'old']);
  assert.deepEqual(
    store.getSnapshot().records.map((item) => item.session.id),
    ['new'],
  );

  assert.deepEqual(getPendingSendStore('', 'w').getSnapshot(), {
    records: [],
    ready: true,
  });
  await assert.rejects(
    getPendingSendStore('', 'w').put(record('x')),
    /scope_expired/,
  );
  assert.notEqual(getPendingSendStore('other', 'w'), store);
  native.generation++;
  const calls = native.calls.length;
  await assert.rejects(store.put(record('stale')), /scope_expired/);
  assert.equal(
    native.calls.length,
    calls,
    'an expired scope never reaches native',
  );
  assert.notEqual(getPendingSendStore('u', 'w'), store);
  unsubscribe();
  assert.equal(listeners.size, 0);
  delete globalThis.__outboxNative;
});
