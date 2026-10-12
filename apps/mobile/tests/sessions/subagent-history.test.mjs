import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { LoroDoc, LoroList, LoroMap } from 'loro-crdt/base64';

async function moduleAt(path, native = false) {
  const bundle = await build({
    entryPoints: [path],
    bundle: true,
    format: 'esm',
    platform: 'browser',
    write: false,
    plugins: [
      {
        name: 'shared-loro',
        setup(b) {
          if (native) {
            b.onResolve({ filter: /^@lody-ios\/kit$/ }, () => ({
              path: 'kit',
              namespace: 'subagent-test',
            }));
            b.onLoad({ filter: /.*/, namespace: 'subagent-test' }, () => ({
              contents: `
          export const subagentHistory = payload => globalThis.__subagentBridge(payload);
          export const addDataRuntimeListener = callback => globalThis.__subagentListener(callback);
        `,
            }));
          }
          b.onResolve({ filter: /^loro-crdt\/base64$/ }, () => ({
            path: pathToFileURL(
              createRequire(import.meta.url).resolve('loro-crdt/base64'),
            ).href,
            external: true,
          }));
        },
      },
    ],
  });
  return import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );
}
const runtime = await moduleAt(
  'packages/cloud-runtime/src/runtime/subagent-history.ts',
);
const { createSubagentHistoryController } = await moduleAt(
  'apps/mobile/src/features/subagent-history/controller.ts',
);
const { subagentTranscript } = await moduleAt(
  'apps/mobile/src/features/subagent-history/transcript.ts',
);
const { readSubagentRunMetadata } = await moduleAt(
  'packages/cloud-runtime/src/protocol/subagent-history.ts',
);
const pause = (ms = 130) => new Promise((resolve) => setTimeout(resolve, ms));
const deferred = () => {
  let resolve;
  const promise = new Promise((done) => {
    resolve = done;
  });
  return { promise, resolve };
};
const snapshot = (state = 'running', extra = {}) => ({
  state,
  support: {
    stream: ['text', 'thought', 'tool', 'plan'],
    progress: true,
    outputRead: 'none',
    cancel: false,
  },
  ...extra,
});
const run = (items, state = 'running', extra = {}) => ({
  sessionId: 'acp-root',
  snapshot: snapshot(state, extra),
  items,
});

function fixture(items, state = 'running') {
  const doc = new LoroDoc();
  const history = doc.getList('history');
  const entry = history.pushContainer(new LoroMap());
  entry.set('id', 'parent-reply');
  entry.set('role', 'assistant');
  entry.set('userTurnId', 'parent-turn');
  const tasks = entry.setContainer('items', new LoroList());
  const task = tasks.pushContainer(new LoroMap());
  task.set('type', 'subagent_task');
  task.set('taskId', 'run-one');
  task.set('toolUseId', 'spawn');
  task.set('status', state === 'running' ? 'in_progress' : state);
  task.set('summary', 'A retained result');
  task.set('run', run(items, state));
  doc.commit();
  const id = tasks.getIdAt(0);
  const identity = {
    sessionId: 'parent-session',
    parentTurnId: 'parent-turn',
    entryId: 'parent-reply',
    itemId: `${id.peer}:${id.counter}`,
    taskId: 'run-one',
    runSessionId: 'acp-root',
  };
  return { doc, task, tasks, identity };
}

test('retained native execution records bind their exact parent, run and tool detail without inventing user messages', () => {
  const items = [
    {
      type: 'text',
      text: '## First reply',
      nativeTurnId: 'child-turn',
      messageId: 'child-message',
    },
    {
      type: 'thought',
      text: 'Inspecting the source',
      nativeTurnId: 'child-turn',
    },
    {
      type: 'plan',
      entries: [{ content: 'Read the source', status: 'completed' }],
      nativeTurnId: 'child-turn',
    },
    {
      type: 'tool_call',
      toolCallId: 'child-tool',
      kind: 'execute',
      title: 'Run check',
      status: 'completed',
      rawInput: { command: 'check' },
      content: [
        {
          type: 'terminal_output',
          output: 'PASS',
          exitStatus: { exitCode: 0 },
        },
      ],
      permissionRequest: { requestId: 'invalid-child-request', options: [] },
      nativeTurnId: 'child-turn',
    },
  ];
  const f = fixture(items, 'completed');
  const page = runtime.readSubagentHistory(f.doc, f.identity);
  assert.equal(page.status, 'ready');
  assert.equal(page.fragments.length, 4);
  assert.equal(
    page.fragments[3].item.permission,
    undefined,
    'Read-only run steps never expose approval actions',
  );
  const entries = subagentTranscript(
    f.identity.taskId,
    page.fragments,
    page.task.run.snapshot.state,
  );
  assert.equal(entries.length, 1);
  assert.equal(
    entries[0].role,
    'assistant',
    'Normalized v1 provides no child user message',
  );
  assert.equal(entries[0].finished, true);
  const detail = runtime.readSubagentDetail(f.doc, f.identity, 3);
  assert.deepEqual(detail.blocks, items[3].content);
  assert.deepEqual(detail.rawInput, items[3].rawInput);
  assert.equal(detail.itemId, 'child-tool');
  for (const patch of [
    { parentTurnId: 'another-turn' },
    { entryId: 'another-entry' },
    { itemId: 'another-item' },
    { taskId: 'another-run' },
    { runSessionId: 'another-root' },
  ])
    assert.throws(
      () => runtime.readSubagentHistory(f.doc, { ...f.identity, ...patch }),
      /subagent_run_not_found/,
    );
  assert.throws(
    () => runtime.readSubagentDetail(f.doc, f.identity, 0),
    /subagent_item_not_found/,
  );
});

test('paging preserves all older records and long Unicode text while run cursors cannot cross executions', () => {
  const text = '😀'.repeat(50000) + '\nLast line';
  const items = [
    ...Array.from({ length: 60 }, (_, index) => ({
      type: 'text',
      text: `Step ${index}`,
    })),
    { type: 'text', text },
  ];
  const f = fixture(items, 'completed');
  const first = runtime.readSubagentHistory(f.doc, f.identity);
  assert.equal(first.fragments.length, 1);
  assert.ok(first.nextCursor);
  assert.ok(first.fragments[0].item.text.endsWith('Last line'));
  let page = first;
  let fragments = page.fragments;
  while (page.nextCursor) {
    page = runtime.readSubagentHistory(f.doc, f.identity, page.nextCursor);
    fragments = [...page.fragments, ...fragments];
  }
  const entries = subagentTranscript(f.identity.taskId, fragments, 'completed');
  assert.deepEqual(
    entries[0].items.map((item) => item.text),
    items.map((item) => item.text),
  );
  assert.equal(page.nextCursor, undefined);
  const second = f.tasks.pushContainer(new LoroMap());
  second.set('type', 'subagent_task');
  second.set('taskId', 'run-two');
  second.set('toolUseId', 'spawn');
  second.set('status', 'failed');
  second.set(
    'run',
    run([{ type: 'text', text: 'Only the second execution' }], 'failed'),
  );
  f.doc.commit();
  const id = f.tasks.getIdAt(1);
  const identity = {
    ...f.identity,
    itemId: `${id.peer}:${id.counter}`,
    taskId: 'run-two',
  };
  const selected = runtime.readSubagentHistory(f.doc, identity);
  assert.equal(selected.runs.length, 2);
  assert.equal(selected.fragments[0].item.text, 'Only the second execution');
  assert.throws(
    () => runtime.readSubagentHistory(f.doc, identity, first.nextCursor),
    /invalid_subagent_cursor/,
  );
  assert.throws(
    () => runtime.readSubagentHistory(f.doc, f.identity, '{broken'),
    /invalid_subagent_cursor/,
  );
});

test('legacy, empty, malformed and incomplete observations remain distinct and metadata strips private extras', () => {
  const f = fixture([], 'unknown');
  f.task.set(
    'run',
    run([], 'unknown', {
      outputIncomplete: true,
      reason: {
        code: 'lost',
        message: 'Disconnected',
        secretToken: 'never-project',
      },
      secretToken: 'never-project',
    }),
  );
  f.doc.commit();
  const page = runtime.readSubagentHistory(f.doc, f.identity);
  assert.equal(page.status, 'ready');
  assert.equal(page.fragments.length, 0);
  assert.equal(page.incomplete, true);
  assert.equal(page.task.run.snapshot.state, 'unknown');
  const metadata = readSubagentRunMetadata({
    ...f.task.toJSON().run,
    progress: {
      totalTokens: null,
      durationMs: 20,
      privateConfig: 'never-project',
    },
    privateConfig: 'never-project',
  });
  assert.equal(metadata.progress.totalTokens, null);
  assert.equal(JSON.stringify(metadata).includes('never-project'), false);
  f.task.set('run', undefined);
  f.doc.commit();
  assert.equal(
    runtime.readSubagentHistory(f.doc, {
      ...f.identity,
      runSessionId: undefined,
    }).status,
    'unsupported',
  );
  f.task.set('run', {
    sessionId: 'acp-root',
    snapshot: { state: 'completed' },
    items: [],
  });
  f.doc.commit();
  assert.throws(
    () => runtime.readSubagentHistory(f.doc, f.identity),
    /invalid_subagent_run/,
  );
  assert.equal(readSubagentRunMetadata(f.task.toJSON().run), undefined);
});

test('the owned replica watcher coalesces changes and releases pending notifications on exit or stop', async () => {
  const f = fixture([{ type: 'text', text: 'Before' }]);
  const events = [];
  const owner = runtime.createSubagentHistoryRuntime({
    doc: (id) => (id === f.identity.sessionId ? f.doc : undefined),
    emit: (event) => events.push(event),
  });
  owner.execute({
    action: 'watch',
    subscriptionId: 'one',
    identity: f.identity,
  });
  f.task.set('run', run([{ type: 'text', text: 'After' }]));
  f.doc.commit();
  f.task.set('lastToolName', 'Read');
  f.doc.commit();
  await pause();
  assert.equal(events.length, 1);
  assert.equal(events[0].subscriptionId, 'one');
  assert.equal(
    owner.execute({ action: 'page', identity: f.identity }).fragments[0].item
      .text,
    'After',
  );
  f.task.set('summary', 'Final');
  f.doc.commit();
  owner.execute({ action: 'unwatch', subscriptionId: 'one' });
  await pause();
  assert.equal(events.length, 1);
  owner.execute({
    action: 'watch',
    subscriptionId: 'two',
    identity: f.identity,
  });
  owner.stop();
  f.task.set('summary', 'Later');
  f.doc.commit();
  await pause();
  assert.equal(events.length, 1);
  assert.throws(
    () =>
      owner.execute({
        action: 'page',
        identity: { ...f.identity, sessionId: 'missing' },
      }),
    /session_not_ready/,
  );
});

function serviceFor(f) {
  const signals = new Set();
  const released = [];
  const service = {
    watch: async (_id, identity) =>
      runtime.readSubagentHistory(f.doc, identity),
    page: async (identity, cursor) =>
      runtime.readSubagentHistory(f.doc, identity, cursor),
    detail: async (identity, index, cursor) =>
      runtime.readSubagentDetail(f.doc, identity, index, cursor),
    unwatch: async (id) => {
      released.push(id);
    },
    subscribe: (listener) => {
      signals.add(listener);
      return () => signals.delete(listener);
    },
  };
  return { service, signals, released };
}

test('switching while watch or pagination replies are delayed rejects stale content and closes both subscription races', async () => {
  const f = fixture(
    Array.from({ length: 50 }, (_, index) => ({
      type: 'text',
      text: `First ${index}`,
    })),
    'completed',
  );
  const second = f.tasks.pushContainer(new LoroMap());
  second.set('type', 'subagent_task');
  second.set('taskId', 'run-two');
  second.set('run', run([{ type: 'text', text: 'Second only' }], 'completed'));
  f.doc.commit();
  const id = f.tasks.getIdAt(1);
  const next = {
    ...f.identity,
    itemId: `${id.peer}:${id.counter}`,
    taskId: 'run-two',
  };
  const fake = serviceFor(f);
  const delayed = deferred();
  const watches = [];
  fake.service.watch = async (id, identity) => {
    watches.push(id);
    if (identity.taskId === 'run-one') await delayed.promise;
    return runtime.readSubagentHistory(f.doc, identity);
  };
  const controller = createSubagentHistoryController(fake.service);
  const first = controller.start(f.identity);
  await controller.select(next);
  delayed.resolve();
  await first;
  assert.equal(controller.getSnapshot().identity.taskId, 'run-two');
  assert.deepEqual(
    controller.getSnapshot().fragments.map((row) => row.item.text),
    ['Second only'],
  );
  assert.equal(
    fake.released.filter((id) => id === watches[0]).length,
    2,
    'Release before switching and after a late watch acknowledgement',
  );
  await controller.select(f.identity);
  const pendingPage = deferred();
  fake.service.page = async (identity, cursor) => {
    if (cursor) await pendingPage.promise;
    return runtime.readSubagentHistory(f.doc, identity, cursor);
  };
  const older = controller.loadMore();
  await controller.select(next);
  pendingPage.resolve();
  await older;
  assert.equal(controller.getSnapshot().fragments.length, 1);
  assert.equal(controller.getSnapshot().fragments[0].item.text, 'Second only');
  controller.dispose();
  assert.equal(fake.signals.size, 0);
  assert.ok(fake.released.includes(watches.at(-1)));
});

test('updates preserve loaded older pages, lost runtimes clear content, and a live replacement renews the watch', async () => {
  const f = fixture(
    Array.from({ length: 50 }, (_, index) => ({
      type: 'text',
      text: `Step ${index}`,
    })),
  );
  const fake = serviceFor(f);
  const watches = [];
  fake.service.watch = async (id, identity) => {
    watches.push(id);
    return runtime.readSubagentHistory(f.doc, identity);
  };
  const controller = createSubagentHistoryController(fake.service);
  await controller.start(f.identity);
  await controller.loadMore();
  await controller.loadMore();
  assert.equal(controller.getSnapshot().fragments.length, 50);
  f.task.set(
    'run',
    run(
      [
        ...f.task.toJSON().run.items,
        { type: 'text', text: 'Final live result' },
      ],
      'completed',
    ),
  );
  f.doc.commit();
  for (const signal of fake.signals)
    signal({
      subscriptionId: watches.at(-1),
      sessionId: f.identity.sessionId,
      subagentHistory: 'changed',
    });
  await pause(20);
  assert.equal(controller.getSnapshot().fragments.length, 51);
  assert.equal(
    controller.getSnapshot().page.task.run.snapshot.state,
    'completed',
  );
  assert.equal(controller.getSnapshot().page.nextCursor, undefined);
  for (const signal of fake.signals)
    signal({ state: 'stopped', generation: 2 });
  assert.equal(controller.getSnapshot().fragments.length, 0);
  assert.equal(controller.getSnapshot().status, 'failed');
  for (const signal of fake.signals)
    signal({
      sessionId: f.identity.sessionId,
      session: '{"status":"live"}',
      generation: 3,
    });
  await pause(20);
  assert.equal(watches.length, 2);
  assert.equal(controller.getSnapshot().status, 'ready');
  controller.dispose();
});

test('the production bridge wrapper captures account/workspace scope on every action and never adopts a later account', async () => {
  const f = fixture([{ type: 'text', text: 'Scoped record' }], 'completed');
  const calls = [];
  let currentUser = 'original-user';
  let listening = 0;
  globalThis.__subagentBridge = async (payload) => {
    const request = JSON.parse(payload);
    calls.push(request);
    if (
      request.workspaceId !== 'original-workspace' ||
      request.userId !== currentUser
    )
      throw new Error('metadata_not_ready');
    if (request.action === 'unwatch') return '{"state":"released"}';
    if (request.action === 'detail')
      return '{"itemId":"tool","rev":1,"blocks":[],"truncated":false}';
    return JSON.stringify(
      runtime.readSubagentHistory(f.doc, request.identity, request.cursor),
    );
  };
  globalThis.__subagentListener = () => {
    listening++;
    return {
      remove() {
        listening--;
      },
    };
  };
  try {
    const { createSubagentHistoryService } = await moduleAt(
      'apps/mobile/src/cloud/subagent-history.ts',
      true,
    );
    const scope = {
      workspaceId: 'original-workspace',
      userId: 'original-user',
    };
    const service = createSubagentHistoryService(scope);
    scope.userId = 'later-user';
    scope.workspaceId = 'later-workspace';
    await service.watch('owned-watch', f.identity);
    await service.page(f.identity);
    await service.detail(f.identity, 0);
    await service.unwatch('owned-watch');
    assert.deepEqual(
      calls.map((call) => call.action),
      ['watch', 'page', 'detail', 'unwatch'],
    );
    for (const call of calls) {
      assert.equal(call.workspaceId, 'original-workspace');
      assert.equal(call.userId, 'original-user');
    }
    const stop = service.subscribe(() => {});
    assert.equal(listening, 1);
    stop();
    assert.equal(listening, 0);
    currentUser = 'later-user';
    await assert.rejects(service.page(f.identity), /metadata_not_ready/);
    assert.equal(calls.at(-1).userId, 'original-user');
  } finally {
    delete globalThis.__subagentBridge;
    delete globalThis.__subagentListener;
  }
});

test('a partially synced parent pauses updates without discarding already read history or accepting old-generation events', async () => {
  const f = fixture(
    Array.from({ length: 40 }, (_, index) => ({
      type: 'text',
      text: `Retained ${index}`,
    })),
    'completed',
  );
  const fake = serviceFor(f);
  let ready = true;
  fake.service.watch = async (_id, identity) => {
    if (!ready) throw new Error('session_not_ready');
    return runtime.readSubagentHistory(f.doc, identity);
  };
  const controller = createSubagentHistoryController(fake.service);
  await controller.start(f.identity);
  await controller.loadMore();
  ready = false;
  for (const signal of fake.signals)
    signal({
      sessionId: f.identity.sessionId,
      session: '{"status":"syncing"}',
      generation: 2,
    });
  assert.equal(controller.getSnapshot().paused, true);
  assert.equal(controller.getSnapshot().fragments.length, 40);
  await controller.retry();
  assert.equal(controller.getSnapshot().status, 'failed');
  assert.equal(
    controller.getSnapshot().fragments.length,
    40,
    'Failed retry preserves the retained records',
  );
  for (const signal of fake.signals)
    signal({ state: 'stopped', generation: 1 });
  assert.equal(
    controller.getSnapshot().fragments.length,
    40,
    'A replaced runtime cannot clear a newer view',
  );
  ready = true;
  for (const signal of fake.signals)
    signal({
      sessionId: f.identity.sessionId,
      session: '{"status":"live"}',
      generation: 2,
    });
  await pause(20);
  assert.equal(controller.getSnapshot().status, 'ready');
  assert.equal(controller.getSnapshot().paused, undefined);
  assert.equal(
    controller.getSnapshot().fragments.length,
    40,
    'Recovery preserves loaded earlier pages',
  );
  controller.dispose();
});
