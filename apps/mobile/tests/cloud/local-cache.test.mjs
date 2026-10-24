import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';

test('writes carry the generation they were issued under so native drops old-account writes', async () => {
  const db = new Map();
  let generation = 0;
  globalThis.__localTestKit = {
    readLocalValue: async (key) => db.get(key) ?? null,
    writeLocalValue: async (key, value, expected) => {
      if (expected === generation) db.set(key, value);
    },
    localStoreGeneration: () => generation,
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
              'export const {readLocalValue, writeLocalValue, localStoreGeneration} = globalThis.__localTestKit;',
          }));
        },
      },
    ],
  });
  const store = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );
  const oldGeneration = store.localGeneration();
  db.clear();
  generation++;
  await store.writeLocal('account', 'new');
  await store.writeLocal('late-event', 'old', oldGeneration);
  assert.deepEqual([...db.keys()], ['account']);
  assert.equal(await store.readLocal('account'), 'new');
  db.set('corrupt', '{');
  assert.equal(await store.readLocal('corrupt'), null);
  delete globalThis.__localTestKit;
});
