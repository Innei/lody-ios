import type { Flock } from '@loro-dev/flock-wasm/base64';
import { encodeFrame } from '../frames';
import type { MachinePresence } from '../models/machines';
import type {
  ProviderCapability,
  ProviderConfig,
  ProviderMachine,
  ProviderOperationResult,
  ProviderProgress,
  ProviderReply,
  ProviderRequest,
  ProviderSummary,
} from '../models/providers';
import { machineRpc } from './machine-rpc';
import { openSettings, settingsRows } from './settings';
import { clientFor } from './session';

type Grant = Parameters<typeof openSettings>[1];
type SecretPublicKey = {
  type: 'rpc-secret-public-key-v1';
  algorithm: 'ECDH-P256-AES-256-GCM';
  keyId: string;
  publicKey: JsonWebKey;
};
export type ProviderOperation = {
  workspaceId: string;
  userId: string;
  machineId: string;
  configId: string;
  agentType: string;
  rpcId: string;
  replyTo: string;
  offset: string;
  expiresAt: number;
  publicKey?: SecretPublicKey;
  value: ProviderOperationResult;
};
export type ProviderContext = {
  workspaceId: string;
  userId: string;
  meta: Pick<Flock, 'get' | 'scan'>;
  machines: Map<string, Flock>;
  getGrant: Grant;
  signal: AbortSignal;
  presence?: MachinePresence;
  operations: Map<string, ProviderOperation>;
  assertCurrent?: () => void;
};

const obj = (value: unknown): Record<string, any> =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, any>)
    : {};
const managed = new Set(['kimi', 'devin', 'grok', 'claude', 'codex', 'pi']);
const builtins = new Set([...managed, 'deepseek', 'bub', 'dimcode']);
const setupStates = new Set([
  'queued',
  'preparing-runtime',
  'verifying',
  'awaiting-auth',
  'failed',
]);
const overrideFor: Record<string, string> = {
  codex: 'codexPath',
  claude: 'claudeCodeExecutable',
  kimi: 'kimiPath',
  grok: 'grokPath',
  devin: 'devinPath',
  pi: 'piPath',
};
const profileGuard = '\0lody-codex-profile-v1';
const validText = (value: unknown, max = 4096): value is string =>
  typeof value === 'string' && value.length <= max && !value.includes('\0');
const identifier = (value: unknown): value is string =>
  validText(value, 1024) && !!value.trim() && !/[\s\x00-\x1f\x7f]/.test(value);
const authIdentifier = (value: unknown): value is string =>
  validText(value, 1024) && !!value.trim();
const fail = (): never => {
  throw new Error('invalid_provider');
};

function parseProvider(value: unknown, editing: boolean): ProviderConfig {
  const config = obj(value);
  const text = (value: unknown, max = 4096): value is string =>
    validText(value, editing ? max : 8 * 1024 * 1024);
  if (
    !identifier(config.id) ||
    !identifier(config.machineId) ||
    !text(config.name, 200) ||
    !config.name.trim() ||
    !['builtin', 'registry', 'custom'].includes(config.cliType) ||
    !identifier(config.agentType) ||
    (config.cliType === 'builtin' && !builtins.has(config.agentType)) ||
    !config.env ||
    typeof config.env !== 'object' ||
    Array.isArray(config.env) ||
    (editing && Object.entries(config.env).length > 128) ||
    Object.entries(config.env).some(
      ([key, value]) =>
        !/^[A-Za-z_][A-Za-z0-9_]*$/.test(key) ||
        (editing && key.length > 200) ||
        !text(value, 32000),
    ) ||
    (config.prompt !== undefined && !text(config.prompt, 32000))
  )
    fail();
  const result: ProviderConfig = {
    id: config.id,
    machineId: config.machineId,
    name: editing ? config.name.trim() : config.name,
    cliType: config.cliType,
    agentType: config.agentType,
    env: { ...config.env },
    ...(config.prompt !== undefined ? { prompt: config.prompt } : {}),
  };
  if (config.cliType === 'custom') {
    const launch = obj(config.customAcp);
    if (
      !text(launch.command) ||
      !launch.command.trim() ||
      (launch.args !== undefined &&
        (!Array.isArray(launch.args) ||
          (editing && launch.args.length > 128) ||
          launch.args.some((arg: unknown) => !text(arg))))
    )
      fail();
    result.customAcp = {
      command: editing ? launch.command.trim() : launch.command,
      ...(launch.args ? { args: [...launch.args] } : {}),
    };
  } else if (config.customAcp !== undefined) fail();
  if (config.runtimeOverrides !== undefined) {
    const overrides = obj(config.runtimeOverrides);
    if (
      config.cliType !== 'builtin' ||
      Object.entries(overrides).some(([key, value]) => {
        if (key === 'piExtensions')
          return (
            config.agentType !== 'pi' ||
            !Array.isArray(value) ||
            (editing && value.length > 32) ||
            value.some((path: unknown) => !text(path) || !path.trim())
          );
        return key !== overrideFor[config.agentType] || !text(value);
      })
    )
      fail();
    result.runtimeOverrides = { ...overrides };
  }
  if (config.codexAuth !== undefined) {
    const profile = obj(config.codexAuth);
    if (
      config.cliType !== 'builtin' ||
      config.agentType !== 'codex' ||
      config.runtimeOverrides ||
      !['chatgpt', 'api-key'].includes(profile.mode) ||
      !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(
        profile.profileId ?? '',
      ) ||
      Object.keys(config.env).some(
        (key) =>
          /^(CODEX_|OPENAI_|LODY_CODEX_|DYLD_)/i.test(key) ||
          /^(HOME|USERPROFILE|APPDATA|LOCALAPPDATA|XDG_CONFIG_HOME|DBUS_SESSION_BUS_ADDRESS|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|SSL_CERT_FILE|SSL_CERT_DIR|NODE_EXTRA_CA_CERTS|NODE_TLS_REJECT_UNAUTHORIZED|MODEL_PROVIDER|DEFAULT_AUTH_REQUEST|NODE_OPTIONS|LD_PRELOAD|LD_LIBRARY_PATH)$/i.test(
            key,
          ),
      )
    )
      fail();
    if (profile.mode === 'api-key') {
      if (!text(profile.baseUrl, 2048)) fail();
      let endpoint: URL;
      try {
        endpoint = new URL(profile.baseUrl.trim());
      } catch {
        return fail();
      }
      const loopback =
        endpoint.hostname === 'localhost' ||
        endpoint.hostname === '[::1]' ||
        /^127(?:\.\d{1,3}){3}$/.test(endpoint.hostname);
      if (
        endpoint.username ||
        endpoint.password ||
        endpoint.search ||
        endpoint.hash ||
        (endpoint.protocol !== 'https:' &&
          !(endpoint.protocol === 'http:' && loopback))
      )
        fail();
      result.codexAuth = {
        mode: 'api-key',
        profileId: profile.profileId,
        baseUrl: editing
          ? endpoint.toString().replace(/\/+$/, '')
          : profile.baseUrl,
      };
    } else result.codexAuth = { mode: 'chatgpt', profileId: profile.profileId };
  }
  if (config.titleGeneration !== undefined) {
    const values = obj(config.titleGeneration).configOptionValues;
    if (
      values !== undefined &&
      (!values ||
        typeof values !== 'object' ||
        Array.isArray(values) ||
        Object.entries(values).some(
          ([key, value]) =>
            !identifier(key) || !(typeof value === 'boolean' || text(value)),
        ))
    )
      fail();
    result.titleGeneration =
      values === undefined ? {} : { configOptionValues: { ...values } };
  }
  const limit = editing ? 128 * 1024 : 8 * 1024 * 1024;
  if (
    JSON.stringify(result).length > limit ||
    (editing && JSON.stringify(config).length > limit)
  )
    fail();
  return result;
}

export function validateProvider(value: unknown): ProviderConfig {
  return parseProvider(value, true);
}

function providerOverLimit(config: ProviderConfig) {
  try {
    validateProvider(config);
    return false;
  } catch {
    return true;
  }
}

function readConfig(value: unknown): ProviderConfig | undefined {
  try {
    const raw = obj(value);
    const normalized: Record<string, any> = { ...raw, env: raw.env ?? {} };
    if (raw.codexAuth && raw.runtimeOverrides?.codexPath === profileGuard)
      delete normalized.runtimeOverrides;
    // The mobile edit budget must not hide supported desktop configurations.
    return parseProvider(normalized, false);
  } catch {
    return undefined;
  }
}

export function providerSummaries(
  flock: Pick<Flock, 'scan'>,
  machineId: string,
): ProviderSummary[] {
  const result = new Map<string, ProviderSummary>();
  for (const row of flock.scan()) {
    if (
      row.key.length !== 2 ||
      !['agentConfig', 'providerSetup'].includes(String(row.key[0]))
    )
      continue;
    const raw = obj(row.value);
    const config = readConfig(
      row.key[0] === 'providerSetup' ? raw.config : raw,
    );
    if (!config || config.id !== row.key[1] || config.machineId !== machineId)
      continue;
    const summary: ProviderSummary = {
      id: config.id,
      machineId,
      name: config.name,
      cliType: config.cliType,
      agentType: config.agentType,
      state: 'configured',
      ...(providerOverLimit(config) ? { overLimit: true } : {}),
    };
    if (row.key[0] === 'providerSetup') {
      if (
        raw.v !== 1 ||
        raw.id !== config.id ||
        raw.machineId !== machineId ||
        !setupStates.has(raw.status)
      )
        continue;
      summary.state = raw.status;
      if (Number.isInteger(raw.attempt) && raw.attempt > 0)
        summary.attempt = raw.attempt;
      if (
        [
          'runtime-unavailable',
          'runtime-install-failed',
          'verification-failed',
        ].includes(raw.failureCode)
      )
        summary.failureCode = raw.failureCode;
    }
    if (summary.state === 'configured' || !result.has(config.id))
      result.set(config.id, summary);
  }
  return [...result.values()].sort((a, b) => a.name.localeCompare(b.name));
}

export function providerMachines(
  meta: Pick<Flock, 'get' | 'scan'>,
  userId: string,
  presence?: MachinePresence,
): ProviderMachine[] {
  return settingsRows('machine', meta as Flock).map((machine) => {
    const metadata = obj(meta.get(['m', `machine-${machine.id}`]));
    const field = (name: string) =>
      meta.get(['m', `machine-${machine.id}`, name]) ?? metadata[name];
    const caps = obj(field('protocolCapabilities'));
    const capabilities = Object.fromEntries(
      Object.entries(caps).filter(
        ([, value]) => Number.isInteger(value) && value > 0,
      ),
    );
    let availability: ProviderMachine['availability'] = 'unknown';
    if (presence?.state === 'live')
      availability = presence.onlineMachineIds.includes(machine.id)
        ? 'online'
        : 'offline';
    return {
      id: machine.id,
      name: machine.name,
      readOnly: !userId || field('ownerUserId') !== userId,
      availability,
      capabilities,
    };
  });
}

const revisionOf = async (value: unknown) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest(
        'SHA-256',
        new TextEncoder().encode(JSON.stringify(value)),
      ),
    ),
  )
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');

function configRecord(flock: Flock, id: string) {
  const published = flock.get(['agentConfig', id]);
  if (published)
    return {
      key: ['agentConfig', id],
      raw: obj(published),
      config: readConfig(published),
    };
  const setup = obj(flock.get(['providerSetup', id]));
  return {
    key: ['providerSetup', id],
    raw: setup,
    config: readConfig(setup.config),
  };
}

async function appendChange(
  replica: Awaited<ReturnType<typeof openSettings>>,
  version: ReturnType<Flock['version']>,
  signal: AbortSignal,
) {
  replica.flock.commit();
  signal.throwIfAborted();
  const saved = await replica.client.append({
    part: {
      contentType: 'application/octet-stream',
      body: encodeFrame(
        new TextEncoder().encode(
          JSON.stringify(replica.flock.exportJson(version)),
        ),
      ),
    },
  });
  if (!saved.ok) throw new Error('provider_write_unknown');
}

function optOut(flock: Flock, config: ProviderConfig, now: number) {
  if (
    config.cliType !== 'builtin' ||
    !managed.has(config.agentType) ||
    flock.get(['builtinAgentOptOut', config.agentType]) !== undefined ||
    providerSummaries(flock, config.machineId).some(
      (other) =>
        other.id !== config.id &&
        other.state === 'configured' &&
        other.cliType === 'builtin' &&
        other.agentType === config.agentType,
    )
  )
    return;
  flock.set(['builtinAgentOptOut', config.agentType], { v: 1, removedAt: now });
}

function capability(value: unknown): ProviderCapability {
  const raw = obj(value),
    cached = obj(raw.capability);
  const models = raw.models ?? cached.models ?? [];
  const options = cached.configOptions ?? [];
  if (!Array.isArray(models) || !Array.isArray(options))
    throw new Error('invalid_provider_response');
  return {
    authRequired: raw.authRequired === true,
    models: models
      .filter(
        (item) => identifier(item?.modelId) && validText(item?.name, 4096),
      )
      .map((item) => ({ modelId: item.modelId, name: item.name })),
    configOptions: options
      .filter(
        (item) =>
          identifier(item?.id) &&
          validText(item?.name) &&
          ['select', 'boolean'].includes(item.type) &&
          Array.isArray(item.options),
      )
      .map((item) => ({
        id: item.id,
        name: item.name,
        type: item.type,
        currentValue: item.currentValue,
        options: item.options
          .filter((opt: any) => validText(opt?.value) && validText(opt?.name))
          .map((opt: any) => ({ value: opt.value, name: opt.name })),
      })),
    providesSessionTitle:
      cached.sessionTitle === true &&
      !(raw.cliType === 'builtin' && raw.agentType === 'codex'),
  };
}

export function providerProgress(value: unknown): ProviderProgress {
  const raw = obj(value);
  const result: ProviderProgress = {
    status: String(raw.runtimePhase ?? raw.status ?? 'starting'),
  };
  const percent = raw.runtimePercent ?? raw.percent;
  if (typeof percent === 'number' && percent >= 0 && percent <= 100)
    result.percent = percent;
  if (validText(raw.version, 200)) result.version = raw.version;
  if (
    typeof raw.authorizationUrl === 'string' &&
    raw.authorizationUrl.length <= 8192
  ) {
    try {
      const url = new URL(raw.authorizationUrl);
      if (
        ['http:', 'https:'].includes(url.protocol) &&
        !url.username &&
        !url.password
      )
        result.authorizationUrl = url.toString();
    } catch {
      /* Invalid authorization links are not actionable. */
    }
  }
  if (validText(raw.userCode, 128)) result.userCode = raw.userCode;
  if (authIdentifier(raw.interactionId))
    result.interactionId = raw.interactionId;
  result.acceptsAuthorizationCode = raw.acceptsAuthorizationCode === true;
  result.requiresAuthorizationConsent =
    raw.requiresAuthorizationConsent === true;
  if (Array.isArray(raw.authMethods))
    result.authMethods = raw.authMethods
      .filter(
        (method) =>
          method?.type === 'agent' &&
          authIdentifier(method.id) &&
          validText(method.name),
      )
      .slice(0, 32)
      .map((method) => ({ id: method.id, name: method.name }));
  if (
    raw.form &&
    Array.isArray(raw.form.fields) &&
    raw.form.fields.length <= 32
  ) {
    const fields = raw.form.fields
      .filter(
        (field: any) =>
          authIdentifier(field?.id) &&
          validText(field.label) &&
          ['text', 'secret', 'select'].includes(field.type),
      )
      .map((field: any) => ({
        id: field.id,
        type: field.type,
        label: field.label,
        required: field.required === true,
        ...(field.type !== 'secret' && validText(field.defaultValue, 16384)
          ? { defaultValue: field.defaultValue }
          : {}),
        ...(field.type === 'select' && Array.isArray(field.options)
          ? {
              options: field.options
                .filter(
                  (option: any) =>
                    validText(option?.value, 16384) &&
                    !!option.value.length &&
                    validText(option?.label),
                )
                .slice(0, 256)
                .map((option: any) => ({
                  value: option.value,
                  label: option.label,
                })),
            }
          : {}),
      }));
    if (
      fields.length === raw.form.fields.length &&
      new Set(fields.map((field: any) => field.id)).size === fields.length
    )
      result.form = {
        ...(validText(raw.form.title) ? { title: raw.form.title } : {}),
        fields,
      };
  }
  // Runtime stdout/stderr and raw errors may contain credentials; never project them.
  return result;
}

const base64 = (bytes: Uint8Array) => {
  let value = '';
  for (let offset = 0; offset < bytes.length; offset += 0x8000)
    value += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  return btoa(value).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
export async function sealProviderInput(
  recipient: SecretPublicKey,
  input: string,
  context: string,
) {
  if (
    recipient?.type !== 'rpc-secret-public-key-v1' ||
    recipient.algorithm !== 'ECDH-P256-AES-256-GCM' ||
    !/^[A-Za-z0-9_-]{1,128}$/.test(recipient.keyId) ||
    recipient.publicKey?.kty !== 'EC' ||
    recipient.publicKey.crv !== 'P-256'
  )
    throw new Error('provider_encryption_unavailable');
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    ['deriveKey'],
  );
  const publicKey = await crypto.subtle.importKey(
    'jwk',
    { ...recipient.publicKey, ext: true, key_ops: [] },
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    [],
  );
  const key = await crypto.subtle.deriveKey(
    { name: 'ECDH', public: publicKey },
    pair.privateKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt'],
  );
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv,
      additionalData: new TextEncoder().encode(
        `lody-machine-rpc-secret-v1\0${recipient.keyId}\0${context}`,
      ),
    },
    key,
    new TextEncoder().encode(input),
  );
  const exported = await crypto.subtle.exportKey('jwk', pair.publicKey);
  return {
    type: 'rpc-secret-envelope-v1',
    algorithm: recipient.algorithm,
    keyId: recipient.keyId,
    ephemeralPublicKey: {
      kty: exported.kty,
      crv: exported.crv,
      x: exported.x,
      y: exported.y,
    },
    iv: base64(iv),
    ciphertext: base64(new Uint8Array(ciphertext)),
  };
}

async function startOperation(
  kind: ProviderOperationResult['kind'],
  config: ProviderConfig,
  context: ProviderContext,
) {
  for (const [id, operation] of context.operations) {
    if (operation.expiresAt < Date.now()) context.operations.delete(id);
    else if (
      operation.value.state === 'running' &&
      operation.machineId === config.machineId &&
      operation.configId === config.id &&
      operation.value.kind === kind
    )
      return { operation: operation.value };
  }
  if (context.operations.size >= 16) throw new Error('provider_busy');
  const id = crypto.randomUUID(),
    rpcId = crypto.randomUUID();
  const replyTo = `${context.workspaceId}:rpc:res:${config.machineId}:${crypto.randomUUID()}`;
  const reply = await clientFor(replyTo, context.getGrant);
  const created = await reply.create({
    contentType: 'application/json',
    ttlSeconds: 600,
  });
  if (!created.ok) throw new Error('provider_request_failed');
  const methods = {
    verify: 'machine/acp-capabilities-refresh',
    install: 'machine/acp-binary-install',
    authenticate: 'machine/acp-authenticate',
  };
  let params: object = { configId: config.id, force: true };
  if (kind === 'install') params = { agentType: config.agentType };
  if (kind === 'authenticate')
    params = { action: 'start', requestId: id, configId: config.id };
  const now = Date.now();
  const request = await clientFor(
    `${context.workspaceId}:rpc:req:${config.machineId}`,
    context.getGrant,
  );
  context.assertCurrent?.();
  context.signal.throwIfAborted();
  const sent = await request.append({
    part: {
      contentType: 'application/json',
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: rpcId,
        rpcVersion: '1',
        workspaceId: context.workspaceId,
        machineId: config.machineId,
        replyTo,
        sentAt: now,
        expiresAt: now + 300000,
        method: methods[kind],
        params,
      }),
    },
  });
  if (!sent.ok) throw new Error('provider_request_unknown');
  try {
    context.assertCurrent?.();
    context.signal.throwIfAborted();
  } catch {
    throw new Error('provider_request_unknown');
  }
  const operation: ProviderOperation = {
    workspaceId: context.workspaceId,
    userId: context.userId,
    machineId: config.machineId,
    configId: config.id,
    agentType: config.agentType,
    rpcId,
    replyTo,
    offset: '-1',
    expiresAt: now + 300000,
    value: { id, kind, state: 'running', progress: { status: 'starting' } },
  };
  context.operations.set(id, operation);
  return { operation: operation.value };
}

async function cancelOperation(
  operation: ProviderOperation,
  context: ProviderContext,
) {
  if (operation.value.state !== 'running') return;
  operation.value = {
    ...operation.value,
    state: 'cancelled',
    progress: undefined,
  };
  operation.publicKey = undefined;
  let method: string, params: object;
  if (operation.value.kind === 'authenticate') {
    method = 'machine/acp-authenticate';
    params = {
      action: 'cancel',
      requestId: crypto.randomUUID(),
      authenticationRequestId: operation.value.id,
    };
  } else if (operation.value.kind === 'verify') {
    method = 'machine/acp-capabilities-refresh-cancel';
    params = { requestId: operation.rpcId };
  } else return;
  await machineRpc(
    context.workspaceId,
    operation.machineId,
    method,
    params,
    context.getGrant,
    AbortSignal.timeout(10000),
  );
}

export function stopProviderOperations(context: ProviderContext) {
  const pending = [...context.operations.values()];
  context.operations.clear();
  for (const operation of pending)
    void cancelOperation(operation, context).catch(() => {});
}

export async function providersCommand(
  request: ProviderRequest,
  context: ProviderContext,
): Promise<ProviderReply> {
  if (
    request.workspaceId !== context.workspaceId ||
    !identifier(request.workspaceId) ||
    !context.userId
  )
    throw new Error('provider_scope');
  if (
    ![
      'list',
      'draft',
      'get',
      'save',
      'delete',
      'retry',
      'verify',
      'install',
      'status',
      'authenticate',
      'poll',
      'cancel',
      'auth-input',
    ].includes(request.action)
  )
    fail();
  const { flock: meta } = await openSettings(
    `${context.workspaceId}:meta`,
    context.getGrant,
    context.signal,
  );
  const machines = providerMachines(meta, context.userId, context.presence);
  if (request.action === 'list') {
    const providers: ProviderSummary[] = [];
    for (const machine of machines) {
      try {
        const { flock } = await openSettings(
          `${context.workspaceId}:mf:${machine.id}`,
          context.getGrant,
          context.signal,
        );
        providers.push(...providerSummaries(flock, machine.id));
      } catch (error) {
        if (!(error instanceof Error) || error.message !== 'not_found')
          throw error;
      }
    }
    return { machines, providers };
  }
  if (!identifier(request.machineId)) fail();
  const machine = machines.find((machine) => machine.id === request.machineId);
  if (!machine) throw new Error('machine_unavailable');
  if (machine.readOnly) throw new Error('provider_read_only');
  if (request.action === 'draft') {
    const id = crypto.randomUUID();
    const config: ProviderConfig = {
      id,
      machineId: machine.id,
      name: request.agentType,
      cliType: request.cliType,
      agentType: request.agentType,
      env: {},
      prompt: '',
    };
    if (request.cliType === 'custom') {
      config.agentType = `custom-${id}`;
      config.name = 'Custom ACP';
      config.customAcp = { command: '' };
    }
    if (
      request.cliType === 'builtin' &&
      request.agentType === 'codex' &&
      (machine.capabilities.codexAuthProfiles ?? 0) >= 1
    )
      config.codexAuth = { mode: 'chatgpt', profileId: crypto.randomUUID() };
    return { config };
  }
  if (
    request.action === 'poll' ||
    request.action === 'cancel' ||
    request.action === 'auth-input'
  ) {
    const operation = context.operations.get(request.operationId);
    if (
      !operation ||
      operation.workspaceId !== context.workspaceId ||
      operation.userId !== context.userId ||
      operation.machineId !== machine.id
    )
      throw new Error('provider_operation_expired');
    if (request.action === 'cancel') {
      await cancelOperation(operation, context).catch(() => {});
      context.operations.delete(request.operationId);
      return { operation: operation.value };
    }
    if (
      Date.now() > operation.expiresAt &&
      operation.value.state === 'running'
    ) {
      await cancelOperation(operation, context).catch(() => {});
      operation.value = {
        ...operation.value,
        state: 'failed',
        error: 'provider_timeout',
      };
      return { operation: operation.value };
    }
    if (request.action === 'auth-input') {
      if (
        operation.value.kind !== 'authenticate' ||
        operation.value.state !== 'running' ||
        !operation.publicKey
      )
        throw new Error('provider_encryption_unavailable');
      const progress = operation.value.progress;
      const base = {
        requestId: crypto.randomUUID(),
        authenticationRequestId: operation.value.id,
      };
      let params: object;
      if (request.code !== undefined) {
        if (
          !progress?.acceptsAuthorizationCode ||
          !validText(request.code) ||
          !request.code.trim()
        )
          fail();
        const secretContext = `machine/acp-authenticate\0${context.workspaceId}\0${machine.id}\0${operation.value.id}`;
        params = {
          ...base,
          action: 'submit-code',
          authorizationCodeEnvelope: await sealProviderInput(
            operation.publicKey,
            request.code.trim(),
            secretContext,
          ),
        };
      } else {
        const answer = request.input;
        if (!answer) throw new Error('invalid_provider');
        if (
          !progress?.interactionId ||
          !['accept', 'decline', 'cancel'].includes(answer.action)
        )
          fail();
        if (
          answer.methodId &&
          !progress?.authMethods?.some(
            (method) => method.id === answer.methodId,
          )
        )
          fail();
        const accepted = answer.action === 'accept';
        if (accepted && progress?.authMethods?.length && !answer.methodId)
          fail();
        if (accepted && progress?.form) {
          const content = obj(answer.content);
          if (
            Object.keys(content).some(
              (key) => !progress.form?.fields.some((field) => field.id === key),
            )
          )
            fail();
          for (const field of progress.form.fields) {
            const value = content[field.id];
            if (value !== undefined && !validText(value, 16384)) fail();
            if (field.required && (typeof value !== 'string' || !value.trim()))
              fail();
            if (
              field.type === 'select' &&
              value &&
              !field.options?.some((option) => option.value === value)
            )
              fail();
          }
        }
        const safeInput = {
          action: answer.action,
          ...(answer.methodId ? { methodId: answer.methodId } : {}),
          ...(progress?.form && accepted ? { content: answer.content } : {}),
        };
        const input = JSON.stringify(safeInput);
        if (input.length > 65536) fail();
        const secretContext = `machine/acp-authenticate-input\0${context.workspaceId}\0${machine.id}\0${operation.value.id}\0${progress?.interactionId}`;
        params = {
          ...base,
          action: 'submit-input',
          interactionId: progress?.interactionId,
          authenticationInputEnvelope: await sealProviderInput(
            operation.publicKey,
            input,
            secretContext,
          ),
        };
      }
      context.assertCurrent?.();
      const reply = await machineRpc(
        context.workspaceId,
        machine.id,
        'machine/acp-authenticate',
        params,
        context.getGrant,
        context.signal,
      );
      if (
        reply.error ||
        obj(reply.result).type !== 'machine/acp-authenticate_response' ||
        obj(reply.result).machineId !== machine.id ||
        obj(reply.result).requestId !== base.requestId ||
        obj(reply.result).success !== true ||
        obj(reply.result).disposition !== 'input-accepted'
      )
        throw new Error('provider_auth_input_failed');
      operation.value = {
        ...operation.value,
        progress: { status: 'starting' },
      };
      return { operation: operation.value };
    }
    if (operation.value.state !== 'running')
      return { operation: operation.value };
    const client = await clientFor(operation.replyTo, context.getGrant);
    const read = await client.readOnce({
      offset: operation.offset,
      signal: context.signal,
    });
    if (!read.ok) throw new Error('provider_request_failed');
    context.assertCurrent?.();
    context.signal.throwIfAborted();
    if (context.operations.get(request.operationId) !== operation)
      throw new Error('provider_operation_expired');
    operation.offset = read.result.nextOffset;
    if (read.result.payload) {
      if (read.result.payload.body.byteLength > 2 * 1024 * 1024)
        throw new Error('invalid_provider_response');
      const parsed = JSON.parse(
        new TextDecoder().decode(read.result.payload.body),
      );
      for (const reply of Array.isArray(parsed) ? parsed : [parsed]) {
        if (reply?.id !== operation.rpcId) continue;
        if (reply.error) {
          operation.value = {
            ...operation.value,
            state: 'failed',
            error:
              reply.error.code === 'method_unavailable'
                ? 'provider_unsupported'
                : 'provider_request_failed',
          };
          continue;
        }
        const result = obj(reply.result);
        if (result.machineId !== machine.id)
          throw new Error('invalid_provider_response');
        if (
          result.type === 'machine/acp-authentication-progress' ||
          result.type === 'machine/acp-binary-progress'
        ) {
          if (result.agentType !== operation.agentType)
            throw new Error('invalid_provider_response');
          if (
            operation.value.kind === 'authenticate' &&
            result.requestId !== operation.value.id
          )
            continue;
          operation.publicKey =
            result.authenticationInputPublicKey ??
            result.authorizationCodePublicKey ??
            operation.publicKey;
          operation.value = {
            ...operation.value,
            progress: providerProgress(result),
          };
        } else {
          const expected = {
            verify: 'machine/acp-capabilities-refresh_response',
            install: 'machine/acp-binary-install_response',
            authenticate: 'machine/acp-authenticate_response',
          };
          if (result.type !== expected[operation.value.kind])
            throw new Error('invalid_provider_response');
          if (
            (operation.value.kind === 'verify' &&
              result.configId !== operation.configId) ||
            (operation.value.kind === 'authenticate' &&
              result.requestId !== operation.value.id) ||
            result.agentType !== operation.agentType
          )
            throw new Error('invalid_provider_response');
          if (
            result.success !== true ||
            result.disposition === 'not-running' ||
            result.disposition === 'error'
          )
            operation.value = {
              ...operation.value,
              state: 'failed',
              error: 'provider_request_failed',
            };
          else {
            let state: ProviderOperationResult['state'] = 'completed';
            if (result.disposition === 'cancelled') state = 'cancelled';
            operation.value = {
              ...operation.value,
              state,
              ...(operation.value.kind === 'verify'
                ? { capability: capability(result) }
                : {}),
              progress:
                operation.value.kind === 'install'
                  ? providerProgress({
                      status: 'installed',
                      version: result.version,
                    })
                  : undefined,
            };
          }
          operation.publicKey = undefined;
        }
      }
    }
    return { operation: operation.value };
  }
  let id: string;
  if ('config' in request) id = request.config?.id;
  else if ('id' in request) id = request.id;
  else return fail();
  if (!identifier(id)) fail();
  const replica = await openSettings(
    `${context.workspaceId}:mf:${machine.id}`,
    context.getGrant,
    context.signal,
  );
  const record = configRecord(replica.flock, id);
  if (request.action === 'get') {
    if (!record.config || record.config.machineId !== machine.id)
      throw new Error('provider_not_found');
    return {
      config: record.config,
      revision: await revisionOf(record.raw),
      ...(providerOverLimit(record.config) ? { overLimit: true } : {}),
    };
  }
  if (record.config && providerOverLimit(record.config))
    throw new Error('provider_over_limit');
  if (
    request.action === 'save' ||
    request.action === 'delete' ||
    request.action === 'retry'
  ) {
    const version = replica.flock.version();
    if (record.config && record.config.machineId !== machine.id) fail();
    if (request.action === 'save') {
      if (
        record.config &&
        (!request.revision ||
          request.revision !== (await revisionOf(record.raw)))
      )
        throw new Error('provider_conflict');
      if (!record.config && request.revision)
        throw new Error('provider_not_found');
      const config = validateProvider(request.config);
      if (config.machineId !== machine.id) fail();
      if (config.codexAuth && (machine.capabilities.codexAuthProfiles ?? 0) < 1)
        throw new Error('provider_unsupported');
      if (
        config.runtimeOverrides?.piExtensions?.length &&
        (machine.capabilities.piExtensions ?? 0) < 1
      )
        throw new Error('provider_unsupported');
      context.assertCurrent?.();
      const encoded = config.codexAuth
        ? { ...config, runtimeOverrides: { codexPath: profileGuard } }
        : config;
      if (request.queue) {
        if (
          record.config ||
          config.cliType !== 'builtin' ||
          (!managed.has(config.agentType) &&
            !['bub', 'dimcode'].includes(config.agentType)) ||
          Object.values(config.runtimeOverrides ?? {}).some((value) =>
            Array.isArray(value) ? value.length > 0 : !!value?.trim(),
          ) ||
          (machine.capabilities.providerSetup ?? 0) < 1
        )
          throw new Error('provider_unsupported');
        const now = Date.now();
        replica.flock.set(['providerSetup', id], {
          v: 1,
          id,
          machineId: machine.id,
          config: encoded,
          status: 'queued',
          attempt: 1,
          createdAt: now,
          updatedAt: now,
        });
      } else {
        if (record.key[0] === 'providerSetup' && record.config) {
          if (
            !['queued', 'failed', 'awaiting-auth'].includes(record.raw.status)
          )
            throw new Error('provider_busy');
          replica.flock.set(record.key, {
            ...record.raw,
            config: encoded,
            updatedAt: Date.now(),
          });
        } else {
          const next = { ...record.raw, ...encoded };
          for (const field of [
            'customAcp',
            'runtimeOverrides',
            'codexAuth',
            'titleGeneration',
          ] as const)
            if (!(field in encoded)) delete next[field];
          replica.flock.set(['agentConfig', id], next);
        }
        if (config.cliType === 'builtin' && managed.has(config.agentType))
          replica.flock.delete(['builtinAgentOptOut', config.agentType]);
      }
      if (
        record.config &&
        JSON.stringify([
          record.config.cliType,
          record.config.agentType,
          record.config.env,
          record.config.customAcp,
          record.config.runtimeOverrides,
          record.config.codexAuth,
        ]) !==
          JSON.stringify([
            config.cliType,
            config.agentType,
            config.env,
            config.customAcp,
            config.runtimeOverrides,
            config.codexAuth,
          ])
      ) {
        replica.flock.delete(['acpCapability', id]);
        replica.flock.delete(['acpModelCapability', id]);
      }
      context.assertCurrent?.();
      await appendChange(replica, version, context.signal);
      const saved = configRecord(replica.flock, id);
      return { config, revision: await revisionOf(saved.raw) };
    }
    if (!record.config) throw new Error('provider_not_found');
    if (request.revision && request.revision !== (await revisionOf(record.raw)))
      throw new Error('provider_conflict');
    context.assertCurrent?.();
    if (request.action === 'retry') {
      if (
        record.key[0] !== 'providerSetup' ||
        record.raw.status !== 'failed' ||
        (machine.capabilities.providerSetup ?? 0) < 1
      )
        throw new Error('provider_unsupported');
      const { failureCode: _failure, ...setup } = record.raw;
      replica.flock.set(record.key, {
        ...setup,
        status: 'queued',
        attempt: Number(setup.attempt) + 1,
        updatedAt: Date.now(),
      });
    } else {
      const now = Date.now();
      if (record.key[0] === 'providerSetup')
        replica.flock.set(['providerSetupCancellation', id], {
          v: 1,
          id,
          machineId: machine.id,
          cancelledAt: now,
        });
      optOut(replica.flock, record.config, now);
      replica.flock.delete(['agentConfig', id]);
      replica.flock.delete(['providerSetup', id]);
    }
    context.assertCurrent?.();
    await appendChange(replica, version, context.signal);
    return {};
  }
  if (!record.config || record.config.machineId !== machine.id)
    throw new Error('provider_not_found');
  if (machine.availability !== 'online')
    throw new Error('provider_machine_offline');
  if (request.action === 'status') {
    const reply = await machineRpc(
      context.workspaceId,
      machine.id,
      'machine/acp-binary-status',
      { agentType: record.config.agentType },
      context.getGrant,
      context.signal,
    );
    const result = obj(reply.result);
    if (
      reply.error ||
      result.type !== 'machine/acp-binary-status_response' ||
      result.machineId !== machine.id ||
      result.success !== true
    )
      throw new Error(
        reply.error?.code === 'method_unavailable'
          ? 'provider_unsupported'
          : 'provider_request_failed',
      );
    return {
      status: {
        status: result.status,
        version: result.version,
        current: result.current,
        required: result.required,
      },
    };
  }
  if (request.action === 'authenticate') {
    if (
      record.config.codexAuth &&
      (machine.capabilities.codexAuthProfiles ?? 0) < 1
    )
      throw new Error('provider_unsupported');
    const usesProtocol =
      record.config.cliType !== 'builtin' ||
      record.config.agentType === 'devin';
    if (
      usesProtocol &&
      (machine.capabilities.acpProtocolAuthentication ?? 0) < 2
    )
      throw new Error('provider_unsupported');
    if (
      record.config.cliType === 'builtin' &&
      !['codex', 'claude', 'kimi', 'grok', 'devin'].includes(
        record.config.agentType,
      )
    )
      throw new Error('provider_unsupported');
  }
  if (
    request.action === 'install' &&
    (record.config.cliType === 'custom' ||
      (record.config.cliType === 'builtin' &&
        !managed.has(record.config.agentType)))
  )
    throw new Error('provider_unsupported');
  const kinds = {
    verify: 'verify',
    install: 'install',
    authenticate: 'authenticate',
  } as const;
  return startOperation(kinds[request.action], record.config, context);
}
