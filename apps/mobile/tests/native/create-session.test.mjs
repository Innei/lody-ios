import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { Flock } from '@loro-dev/flock-wasm/base64';
import { LoroDoc } from 'loro-crdt/base64';

test('create a project session, open its empty history and dispatch the first turn; reject invalid targets and never replay an uncertain create', async () => {
  const meta = new Flock('meta'),
    machine = new Flock('machine');
  meta.set(['e', 'machine-m1'], true);
  meta.set(['m', 'machine-m1'], { name: 'Test Mac' });
  machine.set(['localProject', 'p1'], {
    name: 'Project',
    rootPath: '/project',
  });
  machine.set(['agentConfig', 'c1'], {
    id: 'c1',
    name: 'Codex',
    machineId: 'm1',
    cliType: 'builtin',
    agentType: 'codex',
    env: { SECRET: 'never-project' },
  });
  machine.set(['agentConfig', 'wrong-machine'], {
    id: 'wrong-machine',
    name: 'Invalid',
    machineId: 'm2',
    cliType: 'builtin',
    agentType: 'codex',
  });
  machine.set(['acpCapability', 'codex'], {
    cliType: 'builtin',
    agentType: 'codex',
    fetchedAt: 1,
    models: [{ modelId: 'gpt-test', name: 'GPT Test' }],
    modelReasoningEfforts: { 'gpt-test': ['low', 'high'] },
    configOptions: [{ id: 'effort', category: 'thought_level' }],
  });
  const machines = new Map([['m1', machine]]);
  const remote = new Flock('remote');
  remote.importFile(meta.exportFile());
  const history = new LoroDoc();
  const order = [];
  let rpc,
    loseAck = false,
    failCreate = false,
    metaAppends = 0;
  const ok = (result = {}) => ({ ok: true, result });
  const unframe = (body) => {
    assert.equal(
      new DataView(body.buffer, body.byteOffset).getUint32(0, false),
      body.length - 4,
    );
    return body.subarray(4);
  };
  globalThis.__creationClient = class {
    constructor({ url }) {
      this.url = decodeURIComponent(url);
    }
    async create() {
      order.push('stream');
      return failCreate ? { ok: false, result: { code: 'forbidden' } } : ok();
    }
    async append({ part }) {
      if (this.url.includes(':rpc:req:')) {
        rpc = JSON.parse(part.body);
        const persisted = remote.get(['m', `session-${rpc.params.sessionId}`]);
        assert.equal(persisted.agentConfigId, 'c1');
        assert.equal(history.toJSON().history[0].id, rpc.params.userTurnId);
      } else history.import(unframe(part.body));
      return ok();
    }
    async bootstrap() {
      return ok({
        snapshotOffset: '-1',
        nextOffset: '-1',
        upToDate: true,
        updates: [],
      });
    }
    readOnce() {
      if (this.url.includes(':rpc:res:'))
        return Promise.resolve(
          ok({
            nextOffset: '1',
            payload: {
              body: new TextEncoder().encode(
                JSON.stringify([{ id: rpc.id, result: { accepted: true } }]),
              ),
            },
          }),
        );
      return new Promise(() => {});
    }
  };
  const bundle = await build({
    stdin: {
      contents: `export * from './apps/mobile/modules/lody-kit/data-runtime/create-session'; export { openSession, sendTurn, closeSession } from './apps/mobile/modules/lody-kit/data-runtime/session';`,
      resolveDir: process.cwd(),
    },
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
              'export const StreamsClient = globalThis.__creationClient',
          }));
        },
      },
    ],
  });
  const runtime = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );
  const options = runtime.creationOptions('m1:local:p1', meta, machines);
  assert.equal(options.agents.length, 1);
  assert.equal(options.capabilities[0].reasoningEffortConfigId, 'effort');
  assert.equal(JSON.stringify(options).includes('never-project'), false);
  const replica = {
    flock: meta,
    client: {
      async append({ part }) {
        metaAppends++;
        order.push('metadata');
        remote.importJson(
          JSON.parse(new TextDecoder().decode(unframe(part.body))),
        );
        return loseAck ? { ok: false, result: { code: 'timeout' } } : ok();
      },
    },
  };
  const grant = async () => ({
    token: 'synthetic',
    gatewayBaseUrl: 'https://example.invalid',
  });
  const args = {
    workspaceId: 'w1',
    projectId: options.project.id,
    sessionId: options.sessionId,
    machineId: 'm1',
    agentConfigId: 'c1',
    userId: 'u1',
    title: ' First task ',
  };
  await assert.rejects(
    runtime.createSession(
      { ...args, machineId: 'm2' },
      options,
      replica,
      grant,
    ),
    /invalid_session/,
  );
  assert.equal(order.length, 0);
  const result = await runtime.createSession(args, options, replica, grant);
  assert.equal(result.state, 'created');
  assert.deepEqual(order, ['stream', 'metadata']);
  const saved = remote.get(['m', `session-${result.session.id}`]);
  assert.equal(saved.title, 'First task');
  assert.equal(saved.project.localProjectId, 'p1');
  assert.equal(remote.get(['e', `session-${result.session.id}`]), true);
  assert.equal(saved.latestUserMsgId, undefined);
  let live;
  const ready = new Promise((resolve) => {
    live = resolve;
  });
  await runtime.openSession(
    result.session.id,
    'w1',
    grant,
    (event) => {
      const value = JSON.parse(event.session);
      if (value.status === 'live') live(value);
    },
    async (id, turnId) => {
      assert.equal(history.toJSON().history[0].id, turnId);
      remote.set(['m', `session-${id}`, 'latestUserMsgId'], turnId);
    },
  );
  assert.equal((await ready).entries.length, 0);
  const sent = await runtime.sendTurn({
    sessionId: result.session.id,
    machineId: 'm1',
    userId: 'u1',
    text: 'Hello',
    cliType: result.session.cliType,
    agentType: result.session.agentType,
  });
  assert.equal(sent.state, 'accepted');
  assert.equal(history.toJSON().history[0].items[0].text, 'Hello');
  runtime.closeSession();
  await assert.rejects(
    runtime.createSession(args, options, replica, grant),
    /session_already_exists/,
  );
  assert.equal(metaAppends, 1);
  failCreate = true;
  const failedId = crypto.randomUUID();
  await assert.rejects(
    runtime.createSession(
      { ...args, sessionId: failedId },
      options,
      replica,
      grant,
    ),
    /forbidden/,
  );
  assert.equal(meta.get(['e', `session-${failedId}`]), undefined);
  assert.equal(metaAppends, 1);
  failCreate = false;
  loseAck = true;
  const unknownId = crypto.randomUUID();
  const uncertain = await runtime.createSession(
    { ...args, sessionId: unknownId },
    options,
    replica,
    grant,
  );
  assert.equal(uncertain.state, 'unknown');
  assert.equal(uncertain.session.id, unknownId);
  assert.equal(
    meta.get(['e', `session-${unknownId}`]),
    undefined,
    'An uncertain write must not publish a phantom local session',
  );
  assert.equal(remote.get(['e', `session-${unknownId}`]), true);
  assert.equal(metaAppends, 2);
  await assert.rejects(
    runtime.createSession(
      { ...args, sessionId: unknownId },
      options,
      replica,
      grant,
    ),
    /session_already_exists/,
  );
  assert.equal(metaAppends, 2);
  machine.set(['cmd', 'deleteLocalProject', 'p1'], { requestedAt: 1 });
  assert.throws(
    () => runtime.creationOptions('m1:local:p1', meta, machines),
    /project_unavailable/,
  );
  meta.set(['e', 'session-github'], true);
  meta.set(['m', 'session-github'], {
    machineId: 'm1',
    project: { kind: 'github', repoFullName: 'example/repo', branch: 'main' },
  });
  const github = runtime.creationOptions('github:example/repo', meta, machines);
  const githubArgs = {
    ...args,
    projectId: github.project.id,
    sessionId: github.sessionId,
  };
  await assert.rejects(
    runtime.createSession(githubArgs, github, replica, grant),
    /invalid_session/,
  );
  loseAck = false;
  const githubResult = await runtime.createSession(
    { ...githubArgs, branch: 'develop' },
    github,
    replica,
    grant,
  );
  assert.equal(githubResult.state, 'created');
  const githubMeta = remote.get(['m', `session-${github.sessionId}`]);
  assert.equal(githubMeta.project.branch, 'develop');
  assert.equal(githubMeta.isWorktree, true);
  delete globalThis.__creationClient;
});
