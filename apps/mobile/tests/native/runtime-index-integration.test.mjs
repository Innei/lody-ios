import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { Flock } from '@loro-dev/flock-wasm/base64';
import { encodeFrame } from '../../../../packages/cloud-runtime/src/frames.ts';

const modules = {
  'project-management':
    'export const projectManagement = (request, ctx) => globalThis.__indexIntegration.project(request, ctx);',
  providers: [
    'export const providersCommand = (request, ctx) => globalThis.__indexIntegration.provider(request, ctx);',
    'export const stopProviderOperations = ctx => globalThis.__indexIntegration.stopProvider(ctx);',
  ].join('\n'),
  'session-tools':
    'export const sessionTools = (request, ctx) => globalThis.__indexIntegration.tools(request, ctx);',
  schedules:
    'export const scheduleCommand = (request, ctx) => globalThis.__indexIntegration.schedule(request, ctx);',
  'prompt-shortcuts': [
    'export const promptShortcuts = (request, ctx) => globalThis.__indexIntegration.shortcut(request, ctx);',
    'export const shortcutMentionCatalog = (ctx, scope) => globalThis.__indexIntegration.shortcutCatalog(ctx, scope);',
    'export const expandShortcut = (id, ctx, scope) => globalThis.__indexIntegration.expand(id, ctx, scope);',
  ].join('\n'),
  'run-options': [
    'export const workspaceRunOptions = (request, machines, getGrant, signal, agentCatalog) => globalThis.__indexIntegration.options(request, machines, getGrant, signal, agentCatalog);',
    'export const resolveTurnRunOptions = (choice, previous, input, ctx) => globalThis.__indexIntegration.configure(choice, previous, input, ctx);',
  ].join('\n'),
  'subagent-history':
    'export const createSubagentHistoryRuntime = ({doc}) => ({execute: request => globalThis.__indexIntegration.subagent(request, doc), stop: () => globalThis.__indexIntegration.stops.push("subagents")});',
  'machine-presence': [
    'export const watchMachinePresence = (workspace, getGrant, emit) => { emit({state:"live",onlineMachineIds:["m1"]}); return () => emit({state:"unknown",onlineMachineIds:[]}); };',
    'export const availableCreationOptions = options => options;',
  ].join('\n'),
  session: [
    'const state = globalThis.__indexIntegration;',
    'export const releaseDeletedSessions = state.noop;',
    'export const sessionDoc = id => ({id});',
    'export const readySessionDoc = id => state.sessionReady ? ({id}) : undefined;',
    'export const openSession = state.noop;',
    'export const closeSession = state.noop;',
    'export const stopSessions = () => state.stops.push("sessions");',
    'export const ensureSession = state.noop;',
    'export const releaseReserve = state.noop;',
    'export const retainedSessionIds = () => [];',
    'export const reservedSessionIds = () => [];',
    'export const itemDetail = state.noop;',
    'export const respondPermission = state.noop;',
    'export const controlTurn = state.noop;',
    'export const checkTurnQuota = state.noop;',
    'export const editSession = state.noop;',
    'export const queueMessage = request => state.queue(request);',
    'export const checkSend = request => state.check(request);',
    'export const sendTurn = async (request, expand, configure) => ({state:"queued",text:await expand(request.text),config:await configure({}, {prompt:request.text})});',
  ].join('\n'),
};

async function runtimeBundle() {
  const bundle = await build({
    entryPoints: ['packages/cloud-runtime/src/runtime/index.ts'],
    bundle: true,
    format: 'esm',
    platform: 'browser',
    write: false,
    plugins: [
      {
        name: 'owned-runtime-boundaries',
        setup(builder) {
          builder.onResolve({ filter: /^\.\// }, (args) => {
            if (!args.importer.endsWith('/runtime/index.ts')) return;
            const name = args.path.replace(/^\.\//, '').replace(/\.ts$/, '');
            if (modules[name])
              return { path: name, namespace: 'index-boundary' };
          });
          builder.onLoad(
            { filter: /.*/, namespace: 'index-boundary' },
            (args) => ({ contents: modules[args.path] }),
          );
          builder.onResolve({ filter: /^@loro-dev\/streams-client$/ }, () => ({
            path: 'client',
            namespace: 'index-stream',
          }));
          builder.onLoad({ filter: /.*/, namespace: 'index-stream' }, () => ({
            contents: 'export const StreamsClient = globalThis.__indexClient;',
          }));
        },
      },
    ],
  });
  await import(
    'data:text/javascript;base64,' +
      Buffer.from(bundle.outputFiles[0].text).toString('base64')
  );
}

test('management commands retain healthy replicas and fence identity, teardown and native brokers', async (t) => {
  const meta = new Flock('index-meta');
  meta.set(['e', 'machine-m1'], true);
  meta.set(['m', 'machine-m1'], { name: 'Fixture Mac', ownerUserId: 'u1' });
  meta.set(['e', 'session-s1'], true);
  meta.set(['m', 'session-s1'], {
    id: 's1',
    machineId: 'm1',
    agentConfigId: 'a1',
    title: 'Fixture session',
    project: { kind: 'github', repoFullName: 'fixture/repo' },
    cliType: 'builtin',
    agentType: 'codex',
  });
  const machine = new Flock('index-machine');
  machine.set(['agentConfig', 'a1'], {
    id: 'a1',
    machineId: 'm1',
    name: 'Fixture assistant',
    cliType: 'builtin',
    agentType: 'codex',
  });
  const snapshots = { meta: meta.exportFile(), machine: machine.exportFile() };
  const events = [],
    calls = [],
    stops = [],
    held = new Map(),
    readSignals = [];
  let nextCatalog, respondMeta, nextSyncError;
  const catalogEvent = () =>
    new Promise((resolve) => {
      nextCatalog = resolve;
    });
  const record = (domain, request, ctx) => {
    calls.push({ domain, request, ctx });
  };
  const shared = {
    calls,
    stops,
    sessionReady: true,
    noop() {},
    async project(request, ctx) {
      record('project', request, ctx);
      if (request.projectId?.startsWith('hold'))
        return new Promise((resolve) => held.set(request.projectId, resolve));
      await ctx.cloud('list', {});
      return { projects: ctx.projects };
    },
    provider(request, ctx) {
      record('provider', request, ctx);
      ctx.operations.set('fixture-operation', {
        workspaceId: ctx.workspaceId,
        userId: ctx.userId,
      });
      return { providers: [] };
    },
    stopProvider(ctx) {
      stops.push(['providers', [...ctx.operations.keys()]]);
      ctx.operations.clear();
    },
    tools(request, ctx) {
      record('tools', request, ctx);
      return { action: request.action, saved: true };
    },
    schedule(request, ctx) {
      record('schedule', request, ctx);
      return { schedules: [] };
    },
    async shortcut(request, ctx) {
      record('shortcut', request, ctx);
      await ctx.cloud('listAccessibleDocuments', {
        workspaceId: ctx.workspaceId,
      });
      return { entries: [] };
    },
    shortcutCatalog(ctx, scope) {
      record('shortcutCatalog', scope, ctx);
      return { items: [], incomplete: false, truncated: false };
    },
    expand(id, ctx, scope) {
      record('expand', { id, scope }, ctx);
      return 'Expanded fixture';
    },
    options(request, machines, getGrant, signal, agentCatalog) {
      record('options', request, { machines, getGrant, signal, agentCatalog });
      return { roles: [], mcpServers: [] };
    },
    configure(choice, previous, input, ctx) {
      record('configure', choice, ctx);
      return { ...input, mcpServerIds: choice.mcpServerIds };
    },
    subagent(request, doc) {
      record('subagent', request, doc);
      return {
        state: 'ready',
        doc: request.identity && doc(request.identity.sessionId),
      };
    },
    queue(request) {
      record('queue', request);
      return { state: 'applied' };
    },
    check(request) {
      record('check', request);
      return { state: 'uploaded' };
    },
  };
  globalThis.__indexIntegration = shared;
  globalThis.__indexClient = class {
    constructor({ url }) {
      this.isMeta = decodeURIComponent(url).endsWith(':meta');
    }
    async bootstrap() {
      return {
        ok: true,
        result: {
          snapshotOffset: '1',
          nextOffset: '1',
          upToDate: true,
          updates: [],
          snapshot: { body: this.isMeta ? snapshots.meta : snapshots.machine },
        },
      };
    }
    readOnce({ signal }) {
      readSignals.push(signal);
      return new Promise((resolve, reject) => {
        if (this.isMeta) respondMeta = resolve;
        signal.addEventListener('abort', () => reject(new Error('cancelled')), {
          once: true,
        });
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
                token: 'fixture',
                gatewayBaseUrl: 'https://example.invalid',
                expiresIn: 3600,
              }),
            );
          if (event.type === 'catalog') nextCatalog?.(event);
          if (event.type === 'syncError') nextSyncError?.(event);
          if (event.type === 'shareRequest')
            queueMicrotask(() =>
              globalThis.dataRuntime.shareResult(event.id, {}, false),
            );
        },
      },
    },
  };
  t.after(() => {
    globalThis.dataRuntime?.stop();
    delete globalThis.dataRuntime;
    delete globalThis.webkit;
    delete globalThis.__indexClient;
    delete globalThis.__indexIntegration;
  });
  await runtimeBundle();
  const runtime = globalThis.dataRuntime,
    scope = { workspaceId: 'w1', userId: 'u1' };
  await assert.rejects(
    runtime.scheduleCommand({ ...scope, action: 'list' }),
    /metadata_not_ready/,
  );
  const ready = catalogEvent();
  runtime.start('w1', 'u1');
  await ready;
  const identity = {
    sessionId: 's1',
    parentTurnId: 'p',
    entryId: 'e',
    itemId: 'i',
    taskId: 't',
  };
  const requests = [
    ['scheduleCommand', { ...scope, action: 'list' }],
    [
      'projectCommand',
      { ...scope, editorId: 'editor', request: { kind: 'list' } },
    ],
    ['providerCommand', { ...scope, action: 'list' }],
    ['shortcutCommand', { ...scope, action: 'list' }],
    ['sessionTools', { ...scope, sessionId: 's1', action: 'unread' }],
    [
      'runOptions',
      {
        ...scope,
        sessionId: 's1',
        machineId: 'spoofed',
        agentConfigId: 'spoofed',
      },
    ],
    [
      'subagentHistory',
      { ...scope, action: 'watch', subscriptionId: 'sub', identity },
    ],
    [
      'queueMessage',
      { ...scope, sessionId: 's1', id: 'turn', action: 'delete' },
    ],
    ['checkSend', { ...scope, sessionId: 's1', id: 'turn' }],
  ];
  for (const [method, args] of requests) {
    await runtime[method](args);
    const count = calls.length;
    await assert.rejects(
      async () => runtime[method]({ ...args, userId: 'other' }),
      /metadata_not_ready/,
    );
    await assert.rejects(
      async () => runtime[method]({ ...args, workspaceId: 'other' }),
      /metadata_not_ready/,
    );
    assert.equal(
      calls.length,
      count,
      method + ' must reject stale identity before entering its domain',
    );
  }
  const option = calls.find((call) => call.domain === 'options');
  assert.equal(option.request.machineId, 'm1');
  assert.equal(option.request.agentConfigId, 'a1');
  assert.equal(option.request.projectId, 'github:fixture/repo');
  assert.equal(
    option.ctx.agentCatalog().find((agent) => agent.id === 'a1').machineId,
    'm1',
  );
  assert.deepEqual(calls.find((call) => call.domain === 'subagent').ctx('s1'), {
    id: 's1',
  });
  shared.sessionReady = false;
  assert.equal(
    calls.find((call) => call.domain === 'subagent').ctx('s1'),
    undefined,
    'subagent reads cannot use a partial or offline session replica',
  );
  shared.sessionReady = true;
  const brokerEvents = events.filter((event) => event.type === 'shareRequest');
  assert.deepEqual(
    brokerEvents.map((event) => event.operation),
    ['projectApi', 'shortcutApi'],
  );
  assert.ok(
    brokerEvents.every(
      (event) => event.workspaceId === 'w1' && event.userId === 'u1',
    ),
  );
  const send = await runtime.sendTurn({
    ...scope,
    sessionId: 's1',
    machineId: 'm1',
    cliType: 'builtin',
    agentType: 'codex',
    text: '@shortcut:fixture',
    mcpServerIds: ['mcp'],
  });
  assert.equal(send.text, 'Expanded fixture');
  assert.deepEqual(send.config.mcpServerIds, ['mcp']);
  const expanded = calls.find((call) => call.domain === 'expand');
  assert.deepEqual(expanded.request.scope, {
    machineId: 'm1',
    providerKey: 'builtin:codex',
    project: { kind: 'github', repository: 'fixture/repo' },
  });
  assert.equal(
    calls.find((call) => call.domain === 'configure').ctx.agentConfigId,
    'a1',
  );
  runtime.setActive(false);
  assert.equal(
    option.ctx.signal.aborted,
    false,
    'background suspension retains command and replica ownership',
  );
  assert.deepEqual(stops, []);
  const cancelled = runtime.projectCommand({
    ...scope,
    editorId: 'cancelled',
    request: { kind: 'detail', projectId: 'hold-cancel' },
  });
  await runtime.projectCommand({
    ...scope,
    editorId: 'cancelled',
    request: { kind: 'cancel' },
  });
  held.get('hold-cancel')({ projects: [] });
  await assert.rejects(cancelled, /abort/i);
  const retained = runtime.projectCommand({
    ...scope,
    editorId: 'retained',
    request: { kind: 'detail', projectId: 'hold-live' },
  });
  const changed = catalogEvent(),
    version = meta.version();
  meta.set(['m', 'session-s1', 'title'], 'Changed while reading');
  respondMeta({
    ok: true,
    result: {
      nextOffset: '2',
      upToDate: true,
      payload: {
        body: encodeFrame(
          new TextEncoder().encode(JSON.stringify(meta.exportJson(version))),
        ),
      },
    },
  });
  assert.equal(
    JSON.parse((await changed).catalog).sessions[0].title,
    'Changed while reading',
  );
  held.get('hold-live')({ projects: [] });
  await retained;
  const stale = runtime.projectCommand({
    ...scope,
    editorId: 'stale',
    request: { kind: 'detail', projectId: 'hold-account' },
  });
  const staleContext = calls.at(-1).ctx,
    oldReaders = [...readSignals];
  const switched = catalogEvent();
  runtime.start('w2', 'u2', false);
  await switched;
  assert.equal(staleContext.signal.aborted, true);
  assert.throws(() => option.ctx.agentCatalog(), /abort/i);
  assert.ok(
    oldReaders.every((signal) => signal.aborted),
    'account change closes owned catalog readers',
  );
  assert.deepEqual(stops.slice(0, 3), [
    ['providers', ['fixture-operation']],
    'subagents',
    'sessions',
  ]);
  held.get('hold-account')({ projects: [] });
  await assert.rejects(stale, /abort/i);
  await assert.rejects(runtime.runOptions({ ...scope }), /metadata_not_ready/);
  const current = await runtime.runOptions({
    workspaceId: 'w2',
    userId: 'u2',
    sessionId: 's1',
  });
  assert.deepEqual(current, { roles: [], mcpServers: [] });
  await runtime.providerCommand({
    workspaceId: 'w2',
    userId: 'u2',
    action: 'list',
  });
  const failed = new Promise((resolve) => {
    nextSyncError = resolve;
  });
  respondMeta({ ok: false, result: { code: 'network_error' } });
  await failed;
  runtime.stop();
  assert.deepEqual(
    stops.at(-3),
    ['providers', ['fixture-operation']],
    'teardown releases provider operations even after metadata loss',
  );
  assert.ok(readSignals.every((signal) => signal.aborted));
});
