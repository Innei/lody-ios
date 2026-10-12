import assert from 'node:assert/strict';
import { test } from 'node:test';
import { build } from 'esbuild';
import { Flock } from '@loro-dev/flock-wasm/base64';
import { LoroDoc, LoroMap } from 'loro-crdt/base64';
import {
  sessionForkDocumentResult,
  sessionForkResponseResult,
} from '../../../../packages/cloud-runtime/src/models/session-tools.ts';

const bundle = await build({
  entryPoints: [
    new URL(
      '../../../../packages/cloud-runtime/src/runtime/session-tools.ts',
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
      setup(builder) {
        builder.onResolve({ filter: /^@loro-dev\/streams-client$/ }, () => ({
          path: 'streams',
          namespace: 'test',
        }));
        builder.onLoad({ filter: /.*/, namespace: 'test' }, () => ({
          contents:
            'export class StreamsClient { constructor(args) { return new globalThis.__toolsClient(args); } }',
        }));
      },
    },
  ],
});
const { sessionTools, requestSessionFork } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);
const target = '8d5cf060-29f3-42c5-bf78-3791d4569623';
const spec = {
  sourceSessionId: 'source',
  sourceTurnId: 'assistant-1',
  targetSessionId: target,
  requestedByUserId: 'user',
  targetContext: { kind: 'new-worktree' },
};
const operation = {
  id: `session-fork:${target}`,
  sourceSessionId: 'source',
  sourceTurnId: 'assistant-1',
  requestedByUserId: 'user',
  targetContext: 'new-worktree',
  state: 'preparing',
  phase: 'preparing-worktree',
  createdAt: '2026-10-12T00:00:00Z',
  updatedAt: '2026-10-12T00:00:00Z',
};
const document = {
  session: { id: target },
  history: [
    {
      id: `session-fork-origin:${target}`,
      items: [
        {
          type: 'system_notice',
          name: 'session_fork_origin',
          meta: { sourceSessionId: 'source' },
        },
      ],
    },
  ],
};

test('fork waits for the real preparing operation, and completes only after the cleared operation plus origin', () => {
  assert.equal(
    sessionForkDocumentResult(
      { ...document, forkOperation: operation },
      target,
      'source',
    ).state,
    'preparing',
  );
  assert.equal(
    sessionForkDocumentResult(
      {
        ...document,
        forkOperation: {
          ...operation,
          state: 'failed',
          error: { code: 'SETUP_FAILED', message: 'Setup failed' },
        },
      },
      target,
      'source',
    ).state,
    'failed',
  );
  assert.equal(
    sessionForkDocumentResult(
      { ...document, forkOperation: {} },
      target,
      'source',
    ).state,
    'completed',
  );
  for (const data of [
    { session: { id: target }, history: [] },
    { ...document, session: { id: 'other' } },
    { ...document, forkOperation: { ...operation, sourceSessionId: 'other' } },
    { ...document, forkOperation: { ...operation, state: 'completed' } },
    { ...document, forkOperation: 'malformed' },
    {
      ...document,
      history: [
        { ...document.history[0], id: 'session-fork-origin:older-source-fork' },
      ],
    },
  ])
    assert.equal(
      sessionForkDocumentResult(data, target, 'source').state,
      'unknown',
    );
});

test('a lost fork response never replays the write; dirty confirmation keeps the requested target', async () => {
  let attempts = 0;
  const result = await requestSessionFork(spec, async () => {
    attempts++;
    throw new Error('lost ACK');
  });
  assert.equal(result.state, 'unknown');
  assert.equal(result.targetSessionId, target);
  assert.equal(attempts, 1);
  const response = {
    type: 'session/fork_response',
    sourceSessionId: 'source',
    targetSessionId: target,
    success: false,
    partial: false,
    warnings: [],
    disposition: 'confirmation-required',
    reason: 'SOURCE_WORKTREE_DIRTY',
    error: { code: 'SOURCE_WORKTREE_DIRTY', message: 'Dirty source' },
  };
  assert.equal(
    sessionForkResponseResult(response, spec).state,
    'confirmation-required',
  );
  assert.equal(
    sessionForkResponseResult({ ...response, targetSessionId: 'other' }, spec)
      .state,
    'unknown',
  );
  assert.equal(
    sessionForkResponseResult(
      { ...response, disposition: 'failed', reason: undefined },
      spec,
    ).state,
    'failed',
  );
});

function fixture() {
  const flock = new Flock('tools-source'),
    remote = new Flock('tools-remote'),
    machine = new Flock('tools-machine');
  flock.set(['m', 'session-source'], {
    id: 'source',
    machineId: 'machine',
    agentConfigId: 'agent',
    acpSessionId: 'acp-session',
    isArchived: false,
    isPinned: true,
    title: 'Original',
    lastMessageAt: 100,
    lastReadAt: 250,
    project: { kind: 'local', localProjectId: 'project' },
  });
  flock.commit();
  remote.importFile(flock.exportFile());
  machine.set(['acpCapability', 'agent'], {
    provenance: 'runtime',
    sessionFork: true,
    sessionForkWorktree: true,
  });
  machine.commit();
  const doc = new LoroDoc();
  const history = doc.getList('history');
  const user = history.pushContainer(new LoroMap());
  user.set('id', 'user-1');
  user.set('role', 'user');
  const assistant = history.pushContainer(new LoroMap());
  assistant.set('id', 'assistant-1');
  assistant.set('role', 'assistant');
  assistant.set('acpTurnId', 'acp-turn');
  doc.commit();
  let failed = false,
    appends = 0;
  const context = {
    workspaceId: 'workspace',
    userId: 'user',
    machines: new Map([['machine', machine]]),
    meta: {
      flock,
      client: {
        async append({ part }) {
          appends++;
          if (failed) throw new Error('offline');
          remote.importJson(
            JSON.parse(new TextDecoder().decode(part.body.subarray(4))),
          );
          return { ok: true };
        },
      },
    },
    sessionDoc: () => doc,
    getGrant: async () => ({
      token: 'fixture',
      gatewayBaseUrl: 'https://example.invalid',
    }),
  };
  return {
    context,
    flock,
    remote,
    machine,
    doc,
    fail: () => {
      failed = true;
    },
    appends: () => appends,
  };
}

test('content pin saves the existing user entry and leaves history and list pin alone', async () => {
  const { context, flock, remote, doc } = fixture();
  const before = doc.toJSON();
  await sessionTools(
    {
      action: 'pin',
      workspaceId: 'workspace',
      sessionId: 'source',
      historyId: 'user-1',
    },
    context,
  );
  assert.equal(
    remote.get(['m', 'session-source', 'pinnedHistoryId']),
    'user-1',
  );
  assert.equal(flock.get(['m', 'session-source']).isPinned, true);
  assert.deepEqual(doc.toJSON(), before);
  await assert.rejects(
    sessionTools(
      {
        action: 'pin',
        workspaceId: 'workspace',
        sessionId: 'source',
        historyId: 'assistant-1',
      },
      context,
    ),
    /history_not_found/,
  );
  await sessionTools(
    {
      action: 'pin',
      workspaceId: 'workspace',
      sessionId: 'source',
      historyId: null,
    },
    context,
  );
  assert.equal(remote.get(['m', 'session-source', 'pinnedHistoryId']), '');
});

test('archived history keeps content pin and unpin available without restoring the session', async () => {
  const { context, flock, remote } = fixture();
  flock.set(['m', 'session-source', 'isArchived'], true);
  await sessionTools(
    {
      action: 'pin',
      workspaceId: 'workspace',
      sessionId: 'source',
      historyId: 'user-1',
    },
    context,
  );
  assert.equal(
    remote.get(['m', 'session-source', 'pinnedHistoryId']),
    'user-1',
  );
  await sessionTools(
    {
      action: 'pin',
      workspaceId: 'workspace',
      sessionId: 'source',
      historyId: null,
    },
    context,
  );
  assert.equal(remote.get(['m', 'session-source', 'pinnedHistoryId']), '');
  assert.equal(flock.get(['m', 'session-source', 'isArchived']), true);
});

test('explicit unread may lower the receipt without advancing activity or changing list pin', async () => {
  const { context, flock, remote } = fixture();
  await sessionTools(
    { action: 'unread', workspaceId: 'workspace', sessionId: 'source' },
    context,
  );
  assert.equal(flock.get(['m', 'session-source', 'lastReadAt']), 99);
  assert.equal(remote.get(['m', 'session-source', 'lastReadAt']), 99);
  assert.equal(flock.get(['m', 'session-source']).lastMessageAt, 100);
  assert.equal(flock.get(['m', 'session-source']).isPinned, true);
});

test('failed metadata writes keep the live receipt and pin; account fencing prevents the append', async () => {
  const value = fixture();
  value.fail();
  await assert.rejects(
    sessionTools(
      { action: 'unread', workspaceId: 'workspace', sessionId: 'source' },
      value.context,
    ),
    /offline/,
  );
  assert.equal(value.flock.get(['m', 'session-source']).lastReadAt, 250);
  assert.equal(
    value.flock.get(['m', 'session-source', 'lastReadAt']),
    undefined,
  );
  await assert.rejects(
    sessionTools(
      {
        action: 'pin',
        workspaceId: 'workspace',
        sessionId: 'source',
        historyId: 'user-1',
      },
      value.context,
    ),
    /offline/,
  );
  assert.equal(
    value.flock.get(['m', 'session-source', 'pinnedHistoryId']),
    undefined,
  );
  const fresh = fixture();
  fresh.context.assertCurrent = () => {
    throw new Error('account_changed');
  };
  await assert.rejects(
    sessionTools(
      { action: 'unread', workspaceId: 'workspace', sessionId: 'source' },
      fresh.context,
    ),
    /account_changed/,
  );
  assert.equal(fresh.appends(), 0);
});

test('fork destinations require the source agent runtime capability and archived sources reject writes', async () => {
  const { context, flock, machine } = fixture();
  const read = {
    action: 'fork-options',
    workspaceId: 'workspace',
    sessionId: 'source',
  };
  assert.equal((await sessionTools(read, context)).newWorktree, true);
  machine.set(['acpCapability', 'agent'], {
    provenance: 'probe',
    sessionFork: true,
    sessionForkWorktree: true,
  });
  assert.equal((await sessionTools(read, context)).shared, false);
  flock.set(['m', 'session-source', 'isArchived'], true);
  await assert.rejects(
    sessionTools({ ...read, action: 'fork', spec }, context),
    /session_archived/,
  );
  await assert.rejects(
    sessionTools(
      {
        ...read,
        action: 'fork',
        spec: { ...spec, requestedByUserId: 'other' },
      },
      context,
    ),
    /invalid_fork/,
  );
});

test('an abort after hydrating the request client prevents the Machine RPC append', async () => {
  const { context } = fixture();
  const controller = new AbortController();
  context.signal = controller.signal;
  let dispatches = 0;
  globalThis.__toolsClient = class {
    constructor({ url }) {
      if (decodeURIComponent(url).includes(':rpc:req:')) controller.abort();
    }
    async create() {
      return { ok: true };
    }
    async append() {
      dispatches++;
      return { ok: true };
    }
  };
  const result = await sessionTools(
    { action: 'fork', workspaceId: 'workspace', sessionId: 'source', spec },
    context,
  );
  assert.equal(result.fork.state, 'unknown');
  assert.equal(dispatches, 0);
});
