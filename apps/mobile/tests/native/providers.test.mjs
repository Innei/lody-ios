import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { Flock } from '@loro-dev/flock-wasm/base64';

const bundle = await build({
  entryPoints: [
    new URL(
      '../../../../packages/cloud-runtime/src/runtime/providers.ts',
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
          path: 'mock',
          namespace: 'test',
        }));
        builder.onLoad({ filter: /.*/, namespace: 'test' }, () => ({
          contents:
            'export class StreamsClient { constructor(args) { return new globalThis.__providersClient(args); } }',
        }));
      },
    },
  ],
});
const {
  providersCommand,
  providerSummaries,
  providerProgress,
  validateProvider,
  stopProviderOperations,
} = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);

const initial = (id = 'a1', agentType = 'claude') => ({
  id,
  machineId: 'm1',
  name: 'Provider',
  cliType: 'builtin',
  agentType,
  env: { ANTHROPIC_AUTH_TOKEN: 'fixture-secret' },
  prompt: 'Keep changes focused.',
});

function environment(configs = [initial()]) {
  const meta = new Flock('providers-meta');
  meta.set(['e', 'machine-m1'], true);
  meta.set(['m', 'machine-m1'], {
    name: 'Studio Mac',
    ownerUserId: 'owner',
    protocolCapabilities: {
      providerSetup: 1,
      codexAuthProfiles: 1,
      piExtensions: 1,
      acpProtocolAuthentication: 2,
    },
  });
  const machine = new Flock('providers-machine');
  for (const config of configs)
    machine.set(['agentConfig', config.id], {
      ...config,
      futureField: { keep: true },
    });
  const streams = new Map(),
    requests = [];
  let failure = false,
    rpcHandler;
  globalThis.__providersClient = class {
    constructor({ url }) {
      this.stream = decodeURIComponent(url).split('/ds/lody/')[1];
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
    async create() {
      streams.set(this.stream, []);
      return { ok: true, result: {} };
    }
    async append({ part }) {
      if (part.contentType === 'application/octet-stream') {
        if (failure) return { ok: false, result: { code: 'network_error' } };
        assert.equal(
          new DataView(part.body.buffer, part.body.byteOffset).getUint32(0),
          part.body.length - 4,
        );
        machine.importJson(
          JSON.parse(new TextDecoder().decode(part.body.subarray(4))),
        );
      } else {
        const request = JSON.parse(part.body);
        requests.push(request);
        if (rpcHandler) await rpcHandler(request, streams);
        else
          streams.get(request.replyTo).push({
            id: request.id,
            result: {
              type: `${request.method}_response`,
              machineId: 'm1',
              configId: request.params.configId,
              agentType: request.params.agentType ?? 'claude',
              requestId: request.params.requestId,
              success: true,
              status: 'installed',
              disposition: 'cancelled',
            },
          });
      }
      return { ok: true, result: {} };
    }
    async readOnce({ offset }) {
      const index = offset === '-1' ? 0 : Number(offset);
      const rows = streams.get(this.stream) ?? [];
      const value = rows[index];
      return {
        ok: true,
        result: {
          nextOffset: String(value ? index + 1 : index),
          upToDate: index + 1 >= rows.length,
          ...(value
            ? {
                payload: {
                  body: new TextEncoder().encode(JSON.stringify(value)),
                },
              }
            : {}),
        },
      };
    }
  };
  const context = {
    workspaceId: 'w1',
    userId: 'owner',
    meta,
    machines: new Map([['m1', machine]]),
    presence: { state: 'live', onlineMachineIds: ['m1'] },
    operations: new Map(),
    getGrant: async () => ({
      token: 'fixture',
      gatewayBaseUrl: 'https://example.invalid',
    }),
    signal: AbortSignal.timeout(10000),
  };
  const scope = { workspaceId: 'w1', machineId: 'm1' };
  return {
    context,
    scope,
    meta,
    machine,
    streams,
    requests,
    setFailure: (value) => {
      failure = value;
    },
    onRpc: (handler) => {
      rpcHandler = handler;
    },
  };
}

test('summaries and progress exclude credentials, launch paths, raw output and authentication keys', () => {
  const env = environment();
  const summaries = providerSummaries(env.machine, 'm1');
  assert.equal(summaries[0].name, 'Provider');
  assert.doesNotMatch(
    JSON.stringify(summaries),
    /fixture-secret|env|prompt|futureField/,
  );
  assert.equal(providerSummaries(env.machine, 'other').length, 0);
  const progress = providerProgress({
    status: 'input-required',
    output: 'fixture-secret',
    error: 'fixture-secret',
    authorizationCodePublicKey: { secret: 'no' },
    form: {
      fields: [
        {
          id: 'key',
          type: 'secret',
          label: 'API Key',
          required: true,
          defaultValue: 'fixture-secret',
        },
      ],
    },
  });
  assert.equal(progress.form.fields[0].type, 'secret');
  assert.doesNotMatch(
    JSON.stringify(progress),
    /fixture-secret|PublicKey|output|error/,
  );
});

test('save uses fresh owner and config revisions, preserves unknown fields, invalidates launch capability caches', async () => {
  const env = environment();
  const old = await providersCommand(
    { ...env.scope, action: 'get', id: 'a1' },
    env.context,
  );
  env.machine.set(['agentConfig', 'a1'], {
    ...env.machine.get(['agentConfig', 'a1']),
    name: 'Changed elsewhere',
  });
  await assert.rejects(
    providersCommand(
      {
        ...env.scope,
        action: 'save',
        config: { ...old.config, name: 'My Provider' },
        revision: old.revision,
      },
      env.context,
    ),
    /provider_conflict/,
  );
  const fresh = await providersCommand(
    { ...env.scope, action: 'get', id: 'a1' },
    env.context,
  );
  env.machine.set(['acpCapability', 'a1'], { models: ['old-model'] });
  env.machine.set(['acpModelCapability', 'a1'], { model: 'old-model' });
  const updated = {
    ...fresh.config,
    env: { ANTHROPIC_AUTH_TOKEN: 'fixture-replacement' },
    titleGeneration: { configOptionValues: { model: 'new-model', fast: true } },
  };
  await providersCommand(
    { ...env.scope, action: 'save', config: updated, revision: fresh.revision },
    env.context,
  );
  assert.deepEqual(env.machine.get(['agentConfig', 'a1']).futureField, {
    keep: true,
  });
  assert.deepEqual(
    env.machine.get(['agentConfig', 'a1']).titleGeneration,
    updated.titleGeneration,
  );
  assert.equal(env.machine.get(['acpCapability', 'a1']), undefined);
  assert.equal(env.machine.get(['acpModelCapability', 'a1']), undefined);
  env.meta.set(['m', 'machine-m1', 'ownerUserId'], 'another-owner');
  await assert.rejects(
    providersCommand({ ...env.scope, action: 'delete', id: 'a1' }, env.context),
    /provider_read_only/,
  );
  assert.ok(env.machine.get(['agentConfig', 'a1']));
});

test('legal Unicode configuration survives create, read, update and delete above the ordinary native byte budget', async () => {
  const env = environment([]);
  const config = {
    ...initial('unicode'),
    env: {
      EXTRA_ONE: '界'.repeat(32000),
      EXTRA_TWO: '界'.repeat(32000),
      EXTRA_THREE: '界'.repeat(32000),
    },
    prompt: '界'.repeat(32000),
  };
  const request = { ...env.scope, action: 'save', config };
  assert.ok(JSON.stringify(validateProvider(config)).length < 128 * 1024);
  const bytes = Buffer.byteLength(JSON.stringify(request), 'utf8');
  assert.ok(bytes > 128 * 1024);
  assert.ok(bytes < 400 * 1024);
  await providersCommand(request, env.context);
  const read = await providersCommand(
    { ...env.scope, action: 'get', id: config.id },
    env.context,
  );
  assert.deepEqual(read.config, config);
  assert.equal(read.overLimit, undefined);
  const updated = { ...read.config, name: 'Unicode provider updated' };
  await providersCommand(
    { ...request, config: updated, revision: read.revision },
    env.context,
  );
  const fresh = await providersCommand(
    { ...env.scope, action: 'get', id: config.id },
    env.context,
  );
  assert.deepEqual(fresh.config, updated);
  await providersCommand(
    { ...env.scope, action: 'delete', id: config.id, revision: fresh.revision },
    env.context,
  );
  assert.equal(env.machine.get(['agentConfig', config.id]), undefined);
});

test('larger desktop configurations stay listed, preserve full supported fields and reject a shortened overwrite', async () => {
  const configs = [
    { ...initial('long-prompt'), prompt: '界'.repeat(32001) },
    { ...initial('long-name'), name: `  ${'A'.repeat(201)}  ` },
    {
      ...initial('many-env'),
      env: Object.fromEntries(
        Array.from({ length: 129 }, (_, i) => [`KEY_${i}`, 'value']),
      ),
    },
    {
      ...initial('long-env'),
      env: { ANTHROPIC_AUTH_TOKEN: 'fixture-large-secret'.repeat(2000) },
    },
    {
      ...initial('large-document'),
      env: Object.fromEntries(
        Array.from({ length: 4 }, (_, i) => [`KEY_${i}`, 'a'.repeat(32000)]),
      ),
      prompt: 'b'.repeat(32000),
    },
    {
      ...initial('custom-args'),
      cliType: 'custom',
      agentType: 'custom-agent',
      customAcp: {
        command: ' custom-agent ',
        args: Array.from({ length: 129 }, () => '--argument'),
      },
    },
    {
      ...initial('raw-budget'),
      cliType: 'custom',
      agentType: 'custom-agent',
      env: {
        ONE: 'a'.repeat(32000),
        TWO: 'b'.repeat(32000),
        THREE: 'c'.repeat(32000),
      },
      prompt: 'd'.repeat(32000),
      customAcp: { command: `${'　'.repeat(4000)}agent` },
    },
    {
      ...initial('title-options'),
      titleGeneration: { configOptionValues: { option: '界'.repeat(4097) } },
    },
    {
      ...initial('pi-extensions', 'pi'),
      runtimeOverrides: {
        piExtensions: Array.from({ length: 33 }, (_, i) => `/extensions/${i}`),
      },
    },
  ];
  const env = environment(configs);
  const list = await providersCommand(
    { action: 'list', workspaceId: env.scope.workspaceId },
    env.context,
  );
  assert.equal(list.providers.length, configs.length);
  assert.ok(list.providers.every((provider) => provider.overLimit === true));
  assert.doesNotMatch(
    JSON.stringify(list.providers),
    /fixture-large-secret|custom-agent |extensions\/|configOptionValues/,
  );
  for (const config of configs) {
    const reply = await providersCommand(
      { ...env.scope, action: 'get', id: config.id },
      env.context,
    );
    assert.deepEqual(reply.config, config);
    assert.equal(reply.overLimit, true);
    await assert.rejects(
      providersCommand(
        {
          ...env.scope,
          action: 'save',
          config: initial(config.id, config.agentType),
          revision: reply.revision,
        },
        env.context,
      ),
      /provider_over_limit/,
    );
    await assert.rejects(
      providersCommand(
        { ...env.scope, action: 'verify', id: config.id },
        env.context,
      ),
      /provider_over_limit/,
    );
    assert.equal(
      env.machine.get(['agentConfig', config.id]).futureField.keep,
      true,
    );
    assert.deepEqual(
      (
        await providersCommand(
          { ...env.scope, action: 'get', id: config.id },
          env.context,
        )
      ).config,
      config,
    );
  }
  assert.equal(env.requests.length, 0);
});

test('a failed append is unknown, never silently replayed; replaced runtime is fenced before writes', async () => {
  const env = environment();
  const fresh = await providersCommand(
    { ...env.scope, action: 'get', id: 'a1' },
    env.context,
  );
  env.setFailure(true);
  await assert.rejects(
    providersCommand(
      {
        ...env.scope,
        action: 'save',
        config: { ...fresh.config, name: 'New' },
        revision: fresh.revision,
      },
      env.context,
    ),
    /provider_write_unknown/,
  );
  assert.equal(env.machine.get(['agentConfig', 'a1']).name, 'Provider');
  env.setFailure(false);
  env.context.assertCurrent = () => {
    throw new Error('runtime_replaced');
  };
  await assert.rejects(
    providersCommand(
      {
        ...env.scope,
        action: 'save',
        config: { ...fresh.config, name: 'New' },
        revision: fresh.revision,
      },
      env.context,
    ),
    /runtime_replaced/,
  );
  assert.equal(env.machine.get(['agentConfig', 'a1']).name, 'Provider');
});

test('queued provider tasks retry and cancellation is durable; final builtin deletion records opt-out', async () => {
  const env = environment([initial('a1', 'kimi'), initial('a2', 'kimi')]);
  const config = { ...initial('task', 'pi'), env: {} };
  await providersCommand(
    { ...env.scope, action: 'save', config, queue: true },
    env.context,
  );
  assert.equal(env.machine.get(['agentConfig', 'task']), undefined);
  assert.equal(env.machine.get(['providerSetup', 'task']).status, 'queued');
  const task = env.machine.get(['providerSetup', 'task']);
  env.machine.set(['providerSetup', 'task'], {
    ...task,
    status: 'failed',
    failureCode: 'runtime-install-failed',
  });
  await providersCommand(
    { ...env.scope, action: 'retry', id: 'task' },
    env.context,
  );
  assert.equal(env.machine.get(['providerSetup', 'task']).attempt, 2);
  assert.equal(
    env.machine.get(['providerSetup', 'task']).failureCode,
    undefined,
  );
  await providersCommand(
    { ...env.scope, action: 'delete', id: 'task' },
    env.context,
  );
  assert.equal(env.machine.get(['providerSetupCancellation', 'task']).v, 1);
  assert.equal(env.machine.get(['providerSetup', 'task']), undefined);
  await providersCommand(
    { ...env.scope, action: 'delete', id: 'a1' },
    env.context,
  );
  assert.equal(env.machine.get(['builtinAgentOptOut', 'kimi']), undefined);
  await providersCommand(
    { ...env.scope, action: 'delete', id: 'a2' },
    env.context,
  );
  assert.equal(env.machine.get(['builtinAgentOptOut', 'kimi']).v, 1);
});

test('runtime commands negotiate capabilities, use official RPC progress and do not install on iPhone', async () => {
  const env = environment();
  env.context.presence = { state: 'live', onlineMachineIds: [] };
  await assert.rejects(
    providersCommand(
      { ...env.scope, action: 'install', id: 'a1' },
      env.context,
    ),
    /provider_machine_offline/,
  );
  assert.equal(env.requests.length, 0);
  env.context.presence = { state: 'live', onlineMachineIds: ['m1'] };
  env.onRpc((request, streams) => {
    streams.get(request.replyTo).push({
      id: request.id,
      result: {
        type: 'machine/acp-binary-progress',
        machineId: 'm1',
        agentType: 'claude',
        status: 'downloading',
        percent: 42,
        output: 'ignored',
      },
    });
    streams.get(request.replyTo).push({
      id: request.id,
      result: {
        type: 'machine/acp-binary-install_response',
        machineId: 'm1',
        agentType: 'claude',
        success: false,
        error: 'fixture-secret',
      },
    });
  });
  const started = await providersCommand(
    { ...env.scope, action: 'install', id: 'a1' },
    env.context,
  );
  assert.equal(env.requests[0].method, 'machine/acp-binary-install');
  assert.deepEqual(env.requests[0].params, { agentType: 'claude' });
  const poll = {
    ...env.scope,
    action: 'poll',
    operationId: started.operation.id,
  };
  assert.equal(
    (await providersCommand(poll, env.context)).operation.progress.percent,
    42,
  );
  const failed = await providersCommand(poll, env.context);
  assert.equal(failed.operation.state, 'failed');
  assert.doesNotMatch(JSON.stringify(failed), /fixture-secret/);
  assert.equal(env.requests.length, 1, 'polls must not replay an install');
});

test('authentication form input is sealed to the remote public key and bound to machine, request and interaction', async () => {
  const env = environment();
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    ['deriveKey'],
  );
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  const recipient = {
    type: 'rpc-secret-public-key-v1',
    algorithm: 'ECDH-P256-AES-256-GCM',
    keyId: 'fixture-key-id',
    publicKey: jwk,
  };
  let authRequest;
  env.onRpc(async (request, streams) => {
    if (request.params.action === 'start') {
      authRequest = request;
      streams.get(request.replyTo).push({
        id: request.id,
        result: {
          type: 'machine/acp-authentication-progress',
          machineId: 'm1',
          agentType: 'claude',
          requestId: request.params.requestId,
          status: 'input-required',
          interactionId: 'interaction',
          authenticationInputPublicKey: recipient,
          form: {
            fields: [
              {
                id: 'apiKey',
                type: 'secret',
                label: 'API Key',
                required: true,
              },
            ],
          },
        },
      });
    } else {
      const envelope = request.params.authenticationInputEnvelope;
      assert.ok(envelope);
      assert.doesNotMatch(JSON.stringify(request), /fixture-secret-input/);
      const publicKey = await crypto.subtle.importKey(
        'jwk',
        { ...envelope.ephemeralPublicKey, ext: true, key_ops: [] },
        { name: 'ECDH', namedCurve: 'P-256' },
        false,
        [],
      );
      const key = await crypto.subtle.deriveKey(
        { name: 'ECDH', public: publicKey },
        pair.privateKey,
        { name: 'AES-GCM', length: 256 },
        false,
        ['decrypt'],
      );
      const secretContext = `machine/acp-authenticate-input\0w1\0m1\0${authRequest.params.requestId}\0interaction`;
      const bytes = (value) => Buffer.from(value, 'base64url');
      const args = {
        name: 'AES-GCM',
        iv: bytes(envelope.iv),
        additionalData: new TextEncoder().encode(
          `lody-machine-rpc-secret-v1\0${envelope.keyId}\0${secretContext}`,
        ),
      };
      const plain = new TextDecoder().decode(
        await crypto.subtle.decrypt(args, key, bytes(envelope.ciphertext)),
      );
      assert.deepEqual(JSON.parse(plain), {
        action: 'accept',
        content: { apiKey: 'fixture-secret-input' },
      });
      await assert.rejects(
        crypto.subtle.decrypt(
          {
            ...args,
            additionalData: new TextEncoder().encode('another-machine'),
          },
          key,
          bytes(envelope.ciphertext),
        ),
      );
      streams.get(request.replyTo).push({
        id: request.id,
        result: {
          type: 'machine/acp-authenticate_response',
          machineId: 'm1',
          agentType: 'claude',
          requestId: request.params.requestId,
          success: true,
          disposition: 'input-accepted',
        },
      });
      streams.get(authRequest.replyTo).push({
        id: authRequest.id,
        result: {
          type: 'machine/acp-authenticate_response',
          machineId: 'm1',
          agentType: 'claude',
          requestId: authRequest.params.requestId,
          success: true,
          disposition: 'authenticated',
        },
      });
    }
  });
  const started = await providersCommand(
    { ...env.scope, action: 'authenticate', id: 'a1' },
    env.context,
  );
  const poll = {
    ...env.scope,
    action: 'poll',
    operationId: started.operation.id,
  };
  await providersCommand(poll, env.context);
  await providersCommand(
    {
      ...env.scope,
      action: 'auth-input',
      operationId: started.operation.id,
      input: { action: 'accept', content: { apiKey: 'fixture-secret-input' } },
    },
    env.context,
  );
  assert.equal(
    (await providersCommand(poll, env.context)).operation.state,
    'completed',
  );
  assert.equal(
    env.context.operations.get(started.operation.id).publicKey,
    undefined,
  );
});

test('config validation rejects bad paths, unsupported overrides and profile credential overrides', () => {
  assert.throws(
    () =>
      validateProvider({
        ...initial(),
        runtimeOverrides: { codexPath: '/tmp/codex' },
      }),
    /invalid_provider/,
  );
  assert.throws(
    () =>
      validateProvider({
        ...initial(),
        cliType: 'custom',
        customAcp: { command: 'run\0agent' },
      }),
    /invalid_provider/,
  );
  assert.throws(
    () =>
      validateProvider({
        ...initial('codex', 'codex'),
        codexAuth: {
          mode: 'api-key',
          profileId: crypto.randomUUID(),
          baseUrl: 'https://example.com/v1',
        },
        env: { OPENAI_API_KEY: 'unsafe' },
      }),
    /invalid_provider/,
  );
  assert.throws(
    () =>
      validateProvider({
        ...initial('codex', 'codex'),
        codexAuth: {
          mode: 'api-key',
          profileId: crypto.randomUUID(),
          baseUrl: 'http://example.com/v1',
        },
        env: {},
      }),
    /invalid_provider/,
  );
});

test('runtime teardown clears operations and never retains auth keys', async () => {
  const env = environment();
  const started = await providersCommand(
    { ...env.scope, action: 'verify', id: 'a1' },
    env.context,
  );
  stopProviderOperations(env.context);
  assert.equal(env.context.operations.size, 0);
  await assert.rejects(
    providersCommand(
      { ...env.scope, action: 'poll', operationId: started.operation.id },
      env.context,
    ),
    /provider_operation_expired/,
  );
});
