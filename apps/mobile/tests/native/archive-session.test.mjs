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
const { archiveSession, pinSession, markSessionRead } = await import(
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

test('mark read writes lastReadAt onto the session meta', async () => {
  const meta = new Flock('meta'),
    remoteMeta = new Flock('remote-meta');
  meta.set(['m', 'session-s1'], {
    id: 's1',
    machineId: 'm1',
    lastMessageAt: 100,
  });
  remoteMeta.importFile(meta.exportFile());
  const replica = {
    flock: meta,
    client: {
      async append({ part }) {
        remoteMeta.importJson(unframe(part.body));
        return { ok: true, result: {} };
      },
    },
  };
  await markSessionRead({ sessionId: 's1', lastReadAt: 250 }, replica);
  assert.equal(remoteMeta.get(['m', 'session-s1', 'lastReadAt']), 250);
  assert.equal(meta.get(['m', 'session-s1', 'lastReadAt']), 250);
  await markSessionRead({ sessionId: 's1', lastReadAt: 200 }, replica);
  assert.equal(meta.get(['m', 'session-s1', 'lastReadAt']), 250);
  await assert.rejects(
    markSessionRead({ sessionId: 'missing', lastReadAt: 1 }, replica),
    /session_not_found/,
  );
  await assert.rejects(
    markSessionRead({ sessionId: 's1', lastReadAt: Number.NaN }, replica),
    /invalid_session/,
  );
});

test('archive lands on the session even when the machine flock is unavailable', async () => {
  const meta = new Flock('meta'),
    remoteMeta = new Flock('remote-meta');
  meta.set(['m', 'session-s2'], {
    id: 's2',
    machineId: 'gone',
    isArchived: false,
  });
  globalThis.__archiveClient = class {
    async append() {
      throw new Error('offline');
    }
  };
  const replica = {
    flock: meta,
    client: {
      async append({ part }) {
        remoteMeta.importJson(unframe(part.body));
        return { ok: true, result: {} };
      },
    },
  };
  const grant = async () => ({ token: 't', gatewayBaseUrl: 'https://x' });
  await archiveSession(
    { workspaceId: 'w1', sessionId: 's2', archived: true },
    replica,
    new Map(),
    grant,
  );
  assert.equal(remoteMeta.get(['m', 'session-s2', 'isArchived']), true);
  const machine = new Flock('machine');
  await archiveSession(
    { workspaceId: 'w1', sessionId: 's2', archived: false },
    replica,
    new Map([['gone', machine]]),
    grant,
  );
  assert.equal(remoteMeta.get(['m', 'session-s2', 'isArchived']), false);
  assert.equal(machine.get(['cmd', 'archiveSession', 's2']), undefined);
});

test('archive and pin accept field-level session metadata', async () => {
  const meta = new Flock('meta'),
    machine = new Flock('machine'),
    remoteMeta = new Flock('remote-meta'),
    remoteMachine = new Flock('remote-machine');
  meta.put(['e', 'session-s3'], true);
  meta.put(['m', 'session-s3', 'id'], 's3');
  meta.put(['m', 'session-s3', 'machineId'], 'm1');
  meta.put(['m', 'session-s3', 'isArchived'], false);
  meta.put(['m', 'session-s3', 'status'], { type: 'running' });
  meta.commit();
  remoteMeta.importFile(meta.exportFile());
  globalThis.__archiveClient = class {
    constructor({ url }) {
      this.url = decodeURIComponent(url);
    }
    async append({ part }) {
      remoteMachine.importJson(unframe(part.body));
      return { ok: true, result: {} };
    }
  };
  const replica = {
    flock: meta,
    client: {
      async append({ part }) {
        remoteMeta.importJson(unframe(part.body));
        return { ok: true, result: {} };
      },
    },
  };
  const grant = async () => ({ token: 't', gatewayBaseUrl: 'https://x' });
  await pinSession({ sessionId: 's3', pinned: true }, replica);
  assert.equal(remoteMeta.get(['m', 'session-s3', 'isPinned']), true);
  assert.equal(remoteMeta.get(['m', 'session-s3']), undefined);
  await archiveSession(
    { workspaceId: 'w1', sessionId: 's3', archived: true },
    replica,
    new Map([['m1', machine]]),
    grant,
  );
  assert.equal(remoteMeta.get(['m', 'session-s3', 'isArchived']), true);
  assert.deepEqual(remoteMeta.get(['m', 'session-s3', 'status']), {
    type: 'idle',
  });
  assert.equal(remoteMeta.get(['m', 'session-s3']), undefined);
  assert.equal(remoteMachine.get(['cmd', 'archiveSession', 's3']).v, 1);
  assert.equal(machine.get(['cmd', 'archiveSession', 's3']).v, 1);
});

test('archive cascades to child sessions and only queues the root machine command', async () => {
  const meta = new Flock('meta'),
    machine = new Flock('machine'),
    remoteMeta = new Flock('remote-meta'),
    remoteMachine = new Flock('remote-machine');
  for (const [room, fields] of [
    ['session-root', { id: 'root', machineId: 'm1' }],
    [
      'session-child',
      { id: 'child', machineId: 'm1', parentSessionId: 'root' },
    ],
  ]) {
    meta.put(['e', room], true);
    for (const [key, value] of Object.entries(fields))
      meta.put(['m', room, key], value);
  }
  meta.commit();
  remoteMeta.importFile(meta.exportFile());
  globalThis.__archiveClient = class {
    async append({ part }) {
      remoteMachine.importJson(unframe(part.body));
      return { ok: true, result: {} };
    }
  };
  const replica = {
    flock: meta,
    client: {
      async append({ part }) {
        remoteMeta.importJson(unframe(part.body));
        return { ok: true, result: {} };
      },
    },
  };
  const grant = async () => ({ token: 't', gatewayBaseUrl: 'https://x' });
  await archiveSession(
    { workspaceId: 'w1', sessionId: 'root', archived: true },
    replica,
    new Map([['m1', machine]]),
    grant,
  );
  assert.equal(remoteMeta.get(['m', 'session-root', 'isArchived']), true);
  assert.equal(remoteMeta.get(['m', 'session-child', 'isArchived']), true);
  assert.equal(machine.get(['cmd', 'archiveSession', 'root']).v, 1);
  assert.equal(machine.get(['cmd', 'archiveSession', 'child']), undefined);
  await archiveSession(
    { workspaceId: 'w1', sessionId: 'root', archived: false },
    replica,
    new Map([['m1', machine]]),
    grant,
  );
  assert.equal(remoteMeta.get(['m', 'session-root', 'isArchived']), false);
  assert.equal(remoteMeta.get(['m', 'session-child', 'isArchived']), false);
  assert.equal(machine.get(['cmd', 'archiveSession', 'root']), undefined);
});

test('archive records needToArchiveSessions on machine meta', async () => {
  const meta = new Flock('meta'),
    remoteMeta = new Flock('remote-meta');
  meta.put(['e', 'session-s4'], true);
  meta.put(['e', 'machine-m1'], true);
  meta.put(['m', 'session-s4', 'id'], 's4');
  meta.put(['m', 'session-s4', 'machineId'], 'm1');
  meta.commit();
  remoteMeta.importFile(meta.exportFile());
  const replica = {
    flock: meta,
    client: {
      async append({ part }) {
        remoteMeta.importJson(unframe(part.body));
        return { ok: true, result: {} };
      },
    },
  };
  const grant = async () => ({ token: 't', gatewayBaseUrl: 'https://x' });
  await archiveSession(
    { workspaceId: 'w1', sessionId: 's4', archived: true },
    replica,
    new Map(),
    grant,
  );
  assert.deepEqual(
    remoteMeta.get(['m', 'machine-m1', 'needToArchiveSessions']),
    { s4: true },
  );
  await archiveSession(
    { workspaceId: 'w1', sessionId: 's4', archived: false },
    replica,
    new Map(),
    grant,
  );
  assert.deepEqual(
    remoteMeta.get(['m', 'machine-m1', 'needToArchiveSessions']),
    {},
  );
});
