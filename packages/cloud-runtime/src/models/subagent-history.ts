import type { DetailResponse, ItemSummary } from './session.ts';

export type SubagentState =
  'pending' | 'running' | 'completed' | 'failed' | 'cancelled' | 'unknown';

export type SubagentRunMetadata = {
  sessionId: string;
  snapshot: {
    state: SubagentState;
    parentRunId?: string | null;
    parentToolCallId?: string;
    name?: string;
    description?: string;
    modelId?: string;
    startedAtEpochSeconds?: number;
    endedAtEpochSeconds?: number;
    summary?: string;
    outputIncomplete?: true;
    reason?: { code: string; message?: string };
    support: {
      stream: ('text' | 'thought' | 'tool' | 'plan')[];
      progress: boolean;
      outputRead: 'none' | 'live_tail' | 'final_tail';
      cancel: boolean;
    };
  };
  progress?: {
    summary?: string | null;
    lastToolName?: string | null;
    toolsUsed?: string[] | null;
    durationMs?: number | null;
    turnCount?: number | null;
    toolCallCount?: number | null;
    errorCount?: number | null;
    totalTokens?: number | null;
    contextTokens?: number | null;
    contextWindowTokens?: number | null;
    contextUsagePercent?: number | null;
  };
  itemCount: number;
};

export type SubagentIdentity = {
  sessionId: string;
  parentTurnId: string;
  entryId: string;
  itemId: string;
  taskId: string;
  runSessionId?: string;
};

export type SubagentRunChoice = {
  identity: SubagentIdentity;
  state: SubagentState;
  startedAtEpochSeconds?: number;
};

export type SubagentHistoryFragment = {
  index: number;
  nativeTurnId?: string;
  messageId?: string;
  offset?: number;
  total?: number;
  item: ItemSummary;
};

export type SubagentHistoryPage = {
  v: 1;
  identity: SubagentIdentity;
  task: Extract<ItemSummary, { type: 'subagent_task' }>;
  runs: SubagentRunChoice[];
  status: 'ready' | 'unsupported';
  revision: string;
  fragments: SubagentHistoryFragment[];
  nextCursor?: string;
  incomplete: boolean;
};

export type SubagentHistoryRequest =
  | { action: 'watch'; subscriptionId: string; identity: SubagentIdentity }
  | { action: 'page'; identity: SubagentIdentity; cursor?: string }
  | { action: 'unwatch'; subscriptionId: string }
  | {
      action: 'detail';
      identity: SubagentIdentity;
      index: number;
      cursor?: string;
    };

export type SubagentHistoryResponse =
  SubagentHistoryPage | DetailResponse | { state: 'released' };

export const subagentIdentityKey = (identity: SubagentIdentity): string =>
  JSON.stringify([
    identity.sessionId,
    identity.parentTurnId,
    identity.entryId,
    identity.itemId,
    identity.taskId,
    identity.runSessionId ?? null,
  ]);
