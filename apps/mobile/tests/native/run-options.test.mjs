import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { Flock } from '@loro-dev/flock-wasm/base64';
import { selectedRoleChoice } from '../../src/features/sessions/runOptions.ts';
import { pendingSessionFromDraft } from '../../src/features/sessions/createDraft.ts';
import { supportsRunConfigOptions } from '../../../../packages/cloud-runtime/src/protocol/run-options.ts';

const ok = (result = {}) => ({ ok: true, result });
let workspaceRows = new Flock('roles');
let lastRpc;
let gitState = { git: true, branches: ['main'] };
let reads = 0;
let createRequests = 0;
globalThis.__runOptionsClient = class {
  constructor({ url }) {
    this.url = decodeURIComponent(url);
  }
  async create() {
    createRequests++;
    return ok();
  }
  async bootstrap() {
    reads++;
    return ok({
      snapshotOffset: '0',
      snapshot: { body: workspaceRows.exportFile() },
      nextOffset: '0',
      upToDate: true,
      updates: [],
    });
  }
  async append({ part }) {
    if (this.url.includes(':rpc:req:')) lastRpc = JSON.parse(part.body);
    return ok();
  }
  async readOnce() {
    return ok({
      nextOffset: '1',
      payload: {
        body: new TextEncoder().encode(
          JSON.stringify({
            id: lastRpc.id,
            result: { success: true, state: gitState },
          }),
        ),
      },
    });
  }
};
const bundle = await build({
  stdin: {
    contents: `export * from './packages/cloud-runtime/src/runtime/run-options'; export * from './packages/cloud-runtime/src/runtime/agent-roles'; export * from './packages/cloud-runtime/src/runtime/create-session';`,
    resolveDir: process.cwd(),
  },
  bundle: true,
  format: 'esm',
  platform: 'browser',
  write: false,
  plugins: [
    {
      name: 'streams',
      setup(builder) {
        builder.onResolve({ filter: /^@loro-dev\/streams-client$/ }, () => ({
          path: 'mock',
          namespace: 'test',
        }));
        builder.onLoad({ filter: /.*/, namespace: 'test' }, () => ({
          contents:
            'export const StreamsClient = globalThis.__runOptionsClient',
        }));
      },
    },
  ],
});
const runtime = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);
const machine = new Flock('machine');
const agent = {
  id: 'a1',
  name: 'Codex',
  machineId: 'm1',
  cliType: 'builtin',
  agentType: 'codex',
};
machine.set(['agentConfig', agent.id], agent);
machine.set(['localProject', 'p1'], { name: 'Project', rootPath: '/fixture' });
const machines = new Map([['m1', machine]]);
const role = {
  v: 1,
  id: 'reviewer',
  name: 'Reviewer',
  ownerUserId: 'u1',
  visibility: 'workspace',
  machineId: 'm1',
  agentConfigId: 'a1',
  revision: 3,
  runConfig: {
    modelId: 'model-a',
    modeId: 'read-only',
    configOptionValues: { effort: 'high', auth_token: 'must-not-leave' },
  },
  promptPrefix: 'Review carefully.',
};
const grant = async () => ({
  token: 'synthetic',
  gatewayBaseUrl: 'https://example.invalid',
});
const context = {
  workspaceId: 'w1',
  userId: 'u1',
  machineId: 'm1',
  agentConfigId: 'a1',
  machines,
  getGrant: grant,
};
const input = {
  modelId: 'model-a',
  modeId: 'read-only',
  configOptionValues: { effort: 'high' },
  prompt: 'Task',
  inputBlocks: [{ type: 'text', text: 'Task' }],
  mcpServerIds: ['docs'],
};

function resetRows() {
  workspaceRows = new Flock(`roles-${crypto.randomUUID()}`);
  workspaceRows.set(['agentRole', role.id], role);
  workspaceRows.set(['mcpServer', 'docs'], {
    id: 'docs',
    name: 'Docs',
    transport: 'stdio',
    enabledByDefault: true,
    connection: { command: 'private-command', env: { TOKEN: 'secret' } },
  });
}

test('one safe catalog owner respects Role visibility and binding while omitting MCP connections and Role secrets', () => {
  resetRows();
  workspaceRows.set(['agentRole', 'private'], {
    ...role,
    id: 'private',
    visibility: 'private',
    ownerUserId: 'u2',
  });
  workspaceRows.set(['agentRole', 'missing'], {
    ...role,
    id: 'missing',
    agentConfigId: 'gone',
  });
  const catalog = runtime.runOptionsFromRows(
    workspaceRows.scan(),
    'u1',
    machines,
    'm1',
  );
  assert.deepEqual(
    catalog.roles.map((item) => [item.id, item.available]),
    [
      ['missing', false],
      ['reviewer', true],
    ],
  );
  assert.equal(catalog.roles[0].unavailableReason, 'agent_config_missing');
  assert.equal(
    catalog.roles[1].runConfig.configOptionValues.auth_token,
    undefined,
  );
  assert.equal(JSON.stringify(catalog).includes('private-command'), false);
  assert.equal(
    JSON.stringify(catalog).includes('Review carefully'),
    false,
    'Prompt prefix stays in runtime',
  );
  assert.deepEqual(
    catalog.mcpServers.map((item) => item.id),
    ['docs'],
  );
  assert.deepEqual(
    runtime
      .roleMentions(workspaceRows.scan(), 'u1', machines, 'm1')
      .items.map((item) => item.path),
    ['reviewer'],
  );
  assert.deepEqual(
    runtime.runOptionsFromRows([], 'u1', machines).mcpServers,
    [],
  );
});

test('maximum bounded Unicode Role choices survive projection, creation and send envelopes without truncation', async () => {
  resetRows();
  const configOptionValues = Object.fromEntries(
    Array.from({ length: 64 }, (_, index) => [
      '界'.repeat(125) + String(index).padStart(3, '0'),
      '界'.repeat(512),
    ]),
  );
  const runConfig = {
    modelId: '界'.repeat(4096),
    modeId: '界'.repeat(4096),
    configOptionValues,
    memory: { providerId: 'p'.repeat(100), memoryId: 'm'.repeat(200) },
  };
  workspaceRows.set(['agentRole', role.id], { ...role, runConfig });
  const projected = runtime.runOptionsFromRows(
    workspaceRows.scan(),
    context.userId,
    machines,
  ).roles[0];
  assert.deepEqual(projected.runConfig, runConfig);
  const selected = selectedRoleChoice({ mcpServerIds: [] }, projected);
  const envelope = JSON.stringify({
    workspaceId: context.workspaceId,
    sessionId: '018c10bd-af54-790b-b573-323b5f7bb0ea',
    machineId: context.machineId,
    userId: context.userId,
    cliType: 'builtin',
    agentType: 'codex',
    text: 'Task',
    ...selected,
  });
  assert.ok(
    Buffer.byteLength(envelope, 'utf8') > 128 * 1024,
    'The valid request must reproduce the old native transport rejection',
  );
  const received = JSON.parse(envelope);
  assert.deepEqual(received.frozenRole, runConfig);
  assert.deepEqual(received.configOptionValues, configOptionValues);
  const resolved = await runtime.resolveTurnRunOptions(
    received,
    {},
    {
      prompt: received.text,
      inputBlocks: [{ type: 'text', text: received.text }],
      modelId: received.modelId,
      modeId: received.modeId,
      configOptionValues: received.configOptionValues,
    },
    context,
  );
  assert.deepEqual(resolved.configOptionValues, configOptionValues);
  assert.deepEqual(resolved.memory, runConfig.memory);
  const { record } = pendingSessionFromDraft(
    {
      sessionId: received.sessionId,
      userId: context.userId,
      workspaceId: context.workspaceId,
      projectId: 'm1:local:p1',
      projectName: 'Project',
      useWorktree: true,
      agent: { ...agent, machineName: 'Mac' },
      choice: selected,
    },
    {
      id: received.sessionId,
      text: received.text,
      startedAt: 1,
      attachments: [],
    },
  );
  assert.ok(Buffer.byteLength(record.send.creation, 'utf8') > 128 * 1024);
  assert.deepEqual(JSON.parse(record.send.creation).frozenRole, runConfig);
  assert.deepEqual(record.send.choice.configOptionValues, configOptionValues);
  assert.deepEqual(record.send.choice.mcpServerIds, []);
});

test('escaped 128-option choices plus complete 64-option Role pins fit the finite native transport', async (t) => {
  resetRows();
  const entries = Array.from({ length: 128 }, (_, index) => [
    '\0'.repeat(125) + String(index).padStart(3, '0'),
    '\0'.repeat(512),
  ]);
  const pins = Object.fromEntries(entries.slice(0, 64));
  const prior = Object.fromEntries(entries.slice(64));
  const config = {
    modelId: '界'.repeat(4096),
    modeId: '界'.repeat(4096),
    configOptionValues: pins,
    memory: { providerId: '界'.repeat(100), memoryId: '界'.repeat(200) },
  };
  const largeRole = {
    ...role,
    id: '界'.repeat(256),
    revision: Number.MAX_SAFE_INTEGER,
    runConfig: config,
  };
  const mcpServerIds = Array.from(
    { length: 128 },
    (_, index) => '界'.repeat(253) + String(index).padStart(3, '0'),
  );
  const catalogRows = [
    { key: ['agentRole', largeRole.id], value: largeRole },
    ...mcpServerIds.map((id, index) => ({
      key: ['mcpServer', id],
      value: { id, name: `Server ${index}`, transport: 'http' },
    })),
  ];
  const projected = runtime
    .runOptionsFromRows(catalogRows, 'u1', machines)
    .roles.find((item) => item.id === largeRole.id);
  assert.equal(projected.available, true);
  const choice = selectedRoleChoice(
    { configOptionValues: prior, mcpServerIds },
    projected,
    { reasoningEffortConfigId: entries[0][0] },
  );
  assert.equal(Object.keys(choice.configOptionValues).length, 128);
  assert.equal(choice.effort.length, 512);
  assert.equal(supportsRunConfigOptions(choice.configOptionValues), true);
  const request = {
    workspaceId: 'w1',
    sessionId: '018c10bd-af54-790b-b573-323b5f7bb0ea',
    machineId: 'm1',
    userId: 'u1',
    cliType: 'builtin',
    agentType: 'codex',
    text: '\0'.repeat(32000),
    ...choice,
    reasoningEffort: choice.effort,
    reasoningEffortConfigId: entries[0][0],
  };
  const json = JSON.stringify(request);
  const sendBytes = Buffer.byteLength(json, 'utf8');
  assert.ok(sendBytes < 2 * 1024 * 1024);
  const received = JSON.parse(json);
  runtime.validateRunOptionsChoice(received);
  assert.deepEqual(received.frozenRole, config);
  assert.deepEqual(received.configOptionValues, { ...prior, ...pins });
  const { record } = pendingSessionFromDraft(
    {
      sessionId: request.sessionId,
      userId: 'u1',
      workspaceId: 'w1',
      projectId: 'm1:local:p1',
      projectName: 'Project',
      agent: { ...agent, machineName: 'Mac' },
      choice,
    },
    {
      id: request.sessionId,
      text: request.text,
      startedAt: 1,
      attachments: [],
    },
  );
  const createBytes = Buffer.byteLength(record.send.creation, 'utf8');
  assert.ok(createBytes < 2 * 1024 * 1024);
  assert.deepEqual(JSON.parse(record.send.creation).configOptionValues, {
    ...prior,
    ...pins,
  });
  assert.deepEqual(JSON.parse(record.send.creation).frozenRole, config);
  t.diagnostic(
    `escaped envelopes: send=${sendBytes} bytes, creation=${createBytes} bytes; native ceiling=${2 * 1024 * 1024} bytes`,
  );
});

test('unsupported Role options remain inspectable and cannot create a session with a doomed first turn', async () => {
  for (const configOptionValues of [
    Object.fromEntries(
      Array.from({ length: 65 }, (_, index) => [`option-${index}`, 'value']),
    ),
    { preset: '' },
    { preset: 'x'.repeat(513) },
    { ['x'.repeat(129)]: 'value' },
    { preset: 1 },
  ]) {
    resetRows();
    workspaceRows.set(['agentRole', role.id], {
      ...role,
      runConfig: { modelId: 'model-a', configOptionValues },
    });
    const projected = runtime.runOptionsFromRows(
      workspaceRows.scan(),
      'u1',
      machines,
    ).roles[0];
    assert.equal(projected.available, false);
    assert.equal(projected.unavailableReason, 'run_config_unsupported');
    if (
      Object.keys(configOptionValues).length === 65 ||
      configOptionValues.preset === ''
    )
      assert.deepEqual(
        projected.runConfig.configOptionValues,
        configOptionValues,
      );
    const ordinary = { modelId: 'ordinary', mcpServerIds: ['docs'] };
    assert.equal(selectedRoleChoice(ordinary, projected), ordinary);
    const meta = new Flock(`unsupported-${crypto.randomUUID()}`);
    const options = runtime.creationOptions('m1:local:p1', meta, machines);
    let writes = 0;
    const replica = {
      flock: meta,
      client: {
        async append() {
          writes++;
          return ok();
        },
      },
    };
    const args = {
      workspaceId: 'w1',
      projectId: options.project.id,
      sessionId: options.sessionId,
      userId: 'u1',
      machineId: 'm1',
      agentConfigId: 'a1',
      title: 'Task',
    };
    const before = createRequests;
    await assert.rejects(
      runtime.createSession(
        {
          ...args,
          agentRoleId: role.id,
          agentRoleRevision: role.revision,
          frozenRole: projected.runConfig,
        },
        options,
        replica,
        grant,
        context,
      ),
      /role_unavailable/,
    );
    assert.equal(createRequests, before);
    assert.equal(writes, 0);
    assert.equal(
      (await runtime.createSession(args, options, replica, grant, context))
        .state,
      'created',
      'An unsupported optional Role must not block ordinary creation',
    );
  }
});

test('complete Role plus prior options support 128 entries and reject overflow before creation without dropping fields', async () => {
  resetRows();
  const pins = Object.fromEntries(
    Array.from({ length: 64 }, (_, index) => [`pin-${index}`, 'value']),
  );
  const prior = Object.fromEntries(
    Array.from({ length: 64 }, (_, index) => [`prior-${index}`, false]),
  );
  workspaceRows.set(['agentRole', role.id], {
    ...role,
    runConfig: { modelId: 'model-a', configOptionValues: pins },
  });
  const projected = runtime.runOptionsFromRows(
    workspaceRows.scan(),
    'u1',
    machines,
  ).roles[0];
  const selected = selectedRoleChoice({ configOptionValues: prior }, projected);
  assert.equal(Object.keys(selected.configOptionValues).length, 128);
  assert.deepEqual(selected.configOptionValues, { ...prior, ...pins });
  const meta = new Flock(`combined-${crypto.randomUUID()}`);
  const options = runtime.creationOptions('m1:local:p1', meta, machines);
  let writes = 0;
  const replica = {
    flock: meta,
    client: {
      async append() {
        writes++;
        return ok();
      },
    },
  };
  const args = {
    workspaceId: 'w1',
    projectId: options.project.id,
    sessionId: options.sessionId,
    userId: 'u1',
    machineId: 'm1',
    agentConfigId: 'a1',
    title: 'Task',
    agentRoleId: role.id,
    agentRoleRevision: role.revision,
    frozenRole: projected.runConfig,
    configOptionValues: selected.configOptionValues,
  };
  const before = createRequests;
  await assert.rejects(
    runtime.createSession(
      {
        ...args,
        configOptionValues: { ...args.configOptionValues, overflow: true },
      },
      options,
      replica,
      grant,
      context,
    ),
    /invalid_config_options/,
  );
  assert.equal(createRequests, before);
  assert.equal(writes, 0);
  assert.equal(
    (await runtime.createSession(args, options, replica, grant, context)).state,
    'created',
  );
  assert.equal(writes, 1);
});

test('malformed Role identity bounds never advertise a selectable row or create a session', async () => {
  for (const malformed of [
    { id: 'r'.repeat(257) },
    { revision: Number.MAX_SAFE_INTEGER + 1 },
    { revision: 0 },
    { revision: 1.5 },
  ]) {
    resetRows();
    workspaceRows.delete(['agentRole', role.id]);
    const value = { ...role, ...malformed };
    workspaceRows.set(['agentRole', value.id], value);
    assert.deepEqual(
      runtime.runOptionsFromRows(workspaceRows.scan(), 'u1', machines).roles,
      [],
    );
    const meta = new Flock(`identity-${crypto.randomUUID()}`);
    const options = runtime.creationOptions('m1:local:p1', meta, machines);
    const before = createRequests;
    await assert.rejects(
      runtime.createSession(
        {
          workspaceId: 'w1',
          projectId: options.project.id,
          sessionId: options.sessionId,
          userId: 'u1',
          machineId: 'm1',
          agentConfigId: 'a1',
          title: 'Task',
          agentRoleId: value.id,
          agentRoleRevision: value.revision,
        },
        options,
        {
          flock: meta,
          client: {
            async append() {
              throw new Error('must not write');
            },
          },
        },
        grant,
        context,
      ),
      /invalid_role_selection/,
    );
    assert.equal(createRequests, before);
  }
});

test('explicit Role revalidates revision; first-turn execution prefix does not alter authored blocks or repeat on later turns', async () => {
  resetRows();
  const frozenRole = runtime.runOptionsFromRows(
    workspaceRows.scan(),
    'u1',
    machines,
  ).roles[0].runConfig;
  const choice = { agentRoleId: role.id, agentRoleRevision: 3, frozenRole };
  const first = await runtime.resolveTurnRunOptions(choice, {}, input, context);
  assert.equal(first.prompt, 'Review carefully.\n\nTask');
  assert.deepEqual(first.inputBlocks, input.inputBlocks);
  assert.equal(first.agentRoleId, role.id);
  assert.equal(first.agentRoleRevision, 3);
  const later = await runtime.resolveTurnRunOptions(
    choice,
    first,
    input,
    context,
  );
  assert.equal(
    later.prompt,
    'Task',
    'Existing Role selections never replay prefix',
  );
  workspaceRows.set(['agentRole', role.id], {
    ...role,
    revision: 4,
    runConfig: { modelId: 'different' },
  });
  await assert.rejects(
    runtime.resolveTurnRunOptions(choice, {}, input, context),
    /role_revision_changed/,
  );
  const beforeReads = reads;
  const inherited = await runtime.resolveTurnRunOptions(
    { agentRoleId: role.id, agentRoleRevision: 3 },
    first,
    first,
    context,
  );
  assert.equal(inherited.modelId, 'model-a');
  assert.equal(
    reads,
    beforeReads,
    'Inherited frozen turn config does not reread edited catalog',
  );
  const detached = await runtime.resolveTurnRunOptions(
    { agentRoleId: role.id, agentRoleRevision: 3 },
    first,
    {
      ...first,
      modelId: 'different',
      agentRoleId: null,
      agentRoleRevision: undefined,
    },
    context,
  );
  assert.equal(
    detached.agentRoleId,
    null,
    'sendTurn inherited detachment cannot be reattached by hydrated ids',
  );
});

test('MCP inherits, explicit empty disables all, invalid or deleted ids fail before any durable write', async () => {
  resetRows();
  assert.deepEqual(
    (await runtime.resolveTurnRunOptions({}, input, input, context))
      .mcpServerIds,
    ['docs'],
  );
  assert.deepEqual(
    (
      await runtime.resolveTurnRunOptions(
        { mcpServerIds: [] },
        input,
        input,
        context,
      )
    ).mcpServerIds,
    [],
  );
  assert.deepEqual(
    (
      await runtime.resolveTurnRunOptions(
        { mcpServerIds: ['docs'] },
        input,
        input,
        context,
      )
    ).mcpServerIds,
    ['docs'],
  );
  workspaceRows.delete(['mcpServer', 'docs']);
  await assert.rejects(
    runtime.resolveTurnRunOptions(
      { mcpServerIds: ['docs'] },
      input,
      input,
      context,
    ),
    /mcp_selection_unavailable/,
  );
  for (const ids of [[''], ['docs', 'docs'], ['bad id'], 'docs'])
    assert.throws(
      () => runtime.validateRunOptionsChoice({ mcpServerIds: ids }),
      /invalid_mcp_selection/,
    );
  const cleared = await runtime.resolveTurnRunOptions(
    { agentRoleId: null },
    input,
    {
      ...input,
      agentRoleId: role.id,
      agentRoleRevision: 3,
      agentRoleSnapshot: { id: role.id },
    },
    context,
  );
  assert.equal(cleared.agentRoleId, null);
  assert.equal(cleared.agentRoleRevision, undefined);
  assert.equal(cleared.agentRoleSnapshot, undefined);
  assert.equal(
    cleared.modelId,
    input.modelId,
    'Explicit None keeps run settings',
  );
});

test('desktop legacy Agent Roles use merged identities; Flock wins and deleted legacy rooms do not remain available', () => {
  resetRows();
  const meta = new Flock('legacy-meta');
  const emptyMachine = new Flock('legacy-machine');
  const legacyMachines = new Map([['m1', emptyMachine]]);
  meta.set(['e', 'agent-a1'], true);
  meta.set(['m', 'agent-a1'], { ...agent, name: 'Legacy Codex' });
  const rows = runtime.readAgentRoles(workspaceRows.scan(), 'u1');
  let catalog = runtime.creationAgentCatalog(meta, legacyMachines).agents;
  assert.equal(
    runtime.roleOptions(rows, legacyMachines, 'm1', 'a1', catalog)[0].available,
    true,
  );
  assert.equal(
    runtime.roleMentions(
      workspaceRows.scan(),
      'u1',
      legacyMachines,
      'm1',
      catalog,
    ).items[0].path,
    role.id,
  );
  assert.equal(
    runtime.validateSelectedRole(
      rows,
      { agentRoleId: role.id, agentRoleRevision: 3 },
      { ...context, machines: legacyMachines, agentCatalog: () => catalog },
    ).id,
    role.id,
  );
  emptyMachine.set(['agentConfig', 'a1'], { ...agent, name: 'Current Codex' });
  catalog = runtime.creationAgentCatalog(meta, legacyMachines).agents;
  assert.equal(
    runtime.roleOptions(rows, legacyMachines, 'm1', 'a1', catalog)[0].agentName,
    'Current Codex',
  );
  emptyMachine.delete(['agentConfig', 'a1']);
  meta.set(['e', 'agent-a1'], false);
  catalog = runtime.creationAgentCatalog(meta, legacyMachines).agents;
  assert.equal(
    runtime.roleOptions(rows, legacyMachines, 'm1', 'a1', catalog)[0].available,
    false,
  );
});

test('worktree uses the official remote Git-state read and writes the shared ProjectRef without local Git operations', async () => {
  resetRows();
  const meta = new Flock('project-meta');
  const options = runtime.creationOptions('m1:local:p1', meta, machines);
  const saved = new Flock('saved-meta');
  const replica = {
    flock: meta,
    client: {
      async append({ part }) {
        saved.importJson(
          JSON.parse(new TextDecoder().decode(part.body.subarray(4))),
        );
        return ok();
      },
    },
  };
  const args = {
    workspaceId: 'w1',
    projectId: options.project.id,
    sessionId: options.sessionId,
    userId: 'u1',
    machineId: 'm1',
    agentConfigId: 'a1',
    title: 'Task',
    useWorktree: true,
    agentRoleId: role.id,
    agentRoleRevision: 3,
    frozenRole: runtime.readAgentRoles(workspaceRows.scan(), 'u1')[0].runConfig,
  };
  gitState = { git: false };
  await assert.rejects(
    runtime.createSession(args, options, replica, grant, context),
    /worktree_unavailable/,
  );
  assert.equal(saved.scan().length, 0);
  gitState = { git: true, branches: ['main'] };
  const result = await runtime.createSession(
    args,
    options,
    replica,
    grant,
    context,
  );
  assert.equal(result.state, 'created');
  assert.equal(lastRpc.method, 'local-project/git-state');
  assert.deepEqual(lastRpc.params, {
    localProjectId: 'p1',
    requestedByUserId: 'u1',
  });
  const metadata = saved.get(['m', `session-${options.sessionId}`]);
  assert.equal(metadata.project.useWorktree, true);
  assert.equal(metadata.isWorktree, true);
  assert.equal(metadata.agentRoleId, role.id);
  assert.equal(metadata.agentRoleRevision, 3);
});
