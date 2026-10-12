import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { build } from 'esbuild';
import * as capability from '@lody/cloud-runtime/protocol/capability';
import * as runOptions from '../../src/features/sessions/runOptions.ts';
import * as permissions from '../../src/features/sessions/permissionTarget.ts';
import { planExecutionChoice } from '../../src/features/sessions/proposedPlan.ts';

const tick = () => new Promise((resolve) => setImmediate(resolve));
const entry = {
  id: 'turn',
  rev: 1,
  role: 'user',
  status: 'complete',
  finished: true,
  items: [],
};

async function setup(initialChoice = {}) {
  const calls = {
    sends: [],
    queue: [],
    recover: [],
    pages: [],
    pins: [],
    optionsRetries: 0,
    cancelled: 0,
    released: 0,
  };
  const session = {
    id: 'session',
    title: 'Source',
    machineId: 'machine',
    projectId: 'project',
    cliType: 'builtin',
    agentType: 'codex',
    archived: false,
    status: 'idle',
  };
  const world = {
    account: { user: { id: 'viewer' } },
    selected: { id: 'workspace', name: 'Team' },
    catalog: { sessions: [session], projects: [], machineIds: ['machine'] },
    snapshot: { status: 'live', revision: 1, entries: [entry] },
    params: {
      session,
      modelId: 'model',
      effort: 'high',
      mcpServerIds: ['mcp'],
      ...initialChoice,
    },
    roles: [
      {
        id: 'role',
        name: 'Role',
        available: true,
        revision: 3,
        runConfig: { modelId: 'model' },
      },
    ],
  };
  const runtime = {
    get params() {
      return world.params;
    },
    cancel() {
      calls.cancelled++;
    },
  };
  let instance;
  const instances = new Map();
  const effects = [];
  const react = {
    useRef(initial) {
      const at = instance.cursor++;
      return (instance.cells[at] ??= { current: initial });
    },
    useState(initial) {
      const owner = instance;
      const at = owner.cursor++;
      if (!(at in owner.cells))
        owner.cells[at] = typeof initial === 'function' ? initial() : initial;
      return [
        owner.cells[at],
        (next) => {
          owner.cells[at] =
            typeof next === 'function' ? next(owner.cells[at]) : next;
        },
      ];
    },
    useEffect(effect, deps) {
      const owner = instance;
      const at = owner.cursor++;
      if (
        owner.cells[at] &&
        deps?.every((dep, i) => Object.is(dep, owner.cells[at].deps?.[i]))
      )
        return;
      const previous = owner.cells[at];
      const current = { deps };
      owner.cells[at] = current;
      effects.push(() => {
        previous?.cleanup?.();
        current.cleanup = effect();
      });
    },
    useMemo(create, deps) {
      const at = instance.cursor++;
      if (
        !instance.cells[at] ||
        !deps.every((dep, i) => Object.is(dep, instance.cells[at].deps[i]))
      )
        instance.cells[at] = { deps, value: create() };
      return instance.cells[at].value;
    },
    useCallback(fn, deps) {
      return react.useMemo(() => fn, deps);
    },
  };
  const file = new URL('../../src/screens/SessionScreen.tsx', import.meta.url)
    .pathname;
  const source = await readFile(file, 'utf8');
  const imports = new Map();
  for (const match of source.matchAll(
    /import\s+(type\s+)?\{([\s\S]*?)\}\s+from\s+['"]([^'"]+)['"]/g,
  )) {
    if (match[1]) continue;
    const names = match[2]
      .split(',')
      .map((name) => name.trim())
      .filter((name) => name && !name.startsWith('type '))
      .map((name) => name.split(/\s+as\s+/)[0]);
    imports.set(match[3], [
      ...new Set([...(imports.get(match[3]) ?? []), ...names]),
    ]);
  }
  const noop = () => {};
  const bindings = Object.fromEntries(
    [...imports].map(([path, names]) => [
      path,
      Object.fromEntries(names.map((name) => [name, noop])),
    ]),
  );
  const set = (path, values) => Object.assign(bindings[path], values);
  set('react', react);
  set('react-native', { View: 'View', Alert: { alert: noop } });
  set('@lody-ios/kit', {
    NativeChat: 'NativeChat',
    NativeNavigationHeader: 'Header',
    localProjectIdOf: () => '',
    sessionCreationOptions: async () => JSON.stringify({ capabilities: [] }),
  });
  set('@/lib/presentation', {
    definePage: (page) => page,
    present: async (page, params) => {
      calls.pages.push({ page: page.id, params });
      return { status: 'cancelled' };
    },
  });
  set('@/hooks/screens/usePageRuntime', { usePageRuntime: () => runtime });
  set('@/cloud/auth/AuthProvider', {
    useAuth: () => ({ account: world.account }),
  });
  set('@/cloud/catalog/CatalogProvider', {
    useCatalog: () => ({
      catalog: world.catalog,
      selected: world.selected,
      serverSessions: world.catalog.sessions,
      refresh: noop,
    }),
  });
  set('@/lib/theme/palette', { usePalette: () => ({ reading: 'white' }) });
  set('../lib/i18n/index.ts', { t: (key) => key });
  set('@/cloud/send/pendingSends', {
    usePendingSends: () => ({ ready: true, records: [] }),
  });
  set('@/cloud/catalog/connection', {
    useConnection: () => ({ state: 'live', syncedAt: 1 }),
  });
  set('@lody/cloud-runtime/models/machines', { machineState: () => 'online' });
  set('@/features/sessions/sessionTitle', {
    sessionTitleDetails: () => ({
      projectName: 'Project',
      machineName: 'Machine',
    }),
  });
  set('@/features/sessions/sessionActions', {
    isSessionDeleting: () => false,
    subscribeSessionDeletion: () => noop,
    setContentPinned: (...args) => calls.pins.push(args),
  });
  set('@/features/sessions/useSessionRuntime', {
    useSessionRuntime: () => {
      react.useEffect(
        () => () => {
          calls.released++;
        },
        [],
      );
      return {
        snapshot: world.snapshot,
        overflow: false,
        cursor: { current: { generation: 1 } },
        reconnect: noop,
        initialHistory: world.prepared,
      };
    },
  });
  set('@/features/sessions/useSessionControl', {
    useSessionControl: () => ({ running: false, controlling: false }),
  });
  set('@/features/sessions/useSessionSend', {
    useSessionSend: () => ({
      canSend: true,
      sending: false,
      awaitingReply: false,
      submit: (value) => calls.sends.push(value),
      recover: (action) => calls.recover.push(action),
      sendRecovery: { phase: 'unknown' },
      recovering: false,
      clearDraftToken: 0,
    }),
  });
  set('@/features/sessions/useSessionQueue', {
    useSessionQueue: () => ({
      entries: world.queueEntries ?? world.snapshot.entries,
      queueState: { editable: true, editingId: '' },
      act: (event) => calls.queue.push(event),
    }),
  });
  set('@/features/settings/queued-message-behavior', {
    useQueuedMessageBehavior: () => ({ queuedMessageBehavior: 'queue' }),
  });
  set('@/features/settings/quick-replies', {
    useQuickReplies: () => ({ quickReplies: [] }),
  });
  set('@/hooks/screens/useComposerRunOptions', {
    useComposerRunOptions: () => ({
      catalog: {
        roles: world.optionsError ? [] : world.roles,
        mcpServers: [],
        unavailable: !!world.optionsError,
      },
      error: world.optionsError ?? '',
      loading: world.optionsLoading ?? false,
      refresh: () => {
        calls.optionsRetries++;
        world.optionsError = '';
      },
    }),
  });
  set('@/features/team/useTeamDirectory', {
    useTeamDirectory: () => ({ senders: {}, showSenderIdentity: false }),
  });
  set('@/features/sessions/useAgentErrorRetry', {
    useAgentErrorRetry: () => ({ pending: false, stateJSON: '{}' }),
  });
  set('@/features/sessions/useProposedPlan', {
    useProposedPlan: () => ({ pending: false, stateJSON: '{}' }),
  });
  set('@/features/sessions/proposedPlan', { planExecutionChoice });
  set('@/features/sessions/permissionTarget', permissions);
  set('@/features/sessions/freeTurnNotice', {
    freeTurnLimitReached: () => false,
    freeTurnNotice: () => '',
  });
  set('@/features/sessions/prepareSessionHistory', {
    sessionEntriesJSON: (snapshot) => JSON.stringify(snapshot.entries),
  });
  set('@/cloud/send/capability', capability);
  set('@/features/sessions/runOptions', runOptions);
  set('@/hooks/screens/useSessionPreview', { useSessionPreview: () => ({}) });
  set('@/hooks/screens/useSessionSimulator', {
    useSessionSimulator: () => ({ onPreview: () => false }),
  });
  set('@/hooks/screens/composerContext', { composerContext: () => ({}) });
  set('@/hooks/screens/useComposerMentions', {
    useComposerMentions: () => ({}),
  });
  set('@/features/sessions/workspaceMenu', { workspaceMenuActions: () => [] });
  set('@/cloud/session-tools', {
    requestSessionTools: async () => ({
      action: 'fork-options',
      shared: false,
    }),
  });
  globalThis.__screenTestModules = bindings;
  globalThis.__screenTestJsx = {
    jsx: (type, props) => ({ type, props }),
    jsxs: (type, props) => ({ type, props }),
  };
  const bundle = await build({
    entryPoints: [file],
    bundle: true,
    format: 'esm',
    jsx: 'automatic',
    define: { __DEV__: 'false' },
    write: false,
    plugins: [
      {
        name: 'session-boundaries',
        setup(b) {
          b.onResolve({ filter: /.*/ }, ({ path, kind }) => {
            if (kind === 'entry-point') return;
            if (path === '@/features/sessions/runOptionsRecovery')
              return {
                path: new URL(
                  '../../src/features/sessions/runOptionsRecovery.ts',
                  import.meta.url,
                ).pathname,
              };
            if (path === '../../lib/i18n/index.ts')
              return { path: '../lib/i18n/index.ts', namespace: 'fixture' };
            return { path, namespace: 'fixture' };
          });
          b.onLoad({ filter: /.*/, namespace: 'fixture' }, ({ path }) => ({
            contents:
              path === 'react/jsx-runtime'
                ? 'export const {jsx,jsxs}=globalThis.__screenTestJsx;'
                : `export const {${imports.get(path).join(',')}}=globalThis.__screenTestModules[${JSON.stringify(path)}];`,
          }));
        },
      },
    ],
  });
  const { SessionScreen } = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text + `\n// ${Math.random()}`).toString('base64')}`
  );
  let header;
  function render() {
    let chat;
    header = undefined;
    const seen = new Set();
    const visit = (node) => {
      if (!node) return;
      if (Array.isArray(node)) {
        node.forEach(visit);
        return;
      }
      if (typeof node.type === 'function') {
        const previous = instance;
        instance = instances.get(node.type) ?? { cells: [] };
        instances.set(node.type, instance);
        seen.add(node.type);
        instance.cursor = 0;
        const child = node.type(node.props);
        instance = previous;
        visit(child);
        return;
      }
      if (node.type === 'NativeChat') chat = node.props;
      if (node.type === 'Header') header = node.props;
      visit(node.props?.children);
    };
    visit({ type: SessionScreen.Component });
    for (const [type, owner] of instances) {
      if (seen.has(type)) continue;
      owner.cells.forEach((cell) => cell?.cleanup?.());
      instances.delete(type);
    }
    effects.splice(0).forEach((effect) => effect());
    return chat;
  }
  render();
  await tick();
  render();
  return {
    world,
    calls,
    render,
    get header() {
      return header;
    },
  };
}

test('native MCP and Role events preserve other choices; explicit None and manual pinned edits reach send', async () => {
  const { calls, render } = await setup();
  let chat = render();
  chat.onComposerOptionChange({ nativeEvent: { agentRoleId: 'role' } });
  chat = render();
  chat.onComposerOptionChange({ nativeEvent: { mcpServerIds: [] } });
  chat = render();
  chat.onSend({ nativeEvent: { id: 'send', text: 'Text', attachments: [] } });
  assert.deepEqual(calls.sends[0].choice.mcpServerIds, []);
  assert.equal(calls.sends[0].choice.modelId, 'model');
  assert.equal(calls.sends[0].choice.effort, 'high');
  assert.equal(calls.sends[0].choice.agentRoleRevision, 3);
  chat.onComposerOptionChange({ nativeEvent: { modelId: 'other' } });
  chat = render();
  chat.onSend({
    nativeEvent: { id: 'changed', text: 'Text', attachments: [] },
  });
  assert.equal(calls.sends[1].choice.agentRoleId, null);
  assert.equal(calls.sends[1].choice.effort, 'high');
  chat.onComposerOptionChange({ nativeEvent: { agentRoleId: 'role' } });
  chat = render();
  chat.onComposerOptionChange({ nativeEvent: { agentRoleId: null } });
  chat = render();
  chat.onSend({ nativeEvent: { id: 'none', text: 'Text', attachments: [] } });
  assert.equal(calls.sends[2].choice.agentRoleId, null);
  assert.equal(calls.sends[2].choice.agentRoleRevision, undefined);
});

test('Role picks that exceed the combined option limit are disabled and cannot replace the selected configuration', async () => {
  const values = Object.fromEntries(
    Array.from({ length: 100 }, (_, index) => [`normal${index}`, 'selected']),
  );
  const { world, calls, render } = await setup({ configOptionValues: values });
  world.roles[0].runConfig.configOptionValues = Object.fromEntries(
    Array.from({ length: 29 }, (_, index) => [`role${index}`, 'pinned']),
  );
  world.roles.push({
    ...world.roles[0],
    id: 'compatible',
    runConfig: { configOptionValues: { normal0: 'pinned' } },
  });
  let chat = render();
  const roles = JSON.parse(chat.composerOptionsJSON).runOptions.roles;
  assert.equal(roles.find((role) => role.id === 'role').available, false);
  assert.equal(roles.find((role) => role.id === 'compatible').available, true);
  chat.onComposerOptionChange({ nativeEvent: { agentRoleId: 'role' } });
  chat = render();
  chat.onSend({
    nativeEvent: { id: 'unchanged', text: 'Text', attachments: [] },
  });
  assert.deepEqual(calls.sends[0].choice.configOptionValues, values);
  assert.equal(calls.sends[0].choice.agentRoleId, undefined);
  assert.equal(calls.sends[0].choice.modelId, 'model');
  assert.deepEqual(calls.sends[0].choice.mcpServerIds, ['mcp']);
});

test('queue and recovery use their owned controllers while prepared native history survives unchanged entries', async () => {
  const { world, calls, render } = await setup();
  world.prepared = {
    snapshot: world.snapshot,
    entriesJSON: '[{"id":"cached"}]',
    nativeEntries: { token: 'prepared' },
  };
  let chat = render();
  assert.equal(chat.preparedEntries, world.prepared.nativeEntries);
  assert.equal(chat.entriesJSON, world.prepared.entriesJSON);
  chat.onRecoverSend({ nativeEvent: { action: 'check' } });
  chat.onQueueAction({
    nativeEvent: {
      action: 'save-edit',
      id: 'queued',
      text: 'Edited',
      editingStartedAt: 7,
    },
  });
  assert.deepEqual(calls.recover, ['check']);
  assert.deepEqual(calls.queue, [
    { action: 'save-edit', id: 'queued', text: 'Edited', editingStartedAt: 7 },
  ]);
  assert.equal(JSON.parse(chat.composerJSON).sendRecovery.phase, 'unknown');
  world.queueEntries = [
    ...world.snapshot.entries,
    { ...entry, id: 'queue-ghost' },
  ];
  chat = render();
  assert.deepEqual(
    JSON.parse(chat.entriesJSON).map((item) => item.id),
    ['turn', 'queue-ghost'],
  );
});

test('archiving preserves history pin and unpin actions while sending stays read-only', async () => {
  const { world, calls, render } = await setup();
  let chat = render();
  chat.onPin({ nativeEvent: { entryId: 'turn' } });
  world.catalog.sessions[0].pinnedHistoryId = 'turn';
  world.catalog.sessions[0].archived = true;
  chat = render();
  assert.equal(chat.pinnedHistoryId, 'turn');
  assert.equal(chat.pinEnabled, true);
  assert.equal(JSON.parse(chat.composerJSON).editable, false);
  chat.onPin({ nativeEvent: { entryId: '' } });
  chat.onPin({ nativeEvent: { entryId: 'turn' } });
  assert.deepEqual(calls.pins, [
    ['workspace', 'session', 'turn'],
    ['workspace', 'session', null],
    ['workspace', 'session', 'turn'],
  ]);
  world.snapshot = { ...world.snapshot, status: 'offline' };
  chat = render();
  assert.equal(chat.pinEnabled, false);
  chat.onPin({ nativeEvent: { entryId: '' } });
  assert.equal(calls.pins.length, 3);
});

test('run-option lookup failure shows a product notice and retry without clearing chosen Role or MCP', async () => {
  const fixture = await setup();
  let chat = fixture.render();
  chat.onComposerOptionChange({ nativeEvent: { agentRoleId: 'role' } });
  fixture.render();
  fixture.world.optionsError = 'run-options-unavailable';
  chat = fixture.render();
  const options = JSON.parse(chat.composerOptionsJSON);
  assert.equal(options.agentRoleId, 'role');
  assert.deepEqual(options.mcpServerIds, ['mcp']);
  assert.equal(options.runOptions.unavailable, true);
  assert.equal(
    JSON.parse(chat.composerJSON).notice,
    'runOptions.chatUnavailable',
  );
  const menu = fixture.header.items.find((item) => item.type === 'menu');
  const retry = menu.menu.items.find(
    (item) => item.title === 'runOptions.retry',
  );
  assert.equal(retry.disabled, false);
  retry.onPress();
  chat = fixture.render();
  assert.equal(fixture.calls.optionsRetries, 1);
  assert.equal(JSON.parse(chat.composerJSON).notice, '');
  assert.equal(JSON.parse(chat.composerOptionsJSON).agentRoleId, 'role');
  assert.deepEqual(JSON.parse(chat.composerOptionsJSON).mcpServerIds, ['mcp']);
  assert.equal(
    fixture.header.items
      .find((item) => item.type === 'menu')
      .menu.items.some((item) => item.title === 'runOptions.retry'),
    false,
  );
});
