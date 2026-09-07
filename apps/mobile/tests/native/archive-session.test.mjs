import assert from 'node:assert/strict';
import { test } from 'node:test';
import { build } from 'esbuild';
import { Flock } from '@loro-dev/flock-wasm/base64';

const bundle = await build({
  entryPoints: [
    new URL(
      '../../modules/lody-kit/data-runtime/archive-session.ts',
      import.meta.url,
    ).pathname,
  ],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  write: false,
  plugins: [
    {
      name: 'streams',
      setup(b) {
        b.onResolve({ filter: /^@loro-dev\/streams-client$/ }, () => ({
          path: 'mock',
          namespace: 'test',
        }));
        b.onLoad({ filter: /.*/, namespace: 'test' }, () => ({
          contents:
            'export class StreamsClient { constructor(args) { return new globalThis.__archiveClient(args); } }',
        }));
      },
    },
  ],
});
const { archiveSession, pinSession } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);
const unframe = (body) =>
  JSON.parse(new TextDecoder().decode(body.subarray(4)));

test('archive writes the machine command after the session meta; restore clears it', async () => {
  const meta = new Flock('meta'),
    machine = new Flock('machine'),
    remoteMeta = new Flock('remote-meta'),
    remoteMachine = new Flock('remote-machine');
  meta.set(['m', 'session-s1'], {
    id: 's1',
    machineId: 'm1',
    status: { type: 'running' },
    isArchived: false,
  });
  remoteMeta.importFile(meta.exportFile());
  const urls = [];
  globalThis.__archiveClient = class {
    constructor({ url }) {
      this.url = decodeURIComponent(url);
    }
    async append({ part }) {
      urls.push(this.url);
      remoteMachine.importJson(unframe(part.body));
      return { ok: true, result: {} };
    }
  };
  const replica = {
    flock: meta,
    client: {
      async append({ part }) {
        urls.push('meta');
        remoteMeta.importJson(unframe(part.body));
        return { ok: true, result: {} };
      },
    },
  };
  const grant = async () => ({ token: 't', gatewayBaseUrl: 'https://x' });
  const machines = new Map([['m1', machine]]);
  await assert.rejects(
    archiveSession(
      { workspaceId: 'w1', sessionId: 'missing', archived: true },
      replica,
      machines,
      grant,
    ),
    /session_not_found/,
  );
  await archiveSession(
    { workspaceId: 'w1', sessionId: 's1', archived: true },
    replica,
    machines,
    grant,
  );
  assert.deepEqual(urls, ['meta', 'https://x/ds/lody/w1:mf:m1']);
  assert.equal(remoteMeta.get(['m', 'session-s1', 'isArchived']), true);
  assert.deepEqual(remoteMeta.get(['m', 'session-s1', 'status']), {
    type: 'idle',
  });
  assert.equal(remoteMeta.get(['m', 'session-s1']).id, 's1');
  assert.equal(remoteMachine.get(['cmd', 'archiveSession', 's1']).v, 1);
  assert.equal(machine.get(['cmd', 'archiveSession', 's1']).v, 1);
  await archiveSession(
    { workspaceId: 'w1', sessionId: 's1', archived: false },
    replica,
    machines,
    grant,
  );
  assert.equal(meta.get(['m', 'session-s1', 'isArchived']), false);
  assert.equal(machine.get(['cmd', 'archiveSession', 's1']), undefined);
  assert.equal(remoteMachine.get(['cmd', 'archiveSession', 's1']), undefined);
  await pinSession({ sessionId: 's1', pinned: true }, replica);
  assert.equal(remoteMeta.get(['m', 'session-s1', 'isPinned']), true);
  await assert.rejects(
    pinSession({ sessionId: 'missing', pinned: true }, replica),
    /session_not_found/,
  );
});
