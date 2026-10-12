import type { Flock } from '@loro-dev/flock-wasm/base64';
import type { StreamsClient } from '@loro-dev/streams-client';
import { LoroDoc } from 'loro-crdt/base64';
import {
  sessionForkDocumentResult,
  sessionForkResponseResult,
  type SessionForkResult,
  type SessionForkSpec,
  type SessionToolsRequest,
  type SessionToolsResult,
} from '../models/session-tools.ts';
import { docFields, writeSessionMetadata } from './archive-session.ts';
import { clientFor, importUpdates, unpack } from './session.ts';
import { machineRpc } from './machine-rpc.ts';

export type SessionToolsContext = {
  workspaceId: string;
  userId: string;
  meta: { flock: Flock; client: StreamsClient };
  machines: Map<string, Flock>;
  sessionDoc: (id: string) => LoroDoc | undefined;
  getGrant: () => Promise<{ token: string; gatewayBaseUrl: string }>;
  signal?: AbortSignal;
  assertCurrent?: () => void;
};

const record = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
const uuid = (value: unknown): value is string =>
  typeof value === 'string' &&
  /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/iu.test(value);
const text = (value: unknown): value is string =>
  typeof value === 'string' && !!value.trim();

function forkOptions(
  fields: Record<string, unknown>,
  machines: Map<string, Flock>,
) {
  const machine = machines.get(String(fields.machineId ?? ''));
  const configId = String(fields.agentConfigId ?? '');
  const capability = record(machine?.get(['acpCapability', configId]));
  if (machine) {
    for (const row of machine.scan({ prefix: ['acpCapability', configId] })) {
      if (row.key.length === 3 && typeof row.key[2] === 'string')
        capability[row.key[2]] = row.value;
    }
  }
  const authoritative =
    !!configId &&
    capability.provenance === 'runtime' &&
    !(
      capability.cliType === 'builtin' &&
      capability.agentType === 'pi' &&
      typeof capability.sourceVersion === 'string' &&
      capability.sourceVersion.includes('+override:')
    );
  const shared =
    fields.isArchived !== true &&
    text(fields.acpSessionId) &&
    authoritative &&
    capability.sessionFork === true;
  const project = record(fields.project);
  return {
    shared,
    newWorktree:
      shared &&
      (project.kind === 'local' || project.kind === 'github') &&
      capability.sessionForkWorktree === true,
  };
}

export async function requestSessionFork(
  spec: SessionForkSpec,
  request: (spec: SessionForkSpec) => Promise<{
    result?: unknown;
    error?: { code?: string; message?: string };
  }>,
): Promise<SessionForkResult> {
  try {
    const reply = await request(spec);
    if (reply.error)
      return {
        targetSessionId: spec.targetSessionId,
        state: 'failed',
        code: reply.error.code,
        message: reply.error.message,
      };
    return sessionForkResponseResult(reply.result, spec);
  } catch {
    // An append may have reached the machine before its response was lost.
    return { targetSessionId: spec.targetSessionId, state: 'unknown' };
  }
}

async function readForkDocument(
  targetSessionId: string,
  sourceSessionId: string,
  context: SessionToolsContext,
): Promise<SessionForkResult> {
  const deadline = AbortSignal.timeout(25000);
  const signal = context.signal
    ? AbortSignal.any([context.signal, deadline])
    : deadline;
  const client = await clientFor(
    `${context.workspaceId}:s:${targetSessionId}`,
    context.getGrant,
  );
  const doc = new LoroDoc();
  try {
    const bootstrap = await client.bootstrap({ signal });
    if (!bootstrap.ok) throw new Error('fork_status_unavailable');
    let size = 0;
    const consume = (bytes: Uint8Array, snapshot = false) => {
      size += bytes.length;
      if (size > 32 * 1024 * 1024) throw new Error('fork_status_limit');
      if (snapshot) doc.import(unpack(bytes));
      else importUpdates(doc, bytes);
    };
    const initial = bootstrap.result;
    if (initial.snapshotOffset !== '-1' && initial.snapshot)
      consume(initial.snapshot.body, true);
    for (const update of initial.updates) consume(update.body);
    let { nextOffset: offset, cursor, upToDate } = initial;
    for (let pages = 0; !upToDate; pages++) {
      if (pages >= 100) throw new Error('fork_status_limit');
      const next = await client.readOnce({ offset, cursor, signal });
      if (!next.ok || next.result.closed)
        throw new Error('fork_status_unavailable');
      if (next.result.payload) consume(next.result.payload.body);
      if (!next.result.upToDate && next.result.nextOffset === offset)
        throw new Error('fork_status_stalled');
      ({ nextOffset: offset, cursor, upToDate } = next.result);
    }
    signal.throwIfAborted();
    return sessionForkDocumentResult(
      doc.toJSON(),
      targetSessionId,
      sourceSessionId,
    );
  } finally {
    doc.free();
  }
}

export async function sessionTools(
  args: SessionToolsRequest,
  context: SessionToolsContext,
): Promise<SessionToolsResult> {
  const assertCurrent = () => {
    context.signal?.throwIfAborted();
    context.assertCurrent?.();
  };
  assertCurrent();
  if (!text(args.sessionId) || args.workspaceId !== context.workspaceId)
    throw new Error('invalid_session');
  const room = `session-${args.sessionId}`;
  const fields = docFields(context.meta.flock, room);
  if (
    context.meta.flock.get(['e', room]) === false ||
    !Object.keys(fields).length
  )
    throw new Error('session_not_found');
  if (args.action === 'fork-options')
    return {
      action: args.action,
      ...forkOptions(fields, context.machines),
      targetSessionId: crypto.randomUUID(),
    };
  if (args.action === 'unread') {
    if (
      typeof fields.lastMessageAt !== 'number' ||
      !Number.isFinite(fields.lastMessageAt)
    )
      throw new Error('session_activity_unavailable');
    await writeSessionMetadata(
      args.sessionId,
      { lastReadAt: fields.lastMessageAt - 1 },
      context.meta,
      assertCurrent,
    );
    return { action: args.action, saved: true };
  }
  if (args.action === 'pin') {
    if (args.historyId !== null && !text(args.historyId))
      throw new Error('invalid_history');
    if (args.historyId !== null) {
      const history = context
        .sessionDoc(args.sessionId)
        ?.getList('history')
        .toJSON();
      if (
        !history?.some(
          (entry: unknown) =>
            record(entry).id === args.historyId &&
            record(entry).role === 'user',
        )
      )
        throw new Error('history_not_found');
    }
    await writeSessionMetadata(
      args.sessionId,
      { pinnedHistoryId: args.historyId ?? '' },
      context.meta,
      assertCurrent,
    );
    return { action: args.action, saved: true };
  }
  if (args.action === 'fork-status') {
    if (!uuid(args.targetSessionId) || args.targetSessionId === args.sessionId)
      throw new Error('invalid_session');
    let fork: SessionForkResult;
    try {
      fork = await readForkDocument(
        args.targetSessionId,
        args.sessionId,
        context,
      );
    } catch {
      fork = { targetSessionId: args.targetSessionId, state: 'unknown' };
    }
    return { action: args.action, fork };
  }
  if (args.action !== 'fork') throw new Error('invalid_session_tool');
  const spec = args.spec;
  if (
    !spec ||
    spec.sourceSessionId !== args.sessionId ||
    !text(spec.sourceTurnId) ||
    !uuid(spec.targetSessionId) ||
    spec.targetSessionId === args.sessionId ||
    !context.userId ||
    spec.requestedByUserId !== context.userId ||
    !['shared', 'new-worktree'].includes(spec.targetContext?.kind) ||
    (spec.targetContext.acknowledgeDirtySource !== undefined &&
      spec.targetContext.acknowledgeDirtySource !== true) ||
    (spec.targetContext.kind === 'shared' &&
      spec.targetContext.acknowledgeDirtySource !== undefined)
  )
    throw new Error('invalid_fork');
  if (fields.isArchived === true) throw new Error('session_archived');
  const options = forkOptions(fields, context.machines);
  if (
    !options.shared ||
    (spec.targetContext.kind === 'new-worktree' && !options.newWorktree)
  )
    throw new Error('fork_unavailable');
  const history = context
    .sessionDoc(args.sessionId)
    ?.getList('history')
    .toJSON();
  const source = history?.find(
    (entry: unknown) =>
      record(entry).id === spec.sourceTurnId &&
      record(entry).role === 'assistant',
  );
  if (!source || !text(record(source).acpTurnId))
    throw new Error('source_turn_not_forkable');
  assertCurrent();
  const deadline = AbortSignal.timeout(
    spec.targetContext.kind === 'new-worktree' ? 15000 : 30000,
  );
  const signal = context.signal
    ? AbortSignal.any([context.signal, deadline])
    : deadline;
  const fork = await requestSessionFork(spec, (request) =>
    machineRpc(
      context.workspaceId,
      String(fields.machineId),
      'session/fork',
      request,
      context.getGrant,
      signal,
    ),
  );
  return { action: args.action, fork };
}
