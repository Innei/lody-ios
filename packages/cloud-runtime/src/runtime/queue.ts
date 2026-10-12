import { LoroDoc, LoroMap } from 'loro-crdt/base64';
import { clientFor, importUpdates, unpack } from './session.ts';
import type {
  QueueReceipt,
  QueueRequest,
  QueueResult,
  SendCheckResult,
} from '../models/queue.ts';

export const QUEUE_EDIT_LEASE_MS = 5 * 60 * 1000;
type Grant = () => Promise<{ token: string; gatewayBaseUrl: string }>;

// The official /api/time midpoint calibration keeps leases compatible with CLI.
export async function queueServerNow(signal: AbortSignal): Promise<number> {
  const before = Date.now();
  const response = await fetch('https://api.lody.ai/api/time', {
    signal: AbortSignal.any([signal, AbortSignal.timeout(5000)]),
  });
  if (!response.ok) throw new Error('queue_time_unavailable');
  const data = (await response.json()) as { serverTime?: unknown };
  if (
    typeof data.serverTime !== 'number' ||
    !Number.isFinite(data.serverTime) ||
    data.serverTime <= 0
  )
    throw new Error('queue_time_unavailable');
  return Math.round(data.serverTime + (Date.now() - before) / 2);
}

// Never reconcile against a local replica that may contain an unacknowledged edit.
export async function readQueueSession(
  workspace: string,
  id: string,
  grant: Grant,
  signal: AbortSignal,
) {
  const client = await clientFor(`${workspace}:s:${id}`, grant);
  const doc = new LoroDoc();
  try {
    const initial = await client.bootstrap({ signal });
    if (!initial.ok) throw new Error('session_check_unavailable');
    let size = 0;
    const consume = (bytes: Uint8Array, snapshot = false) => {
      size += bytes.length;
      if (size > 32 * 1024 * 1024) throw new Error('session_limit');
      if (snapshot) doc.import(unpack(bytes));
      else importUpdates(doc, bytes);
    };
    const data = initial.result;
    if (data.snapshotOffset !== '-1' && data.snapshot)
      consume(data.snapshot.body, true);
    for (const update of data.updates) consume(update.body);
    let { nextOffset: offset, cursor, upToDate } = data;
    for (let page = 0; !upToDate; page++) {
      if (page >= 100) throw new Error('session_limit');
      const next = await client.readOnce({ offset, cursor, signal });
      if (!next.ok || next.result.closed)
        throw new Error('session_check_unavailable');
      if (next.result.payload) consume(next.result.payload.body);
      if (!next.result.upToDate && next.result.nextOffset === offset)
        throw new Error('stalled_cursor');
      ({ nextOffset: offset, cursor, upToDate } = next.result);
    }
    signal.throwIfAborted();
    return { doc, client };
  } catch (error) {
    doc.free();
    throw error;
  }
}

function historyFor(doc: LoroDoc, id: string) {
  return (doc.getList('history').toJSON() as any[]).filter(
    (entry) => entry.id === id || entry.userTurnId === id,
  );
}

export function checkSendDocument(doc: LoroDoc, id: string): SendCheckResult {
  const history = historyFor(doc, id);
  if (
    history.some(
      (entry) =>
        entry.role === 'assistant' ||
        ['seen', 'processing', 'handled', 'canceled', 'rejected'].includes(
          entry.status,
        ),
    )
  )
    return { state: 'accepted' };
  if (
    (doc.getMovableList('mq').toJSON() as any[]).some(
      (item) => item.userTurnId === id,
    )
  )
    return { state: 'queued' };
  if (history.some((entry) => entry.role === 'user'))
    return { state: 'uploaded', reason: 'delivery_unconfirmed' };
  return { state: 'unknown', reason: 'turn_not_observed' };
}

export function queueText(item: Record<string, any>): string {
  const config = item.acpSessionConfig;
  if (Array.isArray(config?.inputBlocks))
    return config.inputBlocks
      .filter((block: any) => block.type === 'text')
      .map((block: any) => block.text ?? '')
      .join('\n');
  return config?.prompt ?? item.task ?? '';
}

export function queueLeaseActive(item: Record<string, any>, now: number) {
  return (
    item.isEditing === true &&
    typeof item.editingStartedAt === 'number' &&
    Number.isFinite(item.editingStartedAt) &&
    now - item.editingStartedAt < QUEUE_EDIT_LEASE_MS
  );
}

export function validateQueueRequest(args: QueueRequest) {
  const id = (value: unknown) =>
    typeof value === 'string' && !!value.trim() && value.length <= 256;
  if (
    !id(args.sessionId) ||
    !id(args.id) ||
    ![
      'begin-edit',
      'save-edit',
      'cancel-edit',
      'move-up',
      'move-down',
      'delete',
      'check',
    ].includes(args.action) ||
    (args.editingStartedAt !== undefined &&
      (!Number.isFinite(args.editingStartedAt) ||
        args.editingStartedAt <= 0)) ||
    (args.text !== undefined &&
      (typeof args.text !== 'string' || args.text.length > 32000)) ||
    (args.baseText !== undefined &&
      (typeof args.baseText !== 'string' || args.baseText.length > 32000))
  )
    throw new Error('invalid_queue_command');
  if (args.action === 'check') {
    const receipt = args.receipt;
    if (
      !receipt ||
      receipt.id !== args.id ||
      receipt.action === ('check' as string) ||
      (receipt.order !== undefined &&
        (!Array.isArray(receipt.order) ||
          receipt.order.length > 10000 ||
          receipt.order.some((item) => !id(item))))
    )
      throw new Error('invalid_queue_receipt');
    validateQueueRequest({ ...receipt, sessionId: args.sessionId });
  }
}

export function mutateQueue(
  doc: LoroDoc,
  args: QueueRequest,
  now: number,
): QueueReceipt {
  validateQueueRequest(args);
  if (args.action === 'check') throw new Error('invalid_queue_command');
  if (historyFor(doc, args.id).length) throw new Error('queue_item_started');
  const queue = doc.getMovableList('mq');
  const values = queue.toJSON() as any[];
  const index = values.findIndex((item) => item.userTurnId === args.id);
  const value = values[index];
  if (!value) throw new Error('queue_item_missing');
  const item = queue.get(index);
  if (!(item instanceof LoroMap)) throw new Error('invalid_queue');
  const editing = queueLeaseActive(value, now);
  const owned = editing && args.editingStartedAt === value.editingStartedAt;
  const receipt: QueueReceipt = { action: args.action, id: args.id };
  switch (args.action) {
    case 'begin-edit':
      if (editing) throw new Error('queue_edit_conflict');
      receipt.editingStartedAt = now;
      receipt.text = queueText(value);
      item.set('isEditing', true);
      item.set('editingStartedAt', now);
      break;
    case 'save-edit': {
      if (!owned) throw new Error('queue_edit_expired');
      if (args.baseText !== undefined && queueText(value) !== args.baseText)
        throw new Error('queue_edit_conflict');
      if (typeof args.text !== 'string')
        throw new Error('invalid_queue_command');
      const text = args.text.trim();
      const config = item.get('acpSessionConfig');
      if (!(config instanceof LoroMap)) throw new Error('invalid_queue');
      const blocks = Array.isArray(value.acpSessionConfig?.inputBlocks)
        ? value.acpSessionConfig.inputBlocks.filter(
            (block: any) => block.type !== 'text',
          )
        : [];
      if (!text && !blocks.length) throw new Error('invalid_message');
      item.set('task', text);
      config.set('prompt', text);
      config.set('inputBlocks', [
        ...(text ? [{ type: 'text', text }] : []),
        ...blocks,
      ]);
      item.set('isEditing', false);
      item.delete('editingStartedAt');
      receipt.text = text;
      break;
    }
    case 'cancel-edit':
      if (!owned) throw new Error('queue_edit_expired');
      item.set('isEditing', false);
      item.delete('editingStartedAt');
      break;
    case 'delete':
      if (editing && !owned) throw new Error('queue_edit_conflict');
      queue.delete(index, 1);
      break;
    case 'move-up':
    case 'move-down': {
      if (values.some((row) => queueLeaseActive(row, now)))
        throw new Error('queue_edit_conflict');
      const target = index + (args.action === 'move-up' ? -1 : 1);
      if (target < 0 || target >= queue.length)
        throw new Error('queue_move_boundary');
      queue.move(index, target);
      receipt.order = (queue.toJSON() as any[]).map((row) => row.userTurnId);
      break;
    }
  }
  doc.commit();
  return receipt;
}

export function checkQueueReceipt(
  doc: LoroDoc,
  receipt: QueueReceipt,
): QueueResult {
  if (historyFor(doc, receipt.id).length)
    return { state: 'rejected', reason: 'queue_item_started' };
  const queue = doc.getMovableList('mq').toJSON() as any[];
  const item = queue.find((row) => row.userTurnId === receipt.id);
  if (receipt.action === 'delete')
    // Removal from mq cannot prove that an in-flight machine promotion was cancelled.
    return {
      state: 'unknown',
      reason: item ? 'queue_write_unconfirmed' : 'queue_execution_unconfirmed',
      receipt,
    };
  if (!item) return { state: 'unknown', reason: 'queue_item_missing', receipt };
  let applied = false;
  switch (receipt.action) {
    case 'begin-edit':
      applied =
        item.isEditing === true &&
        item.editingStartedAt === receipt.editingStartedAt;
      break;
    case 'save-edit':
      applied = item.isEditing !== true && queueText(item) === receipt.text;
      break;
    case 'cancel-edit':
      applied = item.isEditing !== true;
      break;
    case 'move-up':
    case 'move-down':
      applied =
        JSON.stringify(queue.map((row) => row.userTurnId)) ===
        JSON.stringify(receipt.order);
      break;
  }
  if (!applied)
    return { state: 'unknown', reason: 'queue_write_unconfirmed', receipt };
  return {
    state: 'applied',
    editingStartedAt: receipt.editingStartedAt,
    text: receipt.action === 'begin-edit' ? queueText(item) : undefined,
  };
}
