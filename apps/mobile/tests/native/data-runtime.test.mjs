import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { Flock } from '@loro-dev/flock-wasm/base64';

test('persistent runtime applies live increments to the existing replica and advances the cursor', async () => {
  const flock = new Flock('synthetic');
  flock.set(['e', 'session-s1'], true, 1);
  flock.set(['m', 'session-s1'], { title: 'Before', machineId: 'm1' }, 2);
  const snapshot = flock.exportFile(),
    version = flock.version();
  flock.set(['m', 'session-s1', 'title'], 'After', 3);
  const update = new TextEncoder().encode(
    JSON.stringify(flock.exportJson(version)),
  );
  const events = [];
  let nextEvent;
  const catalogEvent = () =>
    new Promise((resolve) => {
      nextEvent = resolve;
    });
  const requests = [];
  let respond;
  globalThis.__runtimeTestClient = class {
    async bootstrap() {
      return {
        ok: true,
        result: {
          snapshotOffset: '1',
          nextOffset: '1',
          upToDate: true,
          snapshot: { body: snapshot },
          updates: [],
        },
      };
    }
    readOnce(request) {
      requests.push(request);
      return new Promise((resolve) => {
        respond = resolve;
      });
    }
  };
  globalThis.webkit = {
    messageHandlers: {
      dataRuntime: {
        postMessage(event) {
          events.push(event);
          if (event.type === 'grant')
            queueMicrotask(() =>
              globalThis.dataRuntime.grant({
                token: 'synthetic',
                gatewayBaseUrl: 'https://example.invalid',
                expiresIn: 3600,
              }),
            );
          if (event.type === 'catalog') nextEvent?.(event);
        },
      },
    },
  };
  const bundle = await build({
    entryPoints: ['apps/mobile/modules/lody-kit/data-runtime/index.ts'],
    bundle: true,
    format: 'esm',
    platform: 'browser',
    write: false,
    plugins: [
      {
        name: 'synthetic-stream',
        setup(build) {
          build.onResolve({ filter: /^@loro-dev\/streams-client$/ }, () => ({
            path: 'client',
            namespace: 'test',
          }));
          build.onLoad({ filter: /.*/, namespace: 'test' }, () => ({
            contents:
              'export const StreamsClient = globalThis.__runtimeTestClient;',
          }));
        },
      },
    ],
  });
  await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );
  assert.deepEqual(
    await globalThis.dataRuntime.sendTurn({ sessionId: 's1', text: 'hello' }),
    { state: 'not_sent', reason: 'metadata_not_ready' },
  );
  const first = catalogEvent();
  globalThis.dataRuntime.start('synthetic-workspace');
  assert.equal(JSON.parse((await first).catalog).sessions[0].title, 'Before');
  assert.equal(requests[0].live, 'long-poll');
  const second = catalogEvent();
  respond({
    ok: true,
    result: {
      nextOffset: '2',
      upToDate: true,
      closed: false,
      payload: { body: update },
    },
  });
  const changed = await second;
  assert.equal(JSON.parse(changed.catalog).sessions[0].title, 'After');
  assert.equal(changed.revision, 2);
  assert.equal(requests[1].offset, '2');
  assert.equal(events.filter((e) => e.type === 'grant').length, 1);
  assert.equal(globalThis.dataRuntime.ping(), true);
  delete globalThis.webkit;
  delete globalThis.__runtimeTestClient;
  delete globalThis.dataRuntime;
});
