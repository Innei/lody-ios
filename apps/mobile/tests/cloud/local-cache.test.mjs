import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { catalogKey } from '../../src/cloud/catalog/persist.ts';

test('logout drains in-flight persistence and cancels queued old-account writes', async () => {
  const db = new Map();
  let release;
  globalThis.__localTestKit = {
    readLocalValue: async (key) => db.get(key) ?? null,
    writeLocalValue: async (key, value) => {
      if (key === 'in-flight')
        await new Promise((resolve) => {
          release = resolve;
        });
      db.set(key, value);
    },
    clearLocalValues: async () => db.clear(),
  };
  const bundle = await build({
    entryPoints: ['apps/mobile/src/cloud/kv.ts'],
    bundle: true,
    format: 'esm',
    write: false,
    plugins: [
      {
        name: 'native-store',
        setup(build) {
          build.onResolve({ filter: /^@lody-ios\/kit$/ }, () => ({
            path: 'kit',
            namespace: 'test',
          }));
          build.onLoad({ filter: /.*/, namespace: 'test' }, () => ({
            contents:
              'export const {readLocalValue, writeLocalValue, clearLocalValues} = globalThis.__localTestKit;',
          }));
        },
      },
    ],
  });
  const store = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );
  const oldGeneration = store.localGeneration();
  const first = store.writeLocal('in-flight', 'old');
  await Promise.resolve();
  const queued = store.writeLocal('queued', 'old');
  const clear = store.clearLocal();
  const nextAccount = store.writeLocal('account', 'new');
  release();
  await Promise.all([first, queued, clear, nextAccount]);
  await store.writeLocal('late-event', 'old', oldGeneration);
  assert.deepEqual([...db.keys()], ['account']);
  assert.equal(await store.readLocal('account'), 'new');
  db.set('corrupt', '{');
  assert.equal(await store.readLocal('corrupt'), null);
  assert.notEqual(catalogKey('a', 'workspace'), catalogKey('b', 'workspace'));
  delete globalThis.__localTestKit;
});
