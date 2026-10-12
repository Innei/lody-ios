import assert from 'node:assert/strict';
import { test } from 'node:test';
import { build } from 'esbuild';
import { Flock } from '@loro-dev/flock-wasm/base64';

const bundle = await build({
  entryPoints: [
    new URL(
      '../../../../packages/cloud-runtime/src/runtime/create-session.ts',
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
            'export class StreamsClient { constructor(args) { return new globalThis.__catalogClient(args); } }',
        }));
      },
    },
  ],
});
const { creationOptions, createSession, creationAgentCatalog } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);

function fixture() {
  const meta = new Flock('meta');
  const machine = new Flock('machine');
  meta.set(['e', 'machine-m1'], true);
  meta.set(['m', 'machine-m1'], { name: 'Test Mac' });
  machine.set(['localProject', 'p1'], {
    name: 'Project',
    rootPath: '/project',
  });
  const claude = {
    id: 'claude-legacy',
    machineId: 'm1',
    name: 'Claude Code',
    cliType: 'builtin',
    agentType: 'claude',
    env: { SECRET: 'never-project-environment' },
    prompt: 'never-project-prompt',
    runtimeOverrides: { cliPath: 'never-project-launch-config' },
  };
  meta.set(['e', `agent-${claude.id}`], true);
  meta.set(['m', `agent-${claude.id}`], claude);
  machine.set(['agentConfig', 'codex'], {
    id: 'codex',
    machineId: 'm1',
    name: 'Codex',
    cliType: 'builtin',
    agentType: 'codex',
  });
  machine.set(['acpCapability', 'claude'], {
    cliType: 'builtin',
    agentType: 'claude',
    models: [{ modelId: 'claude-test', name: 'Claude Test' }],
    fetchedAt: 1,
  });
  return { meta, machine, machines: new Map([['m1', machine]]), claude };
}

test('legacy Claude and Flock Codex are selectable for chat, local and GitHub sessions without leaking launch fields', () => {
  const { meta, machine, machines } = fixture();
  const beforeMeta = meta.exportJson();
  const beforeMachine = machine.exportJson();
  for (const projectId of [undefined, 'm1:local:p1', 'github:owner/repo']) {
    const options = creationOptions(projectId, meta, machines);
    assert.deepEqual(
      options.agents.map((agent) => agent.name).sort(),
      ['Claude Code', 'Codex'],
      'desktop merges both storage generations',
    );
    const claude = options.agents.find((agent) => agent.agentType === 'claude');
    assert.equal(claude.id, 'claude-legacy');
    assert.equal(claude.machineName, 'Test Mac');
    assert.equal(
      options.capabilities.find(
        (capability) => capability.agentType === 'claude',
      ).models[0].id,
      'claude-test',
    );
    assert.equal(JSON.stringify(options).includes('never-project'), false);
  }
  assert.deepEqual(
    meta.exportJson(),
    beforeMeta,
    'reading never migrates writes',
  );
  assert.deepEqual(machine.exportJson(), beforeMachine);
});

test('Flock overrides legacy metadata by config ID before local project filtering; deleted and unresolved configs stay hidden', () => {
  const { meta, machine, machines, claude } = fixture();
  const other = new Flock('other');
  machines.set('m2', other);
  meta.set(['e', 'machine-m2'], true);
  meta.set(['m', 'machine-m2'], { name: 'Other Mac' });
  other.set(['agentConfig', claude.id], {
    ...claude,
    machineId: 'm2',
    name: 'Current Claude',
  });
  assert.equal(
    creationOptions(undefined, meta, machines).agents.find(
      (agent) => agent.id === claude.id,
    ).machineId,
    'm2',
  );
  assert.deepEqual(
    creationOptions('m1:local:p1', meta, machines).agents.map(
      (agent) => agent.id,
    ),
    ['codex'],
    'the owning machine cannot recover a shadowed legacy target',
  );
  other.delete(['agentConfig', claude.id]);
  meta.set(['m', `agent-${claude.id}`, 'name'], 'Renamed Claude');
  assert.equal(
    creationOptions(undefined, meta, machines).agents.find(
      (agent) => agent.id === claude.id,
    ).name,
    'Renamed Claude',
    'field-level metadata overrides the base record',
  );
  meta.set(['e', `agent-${claude.id}`], false);
  meta.set(['e', 'agent-unresolved'], true);
  meta.set(['m', 'agent-unresolved'], {
    ...claude,
    id: 'unresolved',
    machineId: 'missing-machine',
  });
  assert.deepEqual(
    creationOptions(undefined, meta, machines).agents.map((agent) => agent.id),
    ['codex'],
  );
  machine.set(['agentConfig', 'malformed'], { ...claude, id: 'other-id' });
  const catalog = creationAgentCatalog(meta, machines);
  assert.deepEqual(
    catalog.agents.map((agent) => agent.id),
    ['codex'],
  );
  assert.equal(catalog.diagnostics.legacy.rejected.machine_unavailable, 1);
  assert.equal(catalog.diagnostics.machines.m1.rejected.identity_mismatch, 1);
  assert.equal(
    JSON.stringify(catalog.diagnostics).includes('never-project'),
    false,
  );
});

test('a legacy assistant can create a session and persists the daemon-resolvable config ID', async () => {
  const { meta, machines } = fixture();
  const options = creationOptions(undefined, meta, machines);
  const ok = (result = {}) => ({ ok: true, result });
  let streamsCreated = 0;
  globalThis.__catalogClient = class {
    async create() {
      streamsCreated++;
      return ok();
    }
  };
  try {
    const result = await createSession(
      {
        workspaceId: 'workspace',
        sessionId: options.sessionId,
        machineId: 'm1',
        agentConfigId: 'claude-legacy',
        userId: 'user',
        title: 'Claude session',
      },
      options,
      { flock: meta, client: { append: async () => ok() } },
      async () => ({
        token: 'synthetic',
        gatewayBaseUrl: 'https://example.invalid',
      }),
    );
    assert.equal(result.state, 'created');
    assert.equal(streamsCreated, 1);
    const persisted = meta.get(['m', `session-${options.sessionId}`]);
    assert.equal(persisted.agentConfigId, 'claude-legacy');
    assert.equal(persisted.machineId, 'm1');
    assert.equal(persisted.agentType, 'claude');
    assert.equal(JSON.stringify(persisted).includes('never-project'), false);
  } finally {
    delete globalThis.__catalogClient;
  }
});
