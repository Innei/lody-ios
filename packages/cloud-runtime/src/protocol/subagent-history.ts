import type {
  SubagentRunMetadata,
  SubagentState,
} from '../models/subagent-history.ts';

const states = new Set<SubagentState>([
  'pending',
  'running',
  'completed',
  'failed',
  'cancelled',
  'unknown',
]);
const stringFields = [
  'parentToolCallId',
  'name',
  'description',
  'modelId',
  'summary',
] as const;
const numberFields = ['startedAtEpochSeconds', 'endedAtEpochSeconds'] as const;
const progressNumbers = [
  'durationMs',
  'turnCount',
  'toolCallCount',
  'errorCount',
  'totalTokens',
  'contextTokens',
  'contextWindowTokens',
  'contextUsagePercent',
] as const;
type Raw = Record<string, any>;
const record = (value: unknown): value is Raw =>
  !!value && typeof value === 'object' && !Array.isArray(value);
const nonnegative = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value) && value >= 0;

export function readSubagentRunMetadata(
  value: unknown,
): SubagentRunMetadata | undefined {
  if (!record(value) || typeof value.sessionId !== 'string' || !value.sessionId)
    return undefined;
  const raw = value.snapshot;
  const support = raw?.support;
  if (
    !record(raw) ||
    !states.has(raw.state) ||
    !record(support) ||
    !Array.isArray(support.stream) ||
    support.stream.some(
      (kind: unknown) =>
        typeof kind !== 'string' ||
        !['text', 'thought', 'tool', 'plan'].includes(kind),
    ) ||
    typeof support.progress !== 'boolean' ||
    typeof support.cancel !== 'boolean' ||
    !['none', 'live_tail', 'final_tail'].includes(support.outputRead) ||
    !Array.isArray(value.items)
  )
    return undefined;
  const snapshot: SubagentRunMetadata['snapshot'] = {
    state: raw.state,
    support: {
      stream: [...support.stream],
      progress: support.progress,
      outputRead: support.outputRead,
      cancel: support.cancel,
    },
  };
  for (const key of stringFields) {
    if (raw[key] != null && typeof raw[key] !== 'string') return undefined;
    if (typeof raw[key] === 'string') snapshot[key] = raw[key];
  }
  for (const key of numberFields) {
    if (raw[key] != null && !nonnegative(raw[key])) return undefined;
    if (nonnegative(raw[key])) snapshot[key] = raw[key];
  }
  if (raw.parentRunId === null || typeof raw.parentRunId === 'string')
    snapshot.parentRunId = raw.parentRunId;
  else if (raw.parentRunId != null) return undefined;
  if (raw.outputIncomplete === true) snapshot.outputIncomplete = true;
  else if (raw.outputIncomplete != null) return undefined;
  if (raw.reason != null) {
    if (
      !record(raw.reason) ||
      !['error', 'timeout', 'cancelled', 'disconnected', 'lost'].includes(
        raw.reason.code,
      ) ||
      (raw.reason.message != null && typeof raw.reason.message !== 'string')
    )
      return undefined;
    snapshot.reason = { code: raw.reason.code };
    if (typeof raw.reason.message === 'string')
      snapshot.reason.message = raw.reason.message;
  }
  let progress: SubagentRunMetadata['progress'];
  if (value.progress != null) {
    if (!record(value.progress)) return undefined;
    progress = {};
    for (const key of ['summary', 'lastToolName'] as const) {
      const field = value.progress[key];
      if (field === null || typeof field === 'string') progress[key] = field;
      else if (field != null) return undefined;
    }
    for (const key of progressNumbers) {
      const field = value.progress[key];
      if (field === null || nonnegative(field)) progress[key] = field;
      else if (field != null) return undefined;
    }
    const tools = value.progress.toolsUsed;
    if (tools === null) progress.toolsUsed = null;
    else if (
      Array.isArray(tools) &&
      tools.every((tool) => typeof tool === 'string')
    )
      progress.toolsUsed = [...tools];
    else if (tools != null) return undefined;
  }
  return {
    sessionId: value.sessionId,
    snapshot,
    progress,
    itemCount: value.items.length,
  };
}
