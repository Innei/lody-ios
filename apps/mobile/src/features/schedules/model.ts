import type {
  ScheduleAgent,
  ScheduleContext,
  ScheduleDraft,
  ScheduleProposalDetail,
  ScheduleRow,
  ScheduleRule,
  ScheduleRuntimeRow,
  ScheduleService,
  ScheduleTrigger,
} from '@lody/cloud-runtime/models/schedules';
import {
  canonicalScheduleJson,
  matchingScheduleRuntime,
  scheduleUsesElevatedPermissions,
  sensitiveScheduleOption,
  validateScheduleDraft,
} from '@lody/cloud-runtime/protocol/schedules';
import {
  ruleToTrigger,
  triggerToRule,
} from '@lody/cloud-runtime/protocol/schedule-time';
import { currentLocale, t, type TranslationKey } from '../../lib/i18n/index.ts';

export type { ScheduleService };
export const copy = (key: string, vars?: Record<string, string | number>) =>
  t(key as TranslationKey, vars);
export const ruleKinds: ScheduleRule['kind'][] = [
  'manual',
  'daily',
  'weekdays',
  'weekly',
  'monthly',
  'hours',
  'minutes',
  'once',
];
export const ruleTitle = (kind: ScheduleRule['kind']) =>
  copy(`schedules.rule.${kind}`);
export function scheduleDisplayTimeZone(
  trigger: ScheduleTrigger,
  machineTimeZone?: string,
): string {
  return trigger.kind === 'cron'
    ? trigger.timeZone
    : (machineTimeZone ?? 'UTC');
}
export function scheduleRuleCandidate(
  original: ScheduleTrigger,
  rule: ScheduleRule | null,
  timeZone: string,
  now = Date.now(),
): ScheduleTrigger | undefined {
  if (!rule) return original;
  try {
    if (
      canonicalScheduleJson(rule) ===
      canonicalScheduleJson(triggerToRule(original, timeZone))
    )
      return original;
    return ruleToTrigger(rule, now, timeZone);
  } catch {
    return undefined;
  }
}
export const dateLabel = (ms: number, timeZone: string) =>
  new Intl.DateTimeFormat(currentLocale() === 'en' ? 'en-US' : 'zh-CN', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone,
  }).format(ms);
export function frequencyLabel(
  row: Pick<ScheduleRow, 'trigger'>,
  timeZone: string,
) {
  const rule = triggerToRule(row.trigger, timeZone);
  if (!rule) return copy('schedules.rule.custom');
  if (rule.kind === 'minutes' || rule.kind === 'hours')
    return copy(`schedules.frequency.${rule.kind}`, { every: rule.every });
  if (rule.kind === 'once') return dateLabel(Date.parse(rule.at), timeZone);
  if (rule.kind === 'manual') return ruleTitle(rule.kind);
  return `${ruleTitle(rule.kind)} · ${String(rule.hour).padStart(2, '0')}:${String(rule.minute).padStart(2, '0')}`;
}
export function statusLabel(row: ScheduleRow, runtimes: ScheduleRuntimeRow[]) {
  if (!row.enabled) return copy('schedules.status.paused');
  const runtime = matchingScheduleRuntime(row, runtimes);
  if (runtime?.blockedCode) return copy('schedules.status.blocked');
  if (runtime?.queueState)
    return copy(`schedules.status.${runtime.queueState}`);
  return copy('schedules.status.active');
}
export function defaultAgent(
  agent: ScheduleContext['agents'][number],
  context: ScheduleContext,
): ScheduleAgent {
  const capability = context.capabilities.find(
    (entry) =>
      entry.machineId === agent.machineId &&
      entry.cliType === agent.cliType &&
      entry.agentType === agent.agentType,
  );
  const configOptionValues = Object.fromEntries(
    (capability?.configOptions ?? [])
      .filter(
        (option) =>
          !sensitiveScheduleOption(option.id) &&
          option.currentValue !== undefined,
      )
      .map((option) => [option.id, option.currentValue!]),
  );
  const builtin: Record<string, string> = { codex: 'agent', claude: 'default' };
  const modeId = builtin[agent.agentType];
  return {
    agentConfigId: agent.id,
    ...(modeId && capability?.modes.some((entry) => entry.id === modeId)
      ? { modeId }
      : {}),
    ...(Object.keys(configOptionValues).length ? { configOptionValues } : {}),
  };
}
export function newScheduleDraft(
  context: ScheduleContext,
  userId: string,
  now = Date.now(),
): ScheduleDraft {
  const machine = context.machines.find(
    (entry) => entry.ownerId === userId && entry.supported,
  );
  const agent = context.agents.find((entry) => entry.machineId === machine?.id);
  return {
    title: '',
    prompt: '',
    machineId: machine?.id ?? '',
    agent: agent ? defaultAgent(agent, context) : { agentConfigId: '' },
    trigger: ruleToTrigger(
      { kind: 'daily', hour: 9, minute: 0 },
      now,
      machine?.timeZone ?? 'UTC',
    ),
    destination: { kind: 'new_session' },
    misfirePolicy: { kind: 'run_once' },
    overlapPolicy: 'queue_one',
    retryPolicy: { dispatchMaxAttempts: 5, dispatchMaxAgeMs: 86_400_000 },
  };
}
export function rezoneScheduleTrigger(
  trigger: ScheduleTrigger,
  timeZone: string,
): ScheduleTrigger {
  if (trigger.kind !== 'cron') return trigger;
  let rule = triggerToRule(trigger, timeZone);
  if (rule && 'timeZone' in rule) rule = { ...rule, timeZone };
  return rule ? ruleToTrigger(rule, Date.now(), timeZone) : trigger;
}
export function scheduleForDestinationSession(
  draft: ScheduleDraft,
  session: ScheduleContext['sessions'][number],
  context: ScheduleContext,
): ScheduleDraft {
  const agent = context.agents.find(
    (entry) =>
      entry.id === session.agentConfigId &&
      entry.machineId === session.machineId,
  );
  if (!agent) throw new Error(copy('schedules.agentMissing'));
  const zone =
    context.machines.find((entry) => entry.id === session.machineId)
      ?.timeZone ?? 'UTC';
  return {
    ...draft,
    machineId: session.machineId,
    agent: defaultAgent(agent, context),
    project: undefined,
    destination: { kind: 'existing_session', sessionId: session.id },
    trigger: rezoneScheduleTrigger(draft.trigger, zone),
  };
}
export function draftFromProposal(
  detail: ScheduleProposalDetail,
  context: ScheduleContext,
  now = Date.now(),
): ScheduleDraft {
  const { proposal, conversation } = detail,
    named = proposal.target;
  const role = named?.agentRoleId
    ? context.roles.find((entry) => entry.id === named.agentRoleId)
    : undefined;
  if (named?.agentRoleId && !role)
    throw new Error(copy('schedules.roleMissing'));
  const agentId =
    role?.agentConfigId ?? named?.agentConfigId ?? conversation.agentConfigId;
  const agent = context.agents.find((entry) => entry.id === agentId);
  if (!agent) throw new Error(copy('schedules.agentMissing'));
  const constrainedMachine = named?.machineId ?? role?.machineId;
  if (constrainedMachine && constrainedMachine !== agent.machineId)
    throw new Error(copy('schedules.destinationMismatch'));
  const run =
    role?.runConfig ??
    (agent.id === conversation.agentConfigId
      ? conversation.runConfig
      : undefined);
  let runAgent = defaultAgent(agent, context);
  if (run)
    runAgent = {
      agentConfigId: agent.id,
      ...(run.modeId ? { modeId: run.modeId } : {}),
      ...(run.modelId ? { modelId: run.modelId } : {}),
      ...(run.configOptionValues
        ? {
            configOptionValues: Object.fromEntries(
              Object.entries(run.configOptionValues).filter(
                ([id]) => !sensitiveScheduleOption(id),
              ),
            ),
          }
        : {}),
      ...('memory' in run && run.memory ? { memory: run.memory } : {}),
    };
  const machine = context.machines.find(
    (entry) => entry.id === agent.machineId,
  );
  let destination: ScheduleDraft['destination'] = { kind: 'new_session' };
  if (proposal.destination?.kind === 'own_session')
    destination = { kind: 'own_session', epoch: 0 };
  if (proposal.destination?.kind === 'existing_session')
    destination = {
      kind: 'existing_session',
      sessionId: proposal.destination.sessionId,
    };
  const project = named?.project ?? conversation.project;
  return {
    ...newScheduleDraft(context, conversation.ownerId, now),
    title: proposal.title,
    prompt: proposal.prompt,
    machineId: agent.machineId,
    agent: runAgent,
    trigger: ruleToTrigger(proposal.rule, now, machine?.timeZone ?? 'UTC'),
    destination,
    ...(destination.kind === 'new_session' && project ? { project } : {}),
  };
}
export function saveBlockers(
  draft: ScheduleDraft,
  context: ScheduleContext,
  userId: string,
  ownerId = userId,
): string[] {
  const reasons: string[] = [];
  if (ownerId !== userId) reasons.push(copy('schedules.ownerOnly'));
  if (!draft.title.trim()) reasons.push(copy('schedules.requireName'));
  if (!draft.prompt.trim()) reasons.push(copy('schedules.requirePrompt'));
  const machine = context.machines.find(
    (entry) => entry.id === draft.machineId,
  );
  if (!machine) reasons.push(copy('schedules.machineMissing'));
  else if (machine.ownerId !== userId)
    reasons.push(copy('schedules.ownedMachine'));
  else if (!machine.supported) reasons.push(copy('schedules.upgrade'));
  if (
    !context.agents.some(
      (entry) =>
        entry.id === draft.agent.agentConfigId &&
        entry.machineId === draft.machineId,
    )
  )
    reasons.push(copy('schedules.agentMissing'));
  const project = draft.project;
  if (
    project?.kind === 'local' &&
    !context.projects.some(
      (entry) =>
        entry.machineId === draft.machineId &&
        entry.project.kind === 'local' &&
        entry.project.localProjectId === project.localProjectId,
    )
  )
    reasons.push(copy('schedules.projectMachine'));
  if (draft.destination.kind === 'existing_session') {
    const sessionId = draft.destination.sessionId;
    const target = context.sessions.find((entry) => entry.id === sessionId);
    if (
      !target ||
      target.ownerId !== userId ||
      target.machineId !== draft.machineId ||
      target.agentConfigId !== draft.agent.agentConfigId
    )
      reasons.push(copy('schedules.destinationMismatch'));
  }
  try {
    validateScheduleDraft(draft);
  } catch {
    if (draft.title.trim() && draft.prompt.trim())
      reasons.push(copy('schedules.invalidDraft'));
  }
  return reasons;
}
export { scheduleUsesElevatedPermissions, matchingScheduleRuntime };
