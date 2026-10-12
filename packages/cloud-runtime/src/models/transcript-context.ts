export type ContextWindowUsage = { size: number; used: number };

export type SessionGoal = {
  threadId: string;
  objective: string;
  status:
    | 'active'
    | 'paused'
    | 'blocked'
    | 'usageLimited'
    | 'budgetLimited'
    | 'complete'
    | 'cleared';
  tokenBudget?: number;
  tokensUsed?: number;
  timeUsedSeconds?: number;
  createdAt?: number;
  updatedAt?: number;
};

export type MessageAuthor =
  | { v: 1; kind: 'human'; userId: string }
  | { v: 1; kind: 'system' }
  | {
      v: 1;
      kind: 'agent';
      sessionId: string;
      turnId: string;
      name: string;
      agentConfigId?: string;
      agentType?: string;
      role?: { id: string; revision: number; name: string; emoji: string };
      model?: { id: string; name?: string; source: 'configured' | 'runtime' };
    };

export type PendingScheduledTask = {
  id: string;
  kind: 'cron' | 'wakeup';
  createdAtMs: number;
  scheduledForMs?: number;
  nextFireMs?: number;
  humanSchedule?: string;
  recurring?: boolean;
  summary?: string;
  timeZone?: string;
};
