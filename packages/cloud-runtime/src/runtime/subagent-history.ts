import { LoroList, LoroMap, type LoroDoc } from 'loro-crdt/base64';
import { identityAt, projectSubagentItem } from './project.ts';
import { readSubagentRunMetadata } from '../protocol/subagent-history.ts';
import type { DetailBlock } from '../models/session.ts';
import {
  subagentIdentityKey,
  type SubagentHistoryFragment,
  type SubagentHistoryPage,
  type SubagentHistoryRequest,
  type SubagentIdentity,
  type SubagentRunMetadata,
  type SubagentState,
} from '../models/subagent-history.ts';

const PAGE_ITEMS = 24;
const TEXT_PAGE_LENGTH = 32 * 1024;
const DETAIL_LIMIT = 256 * 1024;
const states = new Set<SubagentState>([
  'pending',
  'running',
  'completed',
  'failed',
  'cancelled',
  'unknown',
]);
type Raw = Record<string, any>;
type LocatedTask = { identity: SubagentIdentity; raw: Raw };
type Cursor = { identity: string; index: number; offset?: number };

function record(value: unknown): value is Raw {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

export function subagentRunMetadata(
  value: unknown,
): SubagentRunMetadata | undefined {
  if (value == null) return undefined;
  const metadata = readSubagentRunMetadata(value);
  if (!metadata) throw new Error('invalid_subagent_run');
  return metadata;
}

function validateIdentity(identity: SubagentIdentity) {
  for (const key of [
    'sessionId',
    'parentTurnId',
    'entryId',
    'itemId',
    'taskId',
  ] as const)
    if (typeof identity?.[key] !== 'string' || !identity[key])
      throw new Error('invalid_subagent_identity');
  if (
    identity.runSessionId != null &&
    (typeof identity.runSessionId !== 'string' || !identity.runSessionId)
  )
    throw new Error('invalid_subagent_identity');
}

function tasksIn(doc: LoroDoc, sessionId: string): LocatedTask[] {
  const tasks: LocatedTask[] = [];
  const history = doc.getList('history');
  for (let entryIndex = 0; entryIndex < history.length; entryIndex++) {
    const container = history.get(entryIndex);
    const entry = container instanceof LoroMap ? container.toJSON() : container;
    if (!record(entry) || !Array.isArray(entry.items)) continue;
    const entryId = String(entry.id ?? identityAt(history, entryIndex));
    const itemList =
      container instanceof LoroMap ? container.get('items') : undefined;
    for (let itemIndex = 0; itemIndex < entry.items.length; itemIndex++) {
      const raw = entry.items[itemIndex];
      if (
        !record(raw) ||
        raw.type !== 'subagent_task' ||
        typeof raw.taskId !== 'string'
      )
        continue;
      const itemId =
        itemList instanceof LoroList
          ? identityAt(itemList, itemIndex)
          : `idx:${entryIndex}:${itemIndex}`;
      tasks.push({
        raw,
        identity: {
          sessionId,
          parentTurnId: String(entry.userTurnId ?? entryId),
          entryId,
          itemId,
          taskId: raw.taskId,
          runSessionId:
            typeof raw.run?.sessionId === 'string'
              ? raw.run.sessionId
              : undefined,
        },
      });
    }
  }
  return tasks;
}

function locate(doc: LoroDoc, identity: SubagentIdentity) {
  validateIdentity(identity);
  const tasks = tasksIn(doc, identity.sessionId);
  const selected = tasks.find(
    (task) =>
      task.identity.entryId === identity.entryId &&
      task.identity.parentTurnId === identity.parentTurnId &&
      task.identity.itemId === identity.itemId &&
      task.identity.taskId === identity.taskId &&
      (identity.runSessionId == null ||
        task.identity.runSessionId === identity.runSessionId),
  );
  if (!selected) throw new Error('subagent_run_not_found');
  return { selected, tasks };
}

function taskState(raw: Raw): SubagentState {
  const state = raw.run?.snapshot?.state;
  if (states.has(state)) return state;
  if (raw.status === 'in_progress') return 'running';
  if (states.has(raw.status)) return raw.status;
  return 'unknown';
}

function cursorFor(identity: SubagentIdentity, index: number, offset?: number) {
  return JSON.stringify({
    identity: subagentIdentityKey(identity),
    index,
    offset,
  });
}

function parseCursor(
  cursor: string | undefined,
  identity: SubagentIdentity,
  length: number,
): Cursor {
  if (cursor == null)
    return { identity: subagentIdentityKey(identity), index: length };
  if (typeof cursor !== 'string' || cursor.length > 4096)
    throw new Error('invalid_subagent_cursor');
  let value: Cursor;
  try {
    value = JSON.parse(cursor);
  } catch {
    throw new Error('invalid_subagent_cursor');
  }
  if (
    value?.identity !== subagentIdentityKey(identity) ||
    !Number.isSafeInteger(value.index) ||
    value.index < 0 ||
    value.index > length ||
    (value.offset != null &&
      (!Number.isSafeInteger(value.offset) || value.offset < 0))
  )
    throw new Error('invalid_subagent_cursor');
  return value;
}

export function readSubagentHistory(
  doc: LoroDoc,
  identity: SubagentIdentity,
  cursor?: string,
): SubagentHistoryPage {
  const { selected, tasks } = locate(doc, identity);
  const raw = selected.raw;
  const metadata = subagentRunMetadata(raw.run);
  const task = projectSubagentItem(doc, raw, identity.entryId, identity.itemId);
  if (task.type !== 'subagent_task') throw new Error('invalid_subagent_task');
  const spawn = raw.toolUseId ?? raw.run?.snapshot?.parentToolCallId;
  const runs = tasks
    .filter((candidate) => {
      if (candidate.identity.parentTurnId !== selected.identity.parentTurnId)
        return false;
      if (candidate.identity.taskId === selected.identity.taskId) return true;
      return (
        typeof spawn === 'string' &&
        !!spawn &&
        (candidate.raw.toolUseId ??
          candidate.raw.run?.snapshot?.parentToolCallId) === spawn &&
        candidate.identity.runSessionId === selected.identity.runSessionId
      );
    })
    .map((candidate) => ({
      identity: candidate.identity,
      state: taskState(candidate.raw),
      startedAtEpochSeconds:
        candidate.raw.run?.snapshot?.startedAtEpochSeconds ??
        candidate.raw.startedAtEpochSeconds,
    }));
  const page: SubagentHistoryPage = {
    v: 1,
    identity: selected.identity,
    task: task as SubagentHistoryPage['task'],
    runs,
    status: metadata ? 'ready' : 'unsupported',
    revision: JSON.stringify(doc.frontiers()),
    fragments: [],
    incomplete: metadata?.snapshot.outputIncomplete === true,
  };
  if (!metadata) return page;
  const items = raw.run.items as Raw[];
  const position = parseCursor(cursor, selected.identity, items.length);
  let index = position.index;
  let offset = position.offset;
  if (offset == null) index--;
  for (; index >= 0 && page.fragments.length < PAGE_ITEMS; index--) {
    const item = items[index];
    if (
      !record(item) ||
      !['text', 'thought', 'tool_call', 'plan'].includes(item.type)
    )
      throw new Error('invalid_subagent_item');
    const itemId = `run:${identity.taskId}:${index}`;
    const fragment: SubagentHistoryFragment = {
      index,
      nativeTurnId:
        typeof item.nativeTurnId === 'string' ? item.nativeTurnId : undefined,
      messageId:
        typeof item.messageId === 'string' ? item.messageId : undefined,
      item: projectSubagentItem(
        doc,
        item,
        `${identity.entryId}/${identity.itemId}`,
        itemId,
      ),
    };
    if (fragment.item.type === 'tool_call') {
      const { permission: _permission, ...readOnly } = fragment.item as Extract<
        SubagentHistoryFragment['item'],
        { type: 'tool_call' }
      >;
      fragment.item = readOnly;
    }
    if (item.type === 'text' || item.type === 'thought') {
      if (typeof item.text !== 'string')
        throw new Error('invalid_subagent_item');
      const end = offset ?? item.text.length;
      if (end > item.text.length) throw new Error('stale_subagent_cursor');
      let start = Math.max(0, end - TEXT_PAGE_LENGTH);
      // Keep a surrogate pair on one page.
      if (start > 0 && /[\uDC00-\uDFFF]/u.test(item.text[start])) start--;
      fragment.offset = start;
      fragment.total = item.text.length;
      fragment.item = {
        ...fragment.item,
        type: item.type,
        text: item.text.slice(start, end),
      };
      page.fragments.unshift(fragment);
      if (start > 0) {
        page.nextCursor = cursorFor(selected.identity, index, start);
        return page;
      }
    } else {
      page.fragments.unshift(fragment);
    }
    offset = undefined;
  }
  if (index >= 0) page.nextCursor = cursorFor(selected.identity, index + 1);
  return page;
}

export function readSubagentDetail(
  doc: LoroDoc,
  identity: SubagentIdentity,
  index: number,
  cursor?: string,
) {
  const { selected } = locate(doc, identity);
  subagentRunMetadata(selected.raw.run);
  if (!Number.isSafeInteger(index) || index < 0)
    throw new Error('invalid_subagent_item');
  const raw = selected.raw.run?.items[index];
  if (!record(raw) || raw.type !== 'tool_call')
    throw new Error('subagent_item_not_found');
  const start = cursor == null ? 0 : Number(cursor);
  if (!Number.isSafeInteger(start) || start < 0)
    throw new Error('invalid_subagent_cursor');
  const content = Array.isArray(raw.content) ? raw.content : [];
  if (start > content.length) throw new Error('stale_subagent_cursor');
  const blocks: DetailBlock[] = [];
  let next = start;
  let size = 0;
  for (; next < content.length; next++) {
    const block = content[next];
    const bytes = JSON.stringify(block).length;
    if (blocks.length && size + bytes > DETAIL_LIMIT) break;
    blocks.push(block);
    size += bytes;
  }
  const summary = projectSubagentItem(
    doc,
    raw,
    `${identity.entryId}/${identity.itemId}`,
    `run:${identity.taskId}:${index}`,
  );
  return {
    itemId: summary.itemId,
    rev: summary.rev,
    blocks,
    rawInput: raw.rawInput,
    rawOutput: raw.rawOutput,
    truncated: next < content.length,
    nextCursor: next < content.length ? String(next) : undefined,
  };
}

export function createSubagentHistoryRuntime({
  doc,
  emit,
}: {
  doc: (sessionId: string) => LoroDoc | undefined;
  emit: (event: object) => void;
}) {
  const subscriptions = new Map<string, () => void>();
  const unwatch = (id: string) => {
    subscriptions.get(id)?.();
    subscriptions.delete(id);
  };
  const requireDoc = (identity: SubagentIdentity) => {
    validateIdentity(identity);
    const value = doc(identity.sessionId);
    if (!value) throw new Error('session_not_ready');
    return value;
  };
  return {
    execute(request: SubagentHistoryRequest) {
      if (request.action === 'unwatch') {
        unwatch(request.subscriptionId);
        return { state: 'released' as const };
      }
      const value = requireDoc(request.identity);
      if (request.action === 'detail')
        return readSubagentDetail(
          value,
          request.identity,
          request.index,
          request.cursor,
        );
      const result = readSubagentHistory(
        value,
        request.identity,
        request.action === 'page' ? request.cursor : undefined,
      );
      if (request.action === 'watch') {
        if (
          typeof request.subscriptionId !== 'string' ||
          !request.subscriptionId
        )
          throw new Error('invalid_subagent_subscription');
        unwatch(request.subscriptionId);
        let timer: ReturnType<typeof setTimeout> | undefined;
        const stop = value.subscribe(() => {
          if (timer) return;
          timer = setTimeout(() => {
            timer = undefined;
            emit({
              type: 'subagentHistory',
              sessionId: request.identity.sessionId,
              subscriptionId: request.subscriptionId,
              subagentHistory: 'changed',
            });
          }, 100);
        });
        subscriptions.set(request.subscriptionId, () => {
          clearTimeout(timer);
          stop();
        });
      }
      return result;
    },
    stop() {
      for (const id of subscriptions.keys()) unwatch(id);
    },
  };
}
