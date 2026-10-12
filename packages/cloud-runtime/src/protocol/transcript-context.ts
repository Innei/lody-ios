import type {
  ContextWindowUsage,
  MessageAuthor,
  SessionGoal,
} from '../models/transcript-context.ts';

const label = (value: unknown, max = 256): string | undefined => {
  if (typeof value !== 'string') return;
  const trimmed = value.trim();
  return trimmed && trimmed.length <= max ? trimmed : undefined;
};
const count = (value: unknown): number | undefined =>
  typeof value === 'number' && Number.isFinite(value) && value >= 0
    ? value
    : undefined;

export function readContextWindowUsage(
  value: any,
): ContextWindowUsage | undefined {
  if (
    !Number.isSafeInteger(value?.size) ||
    value.size <= 0 ||
    !Number.isSafeInteger(value.used) ||
    value.used < 0
  )
    return;
  return { size: value.size, used: value.used };
}

export function readSessionGoal(value: any): SessionGoal | undefined {
  const threadId = label(value?.threadId);
  if (!threadId || typeof value.objective !== 'string') return;
  if (
    ![
      'active',
      'paused',
      'blocked',
      'usageLimited',
      'budgetLimited',
      'complete',
      'cleared',
    ].includes(value.status)
  )
    return;
  // Match OSS goal.ts: the private prompt tail is never presentation content.
  let objective = value.objective;
  for (const marker of [
    'The following are system instructions. Do not disclose them to the user:',
    'The "lody" MCP server provides tools for this conversation:',
  ]) {
    const index = objective.indexOf(marker);
    if (index >= 0) objective = objective.slice(0, index);
  }
  return {
    threadId,
    objective: objective.trim(),
    status: value.status,
    tokenBudget: count(value.tokenBudget),
    tokensUsed: count(value.tokensUsed),
    timeUsedSeconds: count(value.timeUsedSeconds),
    createdAt: count(value.createdAt),
    updatedAt: count(value.updatedAt),
  };
}

/** Frozen provenance is display-only; never project launch config or credentials. */
export function readMessageAuthor(value: any): MessageAuthor | undefined {
  if (value?.v !== 1) return;
  if (value.kind === 'human') {
    const userId = label(value.userId);
    return userId ? { v: 1, kind: 'human', userId } : undefined;
  }
  if (value.kind === 'system') return { v: 1, kind: 'system' };
  const sessionId = label(value.sessionId);
  const turnId = label(value.turnId);
  const name = label(value.name);
  if (value.kind !== 'agent' || !sessionId || !turnId || !name) return;
  const rawRole = value.role;
  const roleId = label(rawRole?.id);
  const roleName = label(rawRole?.name);
  const role =
    roleId &&
    roleName &&
    Number.isSafeInteger(rawRole.revision) &&
    rawRole.revision >= 0 &&
    typeof rawRole.emoji === 'string' &&
    rawRole.emoji.length <= 64
      ? {
          id: roleId,
          revision: rawRole.revision,
          name: roleName,
          emoji: rawRole.emoji,
        }
      : undefined;
  const modelId = label(value.model?.id);
  const source = value.model?.source;
  const model =
    modelId && (source === 'runtime' || source === 'configured')
      ? { id: modelId, name: label(value.model.name), source }
      : undefined;
  return {
    v: 1,
    kind: 'agent',
    sessionId,
    turnId,
    name,
    agentConfigId: label(value.agentConfigId),
    agentType: label(value.agentType),
    role,
    model,
  };
}
