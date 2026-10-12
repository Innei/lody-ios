import type {
  ScheduleActivity,
  ScheduleAgent,
  ScheduleDefinition,
  ScheduleDestination,
  ScheduleDocument,
  ScheduleDraft,
  ScheduleProject,
  ScheduleProposal,
  ScheduleRow,
  ScheduleRuntimeRow,
  ScheduleRule,
  ScheduleTrigger,
  ScheduleRequest,
} from '../models/schedules.ts';
import { ruleToTrigger, validateScheduleTrigger } from './schedule-time.ts';

export const scheduleId = (value: unknown): value is string =>
  typeof value === 'string' && /^[a-zA-Z0-9_-]{1,50}$/.test(value);
export const object = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
const text = (value: unknown, max = 4096): value is string =>
  typeof value === 'string' && value.length > 0 && value.length <= max;
const timestamp = (value: unknown): value is number =>
  typeof value === 'number' &&
  Number.isInteger(value) &&
  value >= 0 &&
  value <= 8_640_000_000_000_000;
function invalid(): never {
  throw new Error('schedule_invalid');
}
function strict(value: Record<string, unknown>, keys: string[]) {
  if (Object.keys(value).some((key) => !keys.includes(key))) invalid();
}
export const sensitiveScheduleOption = (id: string) =>
  /(?:api[_-]?key|auth|bearer|credential|password|passwd|secret|token)/i.test(
    id,
  );
export function parseScheduleAgent(value: unknown): ScheduleAgent {
  const row = object(value);
  strict(row, [
    'agentConfigId',
    'memory',
    'modeId',
    'modelId',
    'configOptionValues',
  ]);
  if (
    !text(row.agentConfigId) ||
    (row.modeId !== undefined && !text(row.modeId)) ||
    (row.modelId !== undefined && !text(row.modelId))
  )
    invalid();
  if (row.memory !== undefined) {
    const memory = object(row.memory);
    strict(memory, ['providerId', 'memoryId']);
    if (!text(memory.providerId, 100) || !text(memory.memoryId, 200)) invalid();
  }
  if (row.configOptionValues !== undefined) {
    const values = object(row.configOptionValues);
    if (
      values !== row.configOptionValues ||
      Object.keys(values).length > 50 ||
      Object.entries(values).some(
        ([key, entry]) =>
          !key ||
          key.length > 100 ||
          sensitiveScheduleOption(key) ||
          !(
            typeof entry === 'boolean' ||
            (typeof entry === 'string' && entry.length <= 1024)
          ),
      )
    )
      invalid();
  }
  return row as ScheduleAgent;
}
export function parseScheduleProject(value: unknown): ScheduleProject {
  const row = object(value);
  if (row.kind === 'github') {
    strict(row, ['kind', 'repoFullName', 'branch']);
    if (!text(row.repoFullName) || !text(row.branch)) invalid();
  } else if (row.kind === 'local') {
    strict(row, [
      'kind',
      'localProjectId',
      'branch',
      'githubRepoFullName',
      'useWorktree',
    ]);
    if (
      !text(row.localProjectId) ||
      (row.branch !== undefined && !text(row.branch)) ||
      (row.githubRepoFullName !== undefined && !text(row.githubRepoFullName)) ||
      (row.useWorktree !== undefined && typeof row.useWorktree !== 'boolean')
    )
      invalid();
  } else invalid();
  return row as ScheduleProject;
}
export function parseScheduleDestination(value: unknown): ScheduleDestination {
  if (value === undefined) return { kind: 'new_session' };
  const row = object(value);
  if (row.kind === 'new_session') strict(row, ['kind']);
  else if (row.kind === 'own_session') {
    strict(row, ['kind', 'epoch']);
    if (!timestamp(row.epoch)) invalid();
  } else if (row.kind === 'existing_session') {
    strict(row, ['kind', 'sessionId']);
    if (!text(row.sessionId)) invalid();
  } else invalid();
  return row as ScheduleDestination;
}
function parseTrigger(value: unknown): ScheduleTrigger {
  const row = object(value);
  const keys: Record<string, string[]> = {
    manual: ['kind'],
    once: ['kind', 'at'],
    interval: ['kind', 'everyMs', 'anchorAt'],
    cron: ['kind', 'expression', 'timeZone'],
  };
  if (typeof row.kind !== 'string' || !keys[row.kind]) invalid();
  strict(row, keys[row.kind]);
  return validateScheduleTrigger(row as ScheduleTrigger);
}
const draftKeys = [
  'title',
  'machineId',
  'trigger',
  'misfirePolicy',
  'overlapPolicy',
  'agent',
  'project',
  'destination',
  'retryPolicy',
  'prompt',
];
export function validateScheduleDraft(value: unknown): ScheduleDraft {
  const row = object(value);
  strict(row, draftKeys);
  if (
    !text(row.title, 200) ||
    !row.title.trim() ||
    !text(row.machineId) ||
    !text(row.prompt, 32768) ||
    !row.prompt.trim() ||
    new TextEncoder().encode(row.prompt).length > 32768
  )
    invalid();
  const misfire = object(row.misfirePolicy),
    retry = object(row.retryPolicy);
  strict(misfire, ['kind']);
  strict(retry, ['dispatchMaxAttempts', 'dispatchMaxAgeMs']);
  if (
    !['skip', 'run_once'].includes(String(misfire.kind)) ||
    !['skip', 'queue_one'].includes(String(row.overlapPolicy)) ||
    !timestamp(retry.dispatchMaxAttempts) ||
    retry.dispatchMaxAttempts < 1 ||
    retry.dispatchMaxAttempts > 5 ||
    !timestamp(retry.dispatchMaxAgeMs) ||
    retry.dispatchMaxAgeMs < 1 ||
    retry.dispatchMaxAgeMs > 86_400_000
  )
    invalid();
  return {
    ...row,
    title: row.title.trim(),
    trigger: parseTrigger(row.trigger),
    agent: parseScheduleAgent(row.agent),
    destination: parseScheduleDestination(row.destination),
    ...(row.project !== undefined
      ? { project: parseScheduleProject(row.project) }
      : {}),
  } as ScheduleDraft;
}
export function parseScheduleDefinition(
  value: unknown,
  prompt: string,
): ScheduleDefinition {
  const row = object(value);
  const identity = [
    'scheduleId',
    'ownerId',
    'enabled',
    'activationId',
    'activeFrom',
    'createdAt',
    'updatedAt',
    'createdBy',
  ];
  strict(row, [...draftKeys.filter((key) => key !== 'prompt'), ...identity]);
  if (
    !scheduleId(row.scheduleId) ||
    !text(row.ownerId) ||
    typeof row.enabled !== 'boolean' ||
    !scheduleId(row.activationId) ||
    !timestamp(row.activeFrom) ||
    !timestamp(row.createdAt) ||
    !timestamp(row.updatedAt) ||
    !text(row.createdBy)
  )
    invalid();
  const draft = Object.fromEntries(
    Object.entries(row).filter(([key]) => !identity.includes(key)),
  );
  const { prompt: _prompt, ...parsed } = validateScheduleDraft({
    ...draft,
    prompt,
  });
  return { ...row, ...parsed } as ScheduleDefinition;
}
export function parseScheduleDocument(
  value: unknown,
  id: string,
): ScheduleDocument {
  const row = object(value);
  if (typeof row.prompt !== 'string' || !Array.isArray(row.timeline)) invalid();
  const definition = parseScheduleDefinition(row.definition, row.prompt);
  if (definition.scheduleId !== id) invalid();
  for (const entry of row.timeline) {
    const item = object(entry);
    strict(item, ['id', 'kind', 'actorId', 'requesterSessionId', 'createdAt']);
    if (
      !scheduleId(item.id) ||
      ![
        'created',
        'edited',
        'paused',
        'resumed',
        'deleted',
        'manual_run',
      ].includes(String(item.kind)) ||
      !text(item.actorId) ||
      !timestamp(item.createdAt) ||
      (item.requesterSessionId !== undefined &&
        !scheduleId(item.requesterSessionId))
    )
      invalid();
  }
  return {
    definition,
    prompt: row.prompt,
    timeline: row.timeline as ScheduleActivity[],
  };
}
export function canonicalScheduleJson(value: unknown): string {
  const normalize = (entry: unknown): unknown => {
    if (Array.isArray(entry)) return entry.map(normalize);
    if (entry !== null && typeof entry === 'object')
      return Object.fromEntries(
        Object.entries(entry)
          .filter(([, v]) => v !== undefined)
          .sort(([a], [b]) => (a < b ? -1 : Number(a > b)))
          .map(([key, v]) => [key, normalize(v)]),
      );
    return entry;
  };
  return JSON.stringify(normalize(value));
}
export async function scheduleFingerprint(
  document: ScheduleDocument,
): Promise<string> {
  const {
    title: _title,
    createdAt: _createdAt,
    updatedAt: _updatedAt,
    createdBy: _createdBy,
    ...definition
  } = parseScheduleDefinition(document.definition, document.prompt);
  const digest = new Uint8Array(
    await crypto.subtle.digest(
      'SHA-256',
      new TextEncoder().encode(
        canonicalScheduleJson({ definition, prompt: document.prompt }),
      ),
    ),
  );
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
export async function scheduleOwnSessionId(
  id: string,
  epoch: number,
): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest(
      'SHA-256',
      new TextEncoder().encode(
        canonicalScheduleJson(['lody.schedule.v1', 'own-session', id, epoch]),
      ),
    ),
  );
  const hex = [...digest]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
    .slice(0, 32)
    .split('');
  hex[12] = '8';
  hex[16] = ((parseInt(hex[16], 16) & 3) | 8).toString(16);
  const value = hex.join('');
  return `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${value.slice(16, 20)}-${value.slice(20)}`;
}
export const scheduleUsesElevatedPermissions = (agent: ScheduleAgent) =>
  [agent.modeId, ...Object.values(agent.configOptionValues ?? {})].some(
    (value) =>
      typeof value === 'string' &&
      [
        'agent-full-access',
        'danger-full-access',
        'dontAsk',
        'bypassPermissions',
        'yolo',
        'always-approve',
      ].includes(value),
  );
export async function buildScheduleRow(
  document: ScheduleDocument,
): Promise<ScheduleRow> {
  const d = document.definition;
  let projectFields: Pick<ScheduleRow, 'projectKind' | 'projectKey'> = {};
  if (d.project)
    projectFields = {
      projectKind: d.project.kind,
      projectKey:
        d.project.kind === 'local'
          ? d.project.localProjectId
          : d.project.repoFullName,
    };
  return {
    scheduleId: d.scheduleId,
    title: d.title,
    ownerId: d.ownerId,
    machineId: d.machineId,
    enabled: d.enabled,
    activationId: d.activationId,
    activeFrom: d.activeFrom,
    trigger: d.trigger,
    destination: d.destination,
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
    agentConfigId: d.agent.agentConfigId,
    elevatedPermissions: scheduleUsesElevatedPermissions(d.agent),
    definitionFingerprint: await scheduleFingerprint(document),
    ...projectFields,
  };
}
export function readScheduleRegistry(
  scanned: Iterable<{ key: readonly unknown[]; value?: unknown }>,
) {
  const rows: ScheduleRow[] = [],
    runtimes: ScheduleRuntimeRow[] = [],
    deleted = new Set<string>();
  for (const entry of scanned) {
    const row = object(entry.value);
    if (
      entry.key.length === 2 &&
      entry.key[0] === 'tombstone' &&
      text(entry.key[1]) &&
      timestamp(row.deletedAt) &&
      text(row.actorId)
    )
      deleted.add(entry.key[1]);
    if (
      entry.key.length === 2 &&
      entry.key[0] === 'schedule' &&
      row.scheduleId === entry.key[1]
    ) {
      try {
        if (
          !scheduleId(row.scheduleId) ||
          !text(row.title, 200) ||
          !text(row.ownerId) ||
          !text(row.machineId) ||
          typeof row.enabled !== 'boolean' ||
          !scheduleId(row.activationId) ||
          !timestamp(row.activeFrom) ||
          !timestamp(row.createdAt) ||
          !timestamp(row.updatedAt) ||
          !text(row.agentConfigId) ||
          typeof row.definitionFingerprint !== 'string' ||
          !/^[a-f0-9]{64}$/.test(row.definitionFingerprint)
        )
          continue;
        const keys = [
          'scheduleId',
          'title',
          'ownerId',
          'machineId',
          'enabled',
          'activationId',
          'activeFrom',
          'createdAt',
          'updatedAt',
          'agentConfigId',
          'definitionFingerprint',
        ];
        const safe = Object.fromEntries(keys.map((key) => [key, row[key]]));
        if (row.projectKind === 'local' || row.projectKind === 'github')
          safe.projectKind = row.projectKind;
        if (text(row.projectKey)) safe.projectKey = row.projectKey;
        rows.push({
          ...safe,
          trigger: parseTrigger(row.trigger),
          destination: parseScheduleDestination(row.destination),
          elevatedPermissions: row.elevatedPermissions === true,
        } as ScheduleRow);
      } catch {
        /* An invalid registry row never grants execution. */
      }
    }
    if (
      entry.key.length === 3 &&
      entry.key[0] === 'runtime' &&
      row.scheduleId === entry.key[1] &&
      row.machineId === entry.key[2] &&
      scheduleId(row.scheduleId) &&
      text(row.machineId) &&
      scheduleId(row.activationId) &&
      typeof row.observedDefinitionFingerprint === 'string' &&
      timestamp(row.updatedAt)
    ) {
      if (
        (row.nextScheduledAt !== undefined &&
          !timestamp(row.nextScheduledAt)) ||
        (row.queueState !== undefined &&
          !['due', 'waiting_for_agent', 'retrying', 'blocked'].includes(
            String(row.queueState),
          )) ||
        (row.blockedCode !== undefined && !text(row.blockedCode, 100))
      )
        continue;
      const keys = [
        'scheduleId',
        'machineId',
        'activationId',
        'observedDefinitionFingerprint',
        'updatedAt',
        'nextScheduledAt',
        'queueState',
        'blockedCode',
      ];
      const safe = Object.fromEntries(
        keys
          .filter((key) => row[key] !== undefined)
          .map((key) => [key, row[key]]),
      );
      const last = object(row.lastDispatch);
      if (
        timestamp(last.scheduledFor) &&
        timestamp(last.dispatchedAt) &&
        typeof last.sessionId === 'string'
      )
        safe.lastDispatch = {
          scheduledFor: last.scheduledFor,
          dispatchedAt: last.dispatchedAt,
          sessionId: last.sessionId,
        };
      runtimes.push(safe as ScheduleRuntimeRow);
    }
  }
  return { rows: rows.filter((row) => !deleted.has(row.scheduleId)), runtimes };
}
export function matchingScheduleRuntime(
  row: ScheduleRow,
  runtimes: ScheduleRuntimeRow[],
) {
  return runtimes.find(
    (runtime) =>
      runtime.scheduleId === row.scheduleId &&
      runtime.machineId === row.machineId &&
      runtime.activationId === row.activationId &&
      runtime.observedDefinitionFingerprint === row.definitionFingerprint,
  );
}
export function parseScheduleProposal(
  value: unknown,
): ScheduleProposal | undefined {
  try {
    const row = object(value),
      rule = object(row.rule);
    if (
      !scheduleId(row.proposalId) ||
      !text(row.title, 200) ||
      !row.title.trim() ||
      !text(row.prompt, 32768) ||
      !row.prompt.trim() ||
      new TextEncoder().encode(row.prompt).length > 32768
    )
      return undefined;
    const ruleKeys: Record<string, string[]> = {
      manual: ['kind'],
      minutes: ['kind', 'every'],
      hours: ['kind', 'every'],
      daily: ['kind', 'hour', 'minute', 'timeZone'],
      weekdays: ['kind', 'hour', 'minute', 'timeZone'],
      weekly: ['kind', 'hour', 'minute', 'timeZone', 'weekdays'],
      monthly: ['kind', 'hour', 'minute', 'timeZone', 'days'],
      once: ['kind', 'at'],
    };
    if (typeof rule.kind !== 'string' || !ruleKeys[rule.kind]) return undefined;
    strict(rule, ruleKeys[rule.kind]);
    if (rule.timeZone !== undefined && !text(rule.timeZone, 100))
      return undefined;
    if (
      rule.kind === 'weekly' &&
      (!Array.isArray(rule.weekdays) || rule.weekdays.length > 7)
    )
      return undefined;
    if (
      rule.kind === 'monthly' &&
      (!Array.isArray(rule.days) || rule.days.length > 31)
    )
      return undefined;
    if (
      (rule.kind === 'minutes' &&
        (!timestamp(rule.every) || rule.every < 1 || rule.every > 59)) ||
      (rule.kind === 'hours' &&
        (!timestamp(rule.every) || rule.every < 1 || rule.every > 23))
    )
      return undefined;
    ruleToTrigger(
      rule as ScheduleRule,
      0,
      typeof rule.timeZone === 'string' ? rule.timeZone : 'UTC',
    );
    let destination: ScheduleProposal['destination'];
    if (row.destination !== undefined) {
      const d = object(row.destination);
      if (d.kind === 'own_session') {
        strict(d, ['kind']);
        destination = { kind: 'own_session' };
      } else
        destination = parseScheduleDestination(
          d,
        ) as ScheduleProposal['destination'];
    }
    let target: ScheduleProposal['target'];
    if (row.target !== undefined) {
      const named = object(row.target);
      strict(named, ['agentConfigId', 'agentRoleId', 'machineId', 'project']);
      for (const key of ['agentConfigId', 'agentRoleId', 'machineId'])
        if (named[key] !== undefined && !text(named[key])) invalid();
      target = {
        ...named,
        ...(named.project !== undefined
          ? { project: parseScheduleProject(named.project) }
          : {}),
      };
    }
    if (
      (row.outcome !== undefined &&
        !['created', 'dismissed'].includes(String(row.outcome))) ||
      (row.scheduleId !== undefined && !scheduleId(row.scheduleId))
    )
      return undefined;
    const actor = object(row.proposedBy);
    let proposedBy: ScheduleProposal['proposedBy'];
    if (row.proposedBy)
      proposedBy = {
        ...(text(actor.agentConfigId)
          ? { agentConfigId: actor.agentConfigId }
          : {}),
        ...(text(actor.name) ? { name: actor.name } : {}),
      };
    return {
      proposalId: row.proposalId,
      title: row.title.trim(),
      prompt: row.prompt,
      rule: rule as ScheduleRule,
      ...(destination ? { destination } : {}),
      ...(target ? { target } : {}),
      ...(row.outcome
        ? { outcome: row.outcome as ScheduleProposal['outcome'] }
        : {}),
      ...(row.scheduleId ? { scheduleId: row.scheduleId as string } : {}),
      ...(proposedBy ? { proposedBy } : {}),
    };
  } catch {
    return undefined;
  }
}
export function validateScheduleRequest(value: unknown): ScheduleRequest {
  const row = object(value),
    action = row.action;
  const keys: Record<string, string[]> = {
    list: [],
    context: [],
    worktree: ['projectId'],
    show: ['scheduleId'],
    create: ['scheduleId', 'requestId', 'draft', 'proposal'],
    edit: ['scheduleId', 'requestId', 'draft'],
    pause: ['scheduleId', 'requestId'],
    resume: ['scheduleId', 'requestId'],
    run: ['scheduleId', 'requestId'],
    delete: ['scheduleId'],
    proposal: ['ref'],
  };
  if (typeof action !== 'string' || !keys[action] || !text(row.workspaceId))
    invalid();
  strict(row, ['workspaceId', 'action', ...keys[action]]);
  if (keys[action].includes('scheduleId') && !scheduleId(row.scheduleId))
    invalid();
  if (keys[action].includes('requestId') && !scheduleId(row.requestId))
    invalid();
  if (action === 'worktree' && !text(row.projectId)) invalid();
  if (action === 'create' || action === 'edit')
    validateScheduleDraft(row.draft);
  const source = action === 'proposal' ? row.ref : row.proposal;
  if (source !== undefined || action === 'proposal') {
    const ref = object(source);
    strict(ref, ['sessionId', 'entryId', 'itemIndex', 'proposalId']);
    if (
      !text(ref.sessionId) ||
      !text(ref.entryId) ||
      !scheduleId(ref.proposalId) ||
      !timestamp(ref.itemIndex) ||
      ref.itemIndex > 100_000
    )
      invalid();
  }
  return row as ScheduleRequest;
}
