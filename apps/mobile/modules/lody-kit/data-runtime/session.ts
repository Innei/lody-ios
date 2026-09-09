import { LoroDoc, LoroMap, LoroList, LoroText } from 'loro-crdt/base64';
import { StreamsClient } from '@loro-dev/streams-client';
import { decompress } from 'fzstd';
import { decodeFrames, encodeFrame } from '../decoder/frames';
import { identityAt, itemRev, projectSession } from './project';
import { machineRpc, type RpcReply } from './machine-rpc';
export { projectSession } from './project';

type Grant = { token: string; gatewayBaseUrl: string };
export const MAX_BACKGROUND_SESSION_SYNCS = 3;
type SessionState = {
  id: string;
  workspace: string;
  doc: LoroDoc;
  client: StreamsClient;
  controller: AbortController;
  ready: boolean;
  sending: boolean;
  backgroundWork?: { id: string; turnId: string };
  status: string;
  reason?: string;
  pending?: ReturnType<typeof setTimeout>;
  firstQueuedAt: number;
  lastSignal: string;
  unsent: Map<string, ReturnType<LoroDoc['version']>>;
  getGrant: () => Promise<Grant>;
  markDispatch: (
    sessionId: string,
    turnId: string,
    queued?: boolean,
  ) => Promise<void>;
  emit: (event: object) => void;
};
let active: SessionState | undefined;
// Map insertion order is user visit order. Stream updates never touch it.
const sessions = new Map<string, SessionState>();
export const retainedSessionIds = () => [...sessions.keys()];
function signalOf(state: SessionState, status: string) {
  const history = state.doc.getList('history');
  let finished = 0;
  for (let i = 0; i < history.length; i++) {
    const entry = history.get(i);
    if (entry instanceof LoroMap && entry.get('finished') === true) finished++;
  }
  const awaiting = state.doc.getMap('session').get('awaitingUserSince') != null;
  return `${status}|${awaiting}|${finished}`;
}
function backgroundStatus(
  state: SessionState,
  reply: { finished?: boolean } | undefined,
) {
  if (state.status === 'offline') return 'failed';
  if (state.status !== 'live') return 'syncing';
  if (!reply) return 'sent';
  if (reply.finished === true) return 'completed';
  if (state.doc.getMap('session').get('awaitingUserSince') != null)
    return 'waiting';
  return 'receiving';
}
function backgroundProgress(state: SessionState) {
  const work = state.backgroundWork;
  if (!work) return undefined;
  const history = state.doc.getList('history').toJSON() as any[];
  const reply = history.findLast(
    (entry) => entry?.role === 'assistant' && entry.userTurnId === work.turnId,
  );
  const status = backgroundStatus(state, reply);
  if (['completed', 'waiting', 'failed'].includes(status))
    state.backgroundWork = undefined;
  return { id: work.id, state: status };
}
function flush(state: SessionState) {
  clearTimeout(state.pending);
  state.pending = undefined;
  state.firstQueuedAt = 0;
  if (sessions.get(state.id) !== state) return;
  state.emit({
    type: active === state ? 'session' : 'sessionCache',
    sessionId: state.id,
    synced: state.status === 'live',
    backgroundWork: backgroundProgress(state),
    session: JSON.stringify(
      projectSession(state.doc, state.status, state.reason),
    ),
  });
}
function scheduleEmit(state: SessionState, status: string, reason?: string) {
  state.status = status;
  state.reason = reason;
  if (sessions.get(state.id) !== state) return;
  clearTimeout(state.pending);
  const now = Date.now();
  const foreground = active === state;
  const signal = foreground ? signalOf(state, status) : '';
  const maxDelay = foreground ? 200 : 1000;
  if (
    (foreground && signal !== state.lastSignal) ||
    (state.firstQueuedAt && now - state.firstQueuedAt >= maxDelay)
  ) {
    state.lastSignal = signal;
    flush(state);
    return;
  }
  if (!state.firstQueuedAt) state.firstQueuedAt = now;
  state.pending = setTimeout(() => flush(state), foreground ? 100 : 1000);
}
function evict(state: SessionState) {
  if (state.backgroundWork) {
    state.emit({
      type: 'sessionCache',
      sessionId: state.id,
      backgroundWork: { id: state.backgroundWork.id, state: 'failed' },
    });
    state.backgroundWork = undefined;
  }
  // Keep the last complete display snapshot even when its coalescing timer is pending.
  if (state.ready) flush(state);
  clearTimeout(state.pending);
  state.controller.abort();
  sessions.delete(state.id);
}
function trimSessions() {
  for (const state of sessions.values()) {
    if (sessions.size <= MAX_BACKGROUND_SESSION_SYNCS + (active ? 1 : 0)) break;
    if (state !== active) evict(state);
  }
}
export function closeSession() {
  active = undefined;
  trimSessions();
}
export function stopSessions() {
  for (const state of sessions.values()) {
    clearTimeout(state.pending);
    state.controller.abort();
  }
  sessions.clear();
  active = undefined;
}
function unpack(bytes: Uint8Array) {
  return bytes[0] === 0x28 &&
    bytes[1] === 0xb5 &&
    bytes[2] === 0x2f &&
    bytes[3] === 0xfd
    ? decompress(bytes)
    : bytes;
}
export function importUpdates(doc: LoroDoc, bytes: Uint8Array) {
  for (const frame of decodeFrames(bytes)) doc.import(frame);
}
export async function clientFor(id: string, getGrant: () => Promise<Grant>) {
  const grant = await getGrant();
  return new StreamsClient({
    url: `${grant.gatewayBaseUrl.replace(/\/$/, '')}/ds/lody/${encodeURIComponent(id)}`,
    auth: async () => (await getGrant()).token,
    retry: { maxAttempts: 1 },
    timeout: { connectTimeoutMs: 15000, pollTimeoutMs: 35000 },
  });
}
export async function openSession(
  id: string,
  workspace: string,
  getGrant: () => Promise<Grant>,
  emit: (event: object) => void,
  markDispatch: (
    sessionId: string,
    turnId: string,
    queued?: boolean,
  ) => Promise<void>,
) {
  if ([...sessions.values()].some((state) => state.workspace !== workspace))
    stopSessions();
  const existing = sessions.get(id);
  if (existing && existing.status !== 'offline') {
    active = existing;
    existing.emit = emit;
    sessions.delete(id);
    sessions.set(id, existing);
    trimSessions();
    flush(existing);
    return 'watching';
  }
  if (existing) evict(existing);
  const controller = new AbortController();
  const state: SessionState = {
    id,
    workspace,
    doc: new LoroDoc(),
    client: undefined as unknown as StreamsClient,
    controller,
    ready: false,
    sending: false,
    status: 'syncing',
    firstQueuedAt: 0,
    lastSignal: '',
    unsent: new Map(),
    getGrant,
    markDispatch,
    emit,
  };
  active = state;
  sessions.set(id, state);
  trimSessions();
  const event = (status: string, reason?: string) => {
    scheduleEmit(state, status, reason);
  };
  event('syncing');
  void (async () => {
    try {
      state.client = await clientFor(`${workspace}:s:${id}`, getGrant);
      controller.signal.throwIfAborted();
      const initial = await state.client.bootstrap({
        signal: controller.signal,
      });
      if (!initial.ok) throw new Error(initial.result.code);
      if (sessions.get(id) !== state) return;
      const data = initial.result;
      let size = 0;
      const consume = (bytes: Uint8Array, snapshot = false) => {
        size += bytes.length;
        if (size > 32 * 1024 * 1024) throw new Error('session_limit');
        if (snapshot) state.doc.import(unpack(bytes));
        else importUpdates(state.doc, bytes);
      };
      if (data.snapshotOffset !== '-1' && data.snapshot)
        consume(data.snapshot.body, true);
      for (const part of data.updates) consume(part.body);
      let pages = 0;
      let changed = true;
      let offset = data.nextOffset,
        cursor = data.cursor,
        upToDate = data.upToDate;
      while (!controller.signal.aborted) {
        state.ready = upToDate;
        if (upToDate) {
          if (changed || state.status !== 'live') event('live');
          changed = false;
          pages = 0;
        } else {
          event('syncing');
          if (++pages > 100) throw new Error('session_limit');
        }
        const next = await state.client.readOnce({
          offset,
          cursor,
          signal: controller.signal,
          ...(upToDate ? { live: 'long-poll' as const } : {}),
        });
        if (!next.ok) throw new Error(next.result.code);
        if (sessions.get(id) !== state) return;
        if (next.result.payload) {
          consume(next.result.payload.body);
          changed = true;
        }
        if (next.result.nextOffset === offset && !next.result.upToDate)
          throw new Error('stalled_cursor');
        offset = next.result.nextOffset;
        cursor = next.result.cursor;
        upToDate = next.result.upToDate;
        if (next.result.closed) throw new Error('stream_closed');
        if (!next.result.payload?.body.length && upToDate)
          await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    } catch (error) {
      state.ready = false;
      event('offline', error instanceof Error ? error.message : 'sync_failed');
    }
  })();
  return 'watching';
}
export function appendUserTurn(
  doc: LoroDoc,
  id: string,
  text: string,
  userId: string,
  config: Record<string, any>,
  timestamp: string,
  status = 'pending',
) {
  const history = doc.getList('history');
  const entry = history.pushContainer(new LoroMap());
  for (const [key, value] of Object.entries({
    id,
    role: 'user',
    userId,
    timestamp,
    status,
    read: false,
    finished: true,
    fileDiff: [],
  }))
    entry.set(key, value);
  const items = entry.setContainer('items', new LoroList());
  for (const block of config.inputBlocks ?? [{ type: 'text', text }]) {
    const item = items.pushContainer(new LoroMap());
    for (const [key, value] of Object.entries(block)) {
      if (key === 'text')
        item.setContainer('text', new LoroText()).insert(0, String(value));
      else if (value !== undefined) item.set(key, value);
    }
  }
  const input = entry.setContainer('inputConfig', new LoroMap());
  for (const [key, value] of Object.entries(config))
    if (value !== undefined) input.set(key, value);
  doc.commit();
}
export async function sendTurn(args: {
  id?: string;
  backgroundTaskId?: string;
  queue?: boolean;
  sessionId: string;
  machineId: string;
  userId: string;
  text: string;
  attachmentBlocks?: Record<string, any>[];
  cliType: string;
  agentType: string;
  resume?: string;
  modelId?: string | null;
  modeId?: string;
  reasoningEffort?: string | null;
  reasoningEffortConfigId?: string;
}) {
  const state = active;
  if (!state || state.id !== args.sessionId || !state.ready)
    return { state: 'not_sent', reason: 'session_not_ready' };
  if (
    args.id !== undefined &&
    (typeof args.id !== 'string' ||
      !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(args.id))
  )
    return { state: 'not_sent', reason: 'invalid_message_id' };
  if (
    args.id &&
    [
      ...((state.doc.toJSON().history as any[]) ?? []),
      ...((state.doc.toJSON().mq as any[]) ?? []).map((item) => ({
        id: item.userTurnId,
      })),
    ].some((entry) => entry.id === args.id)
  )
    // The local entry may come from a lost append ACK. Never replay its write.
    return { id: args.id, state: 'unknown', reason: 'turn_already_exists' };
  if (state.sending) return { state: 'not_sent', reason: 'session_not_ready' };
  if (typeof args.text !== 'string')
    return { state: 'not_sent', reason: 'invalid_message' };
  const text = args.text.trim();
  const attachments = args.attachmentBlocks ?? [];
  if (
    !Array.isArray(attachments) ||
    attachments.length > 16 ||
    attachments.some(
      (block) =>
        !block ||
        !['image', 'file'].includes(block.type) ||
        typeof block[block.type === 'image' ? 'imageId' : 'fileId'] !==
          'string' ||
        !block[block.type === 'image' ? 'imageId' : 'fileId'] ||
        typeof block.mimeType !== 'string' ||
        !Number.isInteger(block.sizeBytes) ||
        block.sizeBytes <= 0 ||
        (block.type === 'file' &&
          (block.transport !== 'r2' ||
            typeof block.sha256 !== 'string' ||
            typeof block.fileName !== 'string' ||
            typeof block.textPreview !== 'boolean' ||
            typeof block.uploadedAt !== 'number')),
    )
  )
    return { state: 'not_sent', reason: '附件信息无效，请重新选择' };
  if (
    (!text && !attachments.length) ||
    text.length > 32000 ||
    !args.userId ||
    !args.machineId ||
    !args.agentType ||
    !args.cliType ||
    (args.reasoningEffort !== undefined &&
      args.reasoningEffort !== null &&
      (typeof args.reasoningEffort !== 'string' ||
        !args.reasoningEffort ||
        args.reasoningEffort.length > 128)) ||
    (args.reasoningEffortConfigId !== undefined &&
      (typeof args.reasoningEffortConfigId !== 'string' ||
        !args.reasoningEffortConfigId ||
        args.reasoningEffortConfigId.length > 128))
  )
    return { state: 'not_sent', reason: 'invalid_message' };
  const id = args.id ?? crypto.randomUUID(),
    timestamp = new Date().toISOString();
  state.sending = true;
  let uploaded = false;
  let writeStarted = false;
  try {
    const previous =
      (state.doc.toJSON().history as any[] | undefined)?.findLast(
        (entry) => entry.role === 'user',
      )?.inputConfig ?? {};
    if (previous.agentRoleId)
      throw new Error('agent_role_requires_configuration');
    const configOptionValues = {
      ...(previous.configOptionValues &&
      typeof previous.configOptionValues === 'object' &&
      !Array.isArray(previous.configOptionValues)
        ? previous.configOptionValues
        : {}),
    };
    if (args.reasoningEffort !== undefined) {
      const id = args.reasoningEffortConfigId || 'reasoning_effort';
      if (args.reasoningEffort === null) delete configOptionValues[id];
      else configOptionValues[id] = args.reasoningEffort;
    }
    const inputConfig = {
      cliType: args.cliType,
      agentType: args.agentType,
      prompt: text,
      inputBlocks: [...(text ? [{ type: 'text', text }] : []), ...attachments],
      // An explicit pick wins; otherwise the turn inherits what the session
      // already used, and an unset value leaves the machine on its default.
      modeId: args.modeId ?? previous.modeId,
      modelId:
        args.modelId === null ? undefined : (args.modelId ?? previous.modelId),
      configOptionValues: Object.keys(configOptionValues).length
        ? configOptionValues
        : undefined,
      mcpServerIds: previous.mcpServerIds ?? [],
      taskToolsEnabled: previous.taskToolsEnabled ?? false,
      resume: args.resume,
    };
    const raw = state.doc.toJSON();
    const history = (raw.history ?? []) as any[];
    const lastUser = history.findLastIndex((entry) => entry.role === 'user');
    const queued =
      args.queue === true ||
      (raw.mq as any[] | undefined)?.length ||
      history.some((entry) => entry.role === 'assistant' && !entry.finished) ||
      (lastUser >= 0 &&
        history[lastUser].status === 'pending' &&
        !history
          .slice(lastUser + 1)
          .some((entry) => entry.role === 'assistant'));
    const before = state.doc.version();
    writeStarted = true;
    if (queued) {
      // OSS consumes the shared movable queue, then creates its history turn.
      const item = state.doc.getMovableList('mq').pushContainer(new LoroMap());
      for (const [key, value] of Object.entries({
        task: text,
        userId: args.userId,
        userTurnId: id,
        timestamp,
      }))
        item.set(key, value);
      const config = item.setContainer('acpSessionConfig', new LoroMap());
      for (const [key, value] of Object.entries({
        ...inputConfig,
        chainDepth: 0,
      }))
        if (value !== undefined) config.set(key, value);
      state.doc.commit();
    } else {
      appendUserTurn(state.doc, id, text, args.userId, inputConfig, timestamp);
    }
    const result = await state.client.append({
      part: {
        contentType: 'application/octet-stream',
        body: encodeFrame(state.doc.export({ mode: 'update', from: before })),
      },
    });
    if (!result.ok) throw new Error(result.result.code);
    uploaded = true;
    if (queued) {
      // The queue is durable before its catalog wake-up watermark is published.
      await state.markDispatch(state.id, id, true);
      scheduleEmit(state, 'live');
      return { id, state: 'queued' };
    }
    if (state.backgroundWork) {
      state.emit({
        type: 'sessionCache',
        sessionId: state.id,
        backgroundWork: { id: state.backgroundWork.id, state: 'failed' },
      });
    }
    state.backgroundWork = args.backgroundTaskId
      ? { id: args.backgroundTaskId, turnId: id }
      : undefined;
    await state.markDispatch(state.id, id);
    if (active !== state) throw new Error('runtime_replaced');
    scheduleEmit(state, 'live');
    const replyTo = `${state.workspace}:rpc:res:${args.machineId}:${crypto.randomUUID()}`;
    const responseClient = await clientFor(replyTo, state.getGrant);
    const created = await responseClient.create({
      contentType: 'application/json',
      ttlSeconds: 300,
    });
    if (!created.ok) throw new Error(created.result.code);
    const requestId = crypto.randomUUID(),
      now = Date.now();
    const requestClient = await clientFor(
      `${state.workspace}:rpc:req:${args.machineId}`,
      state.getGrant,
    );
    const dispatched = await requestClient.append({
      part: {
        contentType: 'application/json',
        body: JSON.stringify({
          jsonrpc: '2.0',
          id: requestId,
          rpcVersion: '1',
          workspaceId: state.workspace,
          machineId: args.machineId,
          replyTo,
          sentAt: now,
          expiresAt: now + 15000,
          method: 'session/dispatch-turn',
          params: {
            sessionId: state.id,
            userTurnId: id,
            userId: args.userId,
            timestamp,
            inputConfig,
          },
        }),
      },
    });
    if (!dispatched.ok) throw new Error(dispatched.result.code);
    const signal = AbortSignal.any([
      state.controller.signal,
      AbortSignal.timeout(18000),
    ]);
    let offset = '-1';
    while (!signal.aborted) {
      const read = await responseClient.readOnce({
        offset,
        live: 'long-poll',
        signal,
      });
      if (!read.ok) throw new Error(read.result.code);
      offset = read.result.nextOffset;
      if (!read.result.payload) continue;
      const parsed = JSON.parse(
        new TextDecoder().decode(read.result.payload.body),
      );
      for (const reply of Array.isArray(parsed) ? parsed : [parsed]) {
        if (reply.id !== requestId) continue;
        if (!reply.result?.accepted)
          throw new Error(
            reply.error?.message ??
              reply.result?.error ??
              reply.result?.disposition ??
              'dispatch_rejected',
          );
        return { id, state: 'accepted' };
      }
    }
    throw new Error('ack_timeout');
  } catch (error) {
    // No automatic write replay: a lost HTTP ACK may still mean a durable write.
    let delivery = 'not_sent';
    if (writeStarted) delivery = 'unknown';
    if (uploaded) delivery = 'uploaded';
    return {
      id,
      state: delivery,
      reason: error instanceof Error ? error.message : 'send_failed',
    };
  } finally {
    state.sending = false;
  }
}

export async function controlTurn(args: {
  action: 'stop' | 'steer';
  sessionId: string;
  machineId: string;
  turnId: string;
  messageId?: string;
}) {
  const state = active;
  if (!state || state.id !== args.sessionId || !state.ready || state.sending)
    throw new Error('session_not_ready');
  if (
    !['stop', 'steer'].includes(args.action) ||
    typeof args.machineId !== 'string' ||
    !args.machineId.trim() ||
    typeof args.turnId !== 'string' ||
    !args.turnId.trim()
  )
    throw new Error('invalid_control');
  const history = state.doc.getList('history');
  const entries = history.toJSON() as any[];
  if (
    !entries.some(
      (entry) =>
        entry.id === args.turnId &&
        entry.role === 'assistant' &&
        !entry.finished,
    )
  )
    throw new Error('stale_turn');
  state.sending = true;
  try {
    let params: Record<string, unknown> = {
      sessionId: state.id,
      turnId: args.turnId,
    };
    if (args.action === 'steer') {
      if (typeof args.messageId !== 'string' || !args.messageId.trim())
        throw new Error('invalid_message');
      const queue = state.doc.getMovableList('mq');
      const index = (queue.toJSON() as any[]).findIndex(
        (item) => item.userTurnId === args.messageId,
      );
      const entry = entries.find((item) => item.id === args.messageId);
      if (
        entry &&
        (entry.role !== 'user' ||
          entry.status !== 'pending' ||
          entry.inputConfig?._lodyDeliveryKind !== 'steer' ||
          entries.some(
            (item) =>
              item.role === 'assistant' && item.userTurnId === args.messageId,
          ))
      )
        throw new Error('message_not_queued');
      const item = index >= 0 ? (queue.toJSON() as any[])[index] : undefined;
      const config = entry?.inputConfig ?? item?.acpSessionConfig;
      const userId = entry?.userId ?? item?.userId;
      const timestamp = entry?.timestamp ?? item?.timestamp;
      if (
        !config ||
        typeof config !== 'object' ||
        Array.isArray(config) ||
        typeof userId !== 'string' ||
        !userId ||
        typeof timestamp !== 'string' ||
        !timestamp
      )
        throw new Error('message_not_queued');
      const before = state.doc.version();
      // Move the same id atomically. pending_apply is durable intent, not delivery.
      // A lost append/RPC ACK must never trigger an automatic replay.
      if (!entry) {
        appendUserTurn(
          state.doc,
          args.messageId,
          item.task,
          userId,
          { ...config, _lodyDeliveryKind: 'steer' },
          timestamp,
          'pending_apply',
        );
      } else {
        const pending = history.get(entries.indexOf(entry));
        if (!(pending instanceof LoroMap)) throw new Error('invalid_history');
        pending.set('status', 'pending_apply');
        pending.set('read', false);
      }
      if (index >= 0) queue.delete(index, 1);
      state.doc.commit();
      const uploaded = await state.client.append({
        part: {
          contentType: 'application/octet-stream',
          body: encodeFrame(state.doc.export({ mode: 'update', from: before })),
        },
      });
      scheduleEmit(state, state.status);
      if (!uploaded.ok) throw new Error('steer_unconfirmed');
      params = {
        sessionId: state.id,
        expectedTurnId: args.turnId,
        userTurnId: args.messageId,
        userId,
        timestamp,
        inputConfig: config,
      };
    }
    const reply = await machineRpc(
      state.workspace,
      args.machineId,
      args.action === 'stop' ? 'session/cancel' : 'session/steer',
      params,
      state.getGrant,
      AbortSignal.any([state.controller.signal, AbortSignal.timeout(35000)]),
    ).catch((error: unknown): RpcReply => ({
      error: {
        message: error instanceof Error ? error.message : 'control_failed',
      },
    }));
    if (reply.error) {
      // Past the durable write the machine owns the steer: it requeues proven-
      // undelivered ones and an ambiguous failure must not be sent again here.
      if (args.action === 'steer')
        return { state: 'not_applied', reason: reply.error.message };
      throw new Error(reply.error.message ?? 'control_failed');
    }
    const result = reply.result as
      | {
          success?: boolean;
          applied?: boolean;
          disposition?: string;
          error?: string;
        }
      | undefined;
    if (args.action === 'stop') {
      if (result?.success !== true)
        throw new Error(result?.error ?? 'stop_failed');
      return { state: 'stopped' };
    }
    if (result?.applied !== true)
      return { state: 'not_applied', reason: result?.disposition ?? 'unknown' };
    const before = state.doc.version();
    for (let i = 0; i < history.length; i++) {
      const entry = history.get(i);
      if (
        entry instanceof LoroMap &&
        entry.get('id') === args.messageId &&
        entry.get('status') === 'pending_apply'
      ) {
        entry.set('status', 'processing');
        entry.set('read', true);
      }
    }
    state.doc.commit();
    scheduleEmit(state, state.status);
    // Delivery is confirmed even if this redundant display-status append fails.
    await state.client
      .append({
        part: {
          contentType: 'application/octet-stream',
          body: encodeFrame(state.doc.export({ mode: 'update', from: before })),
        },
      })
      .catch(() => {});
    return { state: 'applied' };
  } finally {
    state.sending = false;
    scheduleEmit(state, state.status);
  }
}

export function docSnapshot() {
  return active?.doc.toJSON();
}
function scalar(value: unknown) {
  return value instanceof LoroText ? value.toString() : value;
}
function locateItem(entryId: string, itemId: string) {
  const state = active;
  if (!state) return undefined;
  const history = state.doc.getList('history');
  for (let i = 0; i < history.length; i++) {
    const entry = history.get(i);
    if (!(entry instanceof LoroMap) || entry.get('id') !== entryId) continue;
    const items = entry.get('items');
    if (!(items instanceof LoroList)) return undefined;
    for (let j = 0; j < items.length; j++) {
      const item = items.get(j);
      if (!(item instanceof LoroMap)) continue;
      // Desktop writes toolCallId as LoroText; the projection reads it via toJSON.
      const callId = scalar(item.get('toolCallId'));
      const id =
        scalar(item.get('type')) === 'tool_call' && typeof callId === 'string'
          ? callId
          : identityAt(items, j);
      if (id === itemId) return item;
    }
    return undefined;
  }
  return undefined;
}
const DETAIL_LIMIT = 512 * 1024;
export async function itemDetail(args: {
  sessionId: string;
  entryId: string;
  itemId: string;
  cursor?: string;
}) {
  if (!active || active.id !== args.sessionId || !active.ready)
    throw new Error('session_not_ready');
  const item = locateItem(args.entryId, args.itemId);
  if (!item) throw new Error('item_not_found');
  const raw: any = item.toJSON();
  const content: unknown[] = Array.isArray(raw.content) ? raw.content : [];
  const start = Math.max(0, Number(args.cursor ?? 0) || 0);
  const blocks: unknown[] = [];
  let size = 0;
  let next = content.length;
  for (let i = start; i < content.length; i++) {
    const bytes = JSON.stringify(content[i]).length;
    if (blocks.length && size + bytes > DETAIL_LIMIT) {
      next = i;
      break;
    }
    blocks.push(content[i]);
    size += bytes;
  }
  const truncated = next < content.length;
  return {
    itemId: args.itemId,
    rev: itemRev(active.doc, args.entryId, args.itemId),
    blocks,
    rawInput: raw.rawInput,
    rawOutput: raw.rawOutput,
    options: raw.permissionRequest?.options,
    outcome: raw.permissionRequest?.outcome,
    truncated,
    nextCursor: truncated ? String(next) : undefined,
  };
}
export async function respondPermission(args: {
  sessionId: string;
  entryId: string;
  itemId: string;
  requestId: string;
  optionId: string;
}) {
  const state = active;
  if (!state || state.id !== args.sessionId || !state.ready)
    throw new Error('session_not_ready');
  const item = locateItem(args.entryId, args.itemId);
  const request = item?.get('permissionRequest');
  const current: any =
    request instanceof LoroMap ? request.toJSON() : (request ?? undefined);
  if (!item || !current || current.requestId !== args.requestId)
    return { state: 'stale' as const };
  const options: any[] = Array.isArray(current.options) ? current.options : [];
  if (!options.some((o) => o?.optionId === args.optionId))
    throw new Error('invalid_option');
  const key = `${args.entryId}/${args.itemId}/${args.requestId}`;
  if (current.outcome != null) {
    if (current.outcome.optionId !== args.optionId)
      return { state: 'conflict' as const };
    if (!state.unsent.has(key)) return { state: 'accepted' as const };
  }
  const before = state.unsent.get(key) ?? state.doc.version();
  if (current.outcome == null) {
    const outcome = { outcome: 'selected', optionId: args.optionId };
    if (request instanceof LoroMap) request.set('outcome', outcome);
    else item.set('permissionRequest', { ...current, outcome });
    state.doc.commit();
  }
  const result = await state.client.append({
    part: {
      contentType: 'application/octet-stream',
      body: encodeFrame(state.doc.export({ mode: 'update', from: before })),
    },
  });
  if (!result.ok) {
    // A user-initiated retry re-exports from this version; nothing replays on its own.
    state.unsent.set(key, before);
    throw new Error('upload_failed');
  }
  state.unsent.delete(key);
  if (active === state) scheduleEmit(state, 'live');
  return { state: 'accepted' as const };
}
