import assert from 'node:assert/strict';
import { test } from 'node:test';
import { build } from 'esbuild';
import { Flock } from '@loro-dev/flock-wasm/base64';

const bundle = await build({
  entryPoints: [
    new URL(
      '../../../../packages/cloud-runtime/src/runtime/project-management.ts',
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
          namespace: 'project-test',
        }));
        b.onLoad({ filter: /.*/, namespace: 'project-test' }, () => ({
          contents:
            'export class StreamsClient { constructor(args) { return new globalThis.__projectManagementClient(args); } }',
        }));
      },
    },
  ],
});
const {
  projectManagement,
  managedProjects,
  worktreeScript,
  worktreePreflight,
} = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);

function fixture(workspaceId) {
  const meta = new Flock(`project-meta-${workspaceId}`),
    machine = new Flock(`project-machine-${workspaceId}`);
  meta.set(['e', 'machine-m1'], true);
  meta.set(['m', 'machine-m1'], {
    ownerUserId: 'owner',
    name: 'Studio',
    os: 'darwin',
  });
  machine.set(['localProject', 'p1'], {
    id: 'p1',
    name: 'Project',
    rootPath: '/source',
  });
  const contexts = {
    workspaceId,
    userId: 'owner',
    meta,
    machines: new Map([['m1', machine]]),
    projects: [],
    sessions: [
      {
        id: 's1',
        projectId: 'm1:local:p1',
        status: 'running',
        archived: false,
      },
    ],
    onlineMachineIds: [],
    signal: AbortSignal.timeout(5000),
    getGrant: async () => ({
      token: 'fixture-only',
      gatewayBaseUrl: 'https://project.invalid',
    }),
    cloud: async (method) => {
      assert.equal(method, 'list');
      return {
        access: [
          {
            machineId: 'm1',
            localProjectId: 'p1',
            ownerUserId: 'owner',
            sharedWithTeam: false,
          },
        ],
        repos: [],
      };
    },
    skills: async () => ({ items: [], truncated: false, incomplete: false }),
  };
  const durable = [],
    requests = [],
    envelopes = new Map();
  let failAppend = false,
    acceptUnknown = false,
    rpcResult;
  globalThis.__projectManagementClient = class {
    constructor({ url }) {
      this.stream = decodeURIComponent(url.split('/ds/lody/')[1]);
    }
    async create() {
      return { ok: true };
    }
    async bootstrap() {
      const flock = this.stream.endsWith(':meta') ? meta : machine;
      return {
        ok: true,
        result: {
          snapshotOffset: '1',
          snapshot: { body: flock.exportFile() },
          updates: [],
          nextOffset: '1',
          upToDate: true,
        },
      };
    }
    async append({ part }) {
      if (this.stream.includes(':rpc:req:')) {
        const envelope = JSON.parse(part.body);
        requests.push(envelope.params.request);
        envelopes.set(envelope.replyTo, envelope);
      } else {
        durable.push(part.body);
        assert.equal(
          new DataView(part.body.buffer, part.body.byteOffset).getUint32(0),
          part.body.length - 4,
        );
        if (!failAppend || acceptUnknown)
          machine.importJson(
            JSON.parse(new TextDecoder().decode(part.body.subarray(4))),
          );
        if (failAppend) return { ok: false, result: { code: 'timeout' } };
      }
      return { ok: true, result: {} };
    }
    async readOnce() {
      const envelope = envelopes.get(this.stream);
      assert.ok(envelope, 'Only a requested reply may be consumed');
      let result = rpcResult;
      if (result === undefined) {
        result = {
          clean: [
            {
              sessionId: 'clean',
              title: 'Clean',
              path: '/lody/worktrees/clean',
            },
          ],
          dirty: [
            {
              sessionId: 'dirty',
              title: 'Draft',
              path: '/lody/worktrees/dirty',
            },
          ],
          failed: [],
        };
        if (
          envelope.params.request.type.startsWith('local-project/set-worktree-')
        )
          result = envelope.params.request.config;
      }
      return {
        ok: true,
        result: {
          nextOffset: '1',
          payload: {
            body: new TextEncoder().encode(
              JSON.stringify({
                id: envelope.id,
                result: {
                  ok: true,
                  type: envelope.params.request.type,
                  result,
                },
              }),
            ),
          },
        },
      };
    }
  };
  return {
    contexts,
    meta,
    machine,
    durable,
    requests,
    fail: (accepted = false) => {
      failAppend = true;
      acceptUnknown = accepted;
    },
    response: (value) => {
      rpcResult = value;
    },
  };
}

test('removal persists intent only, keeps the original project and dirty worktrees, and waits for the machine', async () => {
  const fixtureData = fixture('remove-safe');
  const { contexts, machine, durable, requests } = fixtureData;
  contexts.sessions.push(
    {
      id: 'waiting',
      projectId: 'm1:local:p1',
      status: 'requestPermission',
      archived: false,
    },
    {
      id: 'archived',
      projectId: 'm1:local:p1',
      status: 'running',
      archived: true,
    },
    {
      id: 'other-project',
      projectId: 'm1:local:other',
      status: 'running',
      archived: false,
    },
  );
  const projectId = 'm1:local:p1';
  const inspection = await projectManagement(
    { kind: 'preflight', projectId },
    contexts,
  );
  assert.equal(inspection.preflight.dirty[0].sessionId, 'dirty');
  const result = await projectManagement(
    { kind: 'remove', projectId, cleanupWorktrees: false },
    contexts,
  );
  const command = machine.get(['cmd', 'deleteLocalProject', 'p1']);
  assert.equal(command.originalRootPath, '/source');
  assert.equal(
    command.cleanupWorktrees,
    undefined,
    'Cleanup is explicitly opt-in',
  );
  assert.equal(command.requestedBy, 'owner');
  assert.equal(
    machine.get(['localProject', 'p1']).rootPath,
    '/source',
    'Do not hide/remove the source before remote completion',
  );
  assert.equal(result.projects[0].removal.status, 'pending');
  assert.equal(
    result.projects[0].online,
    false,
    'Offline removal remains an honest pending row',
  );
  assert.equal(result.projects[0].conversationCount, 2);
  assert.deepEqual(
    result.projects[0].affectedSessions.map((session) => session.id),
    ['s1', 'waiting'],
  );
  assert.equal(
    result.projects[0].runningSessionCount,
    2,
    'Permission-waiting sessions are still active; archived/other projects are excluded',
  );
  assert.equal(durable.length, 1);
  assert.deepEqual(
    requests.map((row) => row.type),
    ['local-project/removal-preflight'],
  );
  machine.delete(['localProject', 'p1']);
  machine.set(['cmd', 'deleteLocalProject', 'p1'], {
    ...command,
    status: 'completed',
    cleanupResult: {
      completedAt: Date.now(),
      deleted: [],
      skippedDirty: [
        { sessionId: 'dirty', title: 'Draft', path: '/lody/worktrees/dirty' },
      ],
      failed: [
        {
          sessionId: 'failed',
          title: 'Busy',
          path: '/lody/worktrees/busy',
          message: 'Retry later',
        },
      ],
    },
  });
  const [completed] = managedProjects(contexts);
  assert.equal(completed.removal.status, 'completed');
  assert.equal(
    completed.rootPath,
    '/source',
    'Keep source identity with the cleanup result after the row is removed',
  );
  assert.equal(
    completed.removal.cleanupResult.skippedDirty[0].sessionId,
    'dirty',
  );
  assert.equal(
    completed.removal.cleanupResult.failed[0].message,
    'Retry later',
  );
});

test('cleanup opt-in repeats the remote preflight and rejects source-directory candidates', async () => {
  const data = fixture('cleanup-safe');
  const projectId = 'm1:local:p1';
  data.response({
    clean: [{ sessionId: 'original', title: 'Original', path: '/source/' }],
    dirty: [],
    failed: [],
  });
  await assert.rejects(
    projectManagement(
      { kind: 'remove', projectId, cleanupWorktrees: true },
      data.contexts,
    ),
    /invalid_project_cleanup/,
  );
  assert.equal(data.durable.length, 0);
  data.response(undefined);
  await projectManagement(
    { kind: 'remove', projectId, cleanupWorktrees: true },
    data.contexts,
  );
  assert.equal(
    data.machine.get(['cmd', 'deleteLocalProject', 'p1']).cleanupWorktrees,
    true,
  );
  assert.equal(
    data.requests.length,
    2,
    'A valid preflight must precede the only cleanup-enabled command',
  );
  assert.equal(data.durable.length, 1);
  assert.throws(
    () => worktreePreflight({ clean: [], dirty: [], failed: [{}] }, '/source'),
    /invalid_project_cleanup/,
  );
});

test('unowned or changed ownership never reaches project writes; scripts stay in exact remote wire shapes', async () => {
  const data = fixture('owner-safe'),
    projectId = 'm1:local:p1';
  const request = {
    kind: 'save-script',
    projectId,
    phase: 'cleanup',
    config: {
      scripts: { bash: 'echo clean', powershell: 'echo clean' },
      timeoutMs: 30000,
    },
  };
  await assert.rejects(
    projectManagement(request, { ...data.contexts, userId: 'teammate' }),
    /project_read_only/,
  );
  assert.equal(data.requests.length, 0);
  // Context was displayed as owned, but the fresh authoritative meta has changed.
  const displayedMeta = new Flock('displayed-meta');
  displayedMeta.importJson(data.meta.exportJson());
  data.meta.set(['m', 'machine-m1', 'ownerUserId'], 'new-owner');
  await assert.rejects(
    projectManagement(request, { ...data.contexts, meta: displayedMeta }),
    /project_read_only/,
  );
  assert.equal(data.requests.length, 0);
  await assert.rejects(
    projectManagement(
      { kind: 'remove', projectId, cleanupWorktrees: false },
      { ...data.contexts, meta: displayedMeta },
    ),
    /project_read_only/,
  );
  assert.equal(data.durable.length, 0);
  data.meta.set(['m', 'machine-m1', 'ownerUserId'], 'owner');
  await projectManagement(request, data.contexts);
  assert.deepEqual(data.requests[0], {
    type: 'local-project/set-worktree-cleanup',
    localProjectId: 'p1',
    requestedByUserId: 'owner',
    config: request.config,
    workspaceId: 'owner-safe',
    machineId: 'm1',
  });
  assert.equal(
    data.durable.length,
    0,
    'A script save must not append a removal command',
  );
  for (const config of [
    { scripts: [] },
    { scripts: { zsh: 'command' } },
    { scripts: { bash: 'a\0b' } },
    { scripts: {}, timeoutMs: -1 },
  ])
    assert.throws(() => worktreeScript(config), /invalid_project_script/);
});

test('a lost durable ACK reconciles the recorded request instead of replaying it', async () => {
  const data = fixture('unknown-safe'),
    projectId = 'm1:local:p1';
  const request = { kind: 'remove', projectId, cleanupWorktrees: false };
  const displayed = new Flock('unknown-displayed');
  displayed.importJson(data.machine.exportJson());
  data.contexts.machines.set('m1', displayed);
  data.fail(true);
  await assert.rejects(
    projectManagement(request, data.contexts),
    /project_write_unknown/,
  );
  const result = await projectManagement({ kind: 'list' }, data.contexts);
  assert.equal(result.projects[0].removal.status, 'pending');
  assert.equal(data.durable.length, 1);
  await assert.rejects(
    projectManagement(request, data.contexts),
    /project_read_only/,
  );
  assert.equal(data.durable.length, 1);
  const failed = fixture('unknown-not-recorded');
  failed.fail();
  await assert.rejects(
    projectManagement(request, failed.contexts),
    /project_write_unknown/,
  );
  await assert.rejects(
    projectManagement(request, failed.contexts),
    /project_write_unknown/,
  );
  assert.equal(
    failed.durable.length,
    1,
    'An uncertain failed append is never automatically repeated',
  );
  const unavailable = await projectManagement(
    { kind: 'list' },
    failed.contexts,
  );
  assert.equal(
    unavailable.projects[0].removal.status,
    'unknown',
    'Unconfirmed requests cannot appear ready for another removal',
  );
});

test('Skills use the same injected Composer catalog and account teardown blocks an in-flight write', async () => {
  const data = fixture('skill-scope'),
    projectId = 'm1:local:p1';
  const skills = {
    items: [
      {
        kind: 'skill',
        name: 'review',
        path: '.agents/skills/review/SKILL.md',
        subtitle: 'Review',
        insertText: '$review',
        content: 'Review the code',
      },
    ],
    truncated: false,
    incomplete: false,
  };
  let skillTarget;
  data.contexts.skills = async (id) => {
    skillTarget = id;
    return skills;
  };
  const result = await projectManagement(
    { kind: 'skills', projectId },
    data.contexts,
  );
  assert.equal(skillTarget, projectId);
  assert.equal(result.skills, skills);
  data.contexts.assertCurrent = () => {
    throw new Error('account_changed');
  };
  await assert.rejects(
    projectManagement(
      { kind: 'remove', projectId, cleanupWorktrees: false },
      data.contexts,
    ),
    /account_changed/,
  );
  assert.equal(data.durable.length, 0);
});

test('GitHub projects with no history appear from the official workspace list; stale links cannot enable writes', async () => {
  const data = fixture('github-projects');
  data.contexts.projects = [
    {
      id: 'github:LodyAI/Removed',
      machineId: '',
      rootPath: '',
      name: 'Removed',
      repoFullName: 'LodyAI/Removed',
    },
  ];
  const calls = [];
  data.contexts.cloud = async (method, values) => {
    calls.push({ method, values });
    if (method === 'list')
      return {
        access: [],
        repos: [
          {
            repoFullName: 'LodyAI/Lody',
            name: 'Lody',
            worktreeSetup: { scripts: { bash: 'pnpm install' } },
          },
        ],
      };
    return { updated: true };
  };
  const result = await projectManagement({ kind: 'list' }, data.contexts);
  assert.equal(
    result.projects.find((project) => project.id === 'github:LodyAI/Lody')
      .conversationCount,
    0,
  );
  assert.equal(
    result.projects.find((project) => project.id === 'github:LodyAI/Removed')
      .owned,
    false,
  );
  await assert.rejects(
    projectManagement(
      {
        kind: 'save-script',
        projectId: 'github:LodyAI/Removed',
        phase: 'setup',
        config: { scripts: {} },
      },
      data.contexts,
    ),
    /project_read_only/,
  );
  assert.ok(calls.every((call) => call.method === 'list'));
  await projectManagement(
    {
      kind: 'save-script',
      projectId: 'github:LodyAI/Lody',
      phase: 'cleanup',
      config: { scripts: { powershell: 'echo cleanup' } },
    },
    data.contexts,
  );
  assert.deepEqual(calls.at(-1), {
    method: 'save-github-script',
    values: {
      repoFullName: 'LodyAI/Lody',
      phase: 'cleanup',
      config: { scripts: { powershell: 'echo cleanup' } },
    },
  });
  assert.equal(
    data.requests.length,
    0,
    'GitHub settings go through the authenticated Cloud boundary',
  );
});

test('large Unicode and maximum escaped two-shell scripts are saved remotely without truncation', async () => {
  const data = fixture('large-scripts');
  const saved = [];
  data.contexts.cloud = async (method, values) => {
    if (method === 'list')
      return {
        access: [],
        repos: [{ repoFullName: 'LodyAI/Lody', name: 'Lody' }],
      };
    assert.equal(method, 'save-github-script');
    saved.push(values.config);
    return { updated: true };
  };
  const configs = [
    { scripts: { bash: '界'.repeat(45000) } },
    { scripts: { bash: 'a'.repeat(65536), powershell: 'b'.repeat(65536) } },
    {
      scripts: {
        bash: '\u0001'.repeat(65536),
        powershell: '\u0001'.repeat(65536),
      },
    },
  ];
  for (const config of configs) {
    const envelope = JSON.stringify({
      workspaceId: data.contexts.workspaceId,
      editorId: 'script-editor',
      request: {
        kind: 'save-script',
        projectId: 'github:LodyAI/Lody',
        phase: 'setup',
        config,
      },
    });
    assert.ok(Buffer.byteLength(envelope) > 128 * 1024);
    await projectManagement(JSON.parse(envelope).request, data.contexts);
    assert.deepEqual(
      saved.at(-1),
      config,
      'Every decoded script character reaches Cloud unchanged',
    );
  }
  await assert.rejects(
    projectManagement(
      {
        kind: 'save-script',
        projectId: 'github:LodyAI/Lody',
        phase: 'setup',
        config: { scripts: { bash: 'a\u0301'.repeat(32769) } },
      },
      data.contexts,
    ),
    /invalid_project_script/,
  );
  assert.equal(
    saved.length,
    configs.length,
    'An oversized UTF-16 script never reaches a mutation',
  );
});
