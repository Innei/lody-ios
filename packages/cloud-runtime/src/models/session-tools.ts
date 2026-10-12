export type SessionForkSpec = {
  sourceSessionId: string;
  sourceTurnId: string;
  targetSessionId: string;
  requestedByUserId: string;
  targetContext: {
    kind: 'shared' | 'new-worktree';
    acknowledgeDirtySource?: true;
  };
};

export type SessionForkOperation = {
  id: string;
  sourceSessionId: string;
  sourceTurnId: string;
  requestedByUserId: string;
  targetContext: 'shared' | 'new-worktree';
  capturedHeadSha?: string;
  sourceWasDirty?: boolean;
  state: 'preparing' | 'failed';
  phase?:
    'preparing-worktree' | 'running-setup' | 'starting-agent' | 'committing';
  error?: { code: string; message: string };
  createdAt: string;
  updatedAt: string;
};

export type SessionForkResult = {
  targetSessionId: string;
  state:
    'preparing' | 'completed' | 'failed' | 'confirmation-required' | 'unknown';
  operation?: SessionForkOperation;
  code?: string;
  message?: string;
  partial?: boolean;
  warnings?: { code: string; message: string }[];
};

type Scope = { workspaceId: string; sessionId: string };
export type SessionToolsRequest = Scope &
  (
    | { action: 'fork-options' }
    | { action: 'fork'; spec: SessionForkSpec }
    | { action: 'fork-status'; targetSessionId: string }
    | { action: 'pin'; historyId: string | null }
    | { action: 'unread' }
  );

export type SessionToolsResult =
  | {
      action: 'fork-options';
      shared: boolean;
      newWorktree: boolean;
      targetSessionId: string;
    }
  | { action: 'fork' | 'fork-status'; fork: SessionForkResult }
  | { action: 'pin' | 'unread'; saved: true };

const record = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
const nonempty = (value: unknown): value is string =>
  typeof value === 'string' && value.trim().length > 0;

export function readSessionForkOperation(
  value: unknown,
): SessionForkOperation | undefined {
  const data = record(value);
  if (
    ![
      'id',
      'sourceSessionId',
      'sourceTurnId',
      'requestedByUserId',
      'createdAt',
      'updatedAt',
    ].every((key) => nonempty(data[key])) ||
    !['shared', 'new-worktree'].includes(String(data.targetContext)) ||
    !['preparing', 'failed'].includes(String(data.state)) ||
    (data.phase !== undefined &&
      ![
        'preparing-worktree',
        'running-setup',
        'starting-agent',
        'committing',
      ].includes(String(data.phase))) ||
    (data.capturedHeadSha !== undefined &&
      (typeof data.capturedHeadSha !== 'string' ||
        !/^[0-9a-f]{40,64}$/u.test(data.capturedHeadSha))) ||
    (data.sourceWasDirty !== undefined &&
      typeof data.sourceWasDirty !== 'boolean') ||
    (data.error !== undefined &&
      (!nonempty(record(data.error).code) ||
        !nonempty(record(data.error).message)))
  )
    return undefined;
  return {
    id: data.id as string,
    sourceSessionId: data.sourceSessionId as string,
    sourceTurnId: data.sourceTurnId as string,
    requestedByUserId: data.requestedByUserId as string,
    targetContext: data.targetContext as SessionForkOperation['targetContext'],
    state: data.state as SessionForkOperation['state'],
    phase: data.phase as SessionForkOperation['phase'],
    capturedHeadSha: data.capturedHeadSha as string | undefined,
    sourceWasDirty: data.sourceWasDirty as boolean | undefined,
    error: data.error
      ? {
          code: record(data.error).code as string,
          message: record(data.error).message as string,
        }
      : undefined,
    createdAt: data.createdAt as string,
    updatedAt: data.updatedAt as string,
  };
}

export function sessionForkDocumentResult(
  value: unknown,
  targetSessionId: string,
  sourceSessionId: string,
): SessionForkResult {
  const data = record(value);
  const unknown: SessionForkResult = { targetSessionId, state: 'unknown' };
  const operation = readSessionForkOperation(data.forkOperation);
  if (operation) {
    if (
      operation.sourceSessionId !== sourceSessionId ||
      operation.id !== `session-fork:${targetSessionId}`
    )
      return unknown;
    return {
      targetSessionId,
      state: operation.state,
      operation,
      code: operation.error?.code,
      message: operation.error?.message,
    };
  }
  if (
    data.forkOperation !== undefined &&
    (!data.forkOperation ||
      typeof data.forkOperation !== 'object' ||
      Array.isArray(data.forkOperation) ||
      Object.keys(record(data.forkOperation)).length)
  )
    return unknown;
  if (
    record(data.session).id !== targetSessionId ||
    !Array.isArray(data.history)
  )
    return unknown;
  const origin = data.history.some((entry) => {
    if (record(entry).id !== `session-fork-origin:${targetSessionId}`)
      return false;
    const items = record(entry).items;
    return (
      Array.isArray(items) &&
      items.some(
        (item) =>
          record(item).type === 'system_notice' &&
          record(item).name === 'session_fork_origin' &&
          record(record(item).meta).sourceSessionId === sourceSessionId,
      )
    );
  });
  return origin ? { targetSessionId, state: 'completed' } : unknown;
}

export function sessionForkResponseResult(
  value: unknown,
  spec: SessionForkSpec,
): SessionForkResult {
  const data = record(value);
  const unknown: SessionForkResult = {
    targetSessionId: spec.targetSessionId,
    state: 'unknown',
  };
  if (
    data.type !== 'session/fork_response' ||
    data.sourceSessionId !== spec.sourceSessionId ||
    data.targetSessionId !== spec.targetSessionId ||
    typeof data.success !== 'boolean' ||
    typeof data.partial !== 'boolean' ||
    !Array.isArray(data.warnings) ||
    data.warnings.some(
      (warning) =>
        !nonempty(record(warning).code) || !nonempty(record(warning).message),
    )
  )
    return unknown;
  const result: SessionForkResult = {
    ...unknown,
    partial: data.partial,
    warnings: data.warnings.map((warning) => ({
      code: record(warning).code as string,
      message: record(warning).message as string,
    })),
    code: nonempty(record(data.error).code)
      ? (record(data.error).code as string)
      : undefined,
    message: nonempty(record(data.error).message)
      ? (record(data.error).message as string)
      : undefined,
  };
  if (
    data.disposition === 'confirmation-required' &&
    data.reason === 'SOURCE_WORKTREE_DIRTY'
  )
    return { ...result, state: 'confirmation-required' };
  if (!data.success) return { ...result, state: 'failed' };
  if (data.disposition === 'accepted') return { ...result, state: 'preparing' };
  return { ...result, state: 'completed' };
}
