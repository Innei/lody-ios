import type { Capability, CreationOptions, ModelChoice } from './send.ts';

// Wire shapes from Lody OSS 987962e: schedule-types/control/registry and message-schemas.
export type ScheduleTrigger =
  | { kind: 'manual' }
  | { kind: 'once'; at: string }
  | { kind: 'interval'; everyMs: number; anchorAt: string }
  | { kind: 'cron'; expression: string; timeZone: string };
export type ScheduleDestination =
  | { kind: 'new_session' }
  | { kind: 'own_session'; epoch: number }
  | { kind: 'existing_session'; sessionId: string };
export type ScheduleProject =
  | { kind: 'github'; repoFullName: string; branch: string }
  | {
      kind: 'local';
      localProjectId: string;
      branch?: string;
      githubRepoFullName?: string;
      useWorktree?: boolean;
    };
export type ScheduleAgent = {
  agentConfigId: string;
  memory?: { providerId: string; memoryId: string };
  modeId?: string;
  modelId?: string;
  configOptionValues?: Record<string, string | boolean>;
};
export type ScheduleDraft = {
  title: string;
  prompt: string;
  machineId: string;
  trigger: ScheduleTrigger;
  agent: ScheduleAgent;
  project?: ScheduleProject;
  destination: ScheduleDestination;
  misfirePolicy: { kind: 'skip' | 'run_once' };
  overlapPolicy: 'skip' | 'queue_one';
  retryPolicy: { dispatchMaxAttempts: number; dispatchMaxAgeMs: number };
};
export type ScheduleDefinition = Omit<ScheduleDraft, 'prompt'> & {
  scheduleId: string;
  ownerId: string;
  enabled: boolean;
  activationId: string;
  activeFrom: number;
  createdAt: number;
  updatedAt: number;
  createdBy: string;
};
export type ScheduleActivity = {
  id: string;
  kind: 'created' | 'edited' | 'paused' | 'resumed' | 'deleted' | 'manual_run';
  actorId: string;
  requesterSessionId?: string;
  createdAt: number;
};
export type ScheduleDocument = {
  definition: ScheduleDefinition;
  prompt: string;
  timeline: ScheduleActivity[];
};
export type ScheduleRow = Pick<
  ScheduleDefinition,
  | 'scheduleId'
  | 'title'
  | 'ownerId'
  | 'machineId'
  | 'enabled'
  | 'activationId'
  | 'activeFrom'
  | 'trigger'
  | 'destination'
  | 'createdAt'
  | 'updatedAt'
> & {
  elevatedPermissions: boolean;
  definitionFingerprint: string;
  agentConfigId: string;
  projectKind?: ScheduleProject['kind'];
  projectKey?: string;
};
export type ScheduleRuntimeRow = {
  scheduleId: string;
  machineId: string;
  activationId: string;
  observedDefinitionFingerprint: string;
  nextScheduledAt?: number;
  queueState?: 'due' | 'waiting_for_agent' | 'retrying' | 'blocked';
  blockedCode?: string;
  lastDispatch?: {
    scheduledFor: number;
    dispatchedAt: number;
    sessionId: string;
  };
  updatedAt: number;
};
export type ScheduleMachine = {
  id: string;
  name: string;
  ownerId: string;
  timeZone: string;
  supported: boolean;
  state: 'online' | 'offline' | 'unknown';
};
export type ScheduleRole = {
  id: string;
  name: string;
  machineId: string;
  agentConfigId: string;
  runConfig: ModelChoice & { memory?: ScheduleAgent['memory'] };
  promptPrefix?: string;
};
export type ScheduleContext = {
  machines: ScheduleMachine[];
  agents: CreationOptions['agents'];
  capabilities: Capability[];
  roles: ScheduleRole[];
  projects: {
    id: string;
    machineId: string;
    name: string;
    project: ScheduleProject;
  }[];
  sessions: {
    id: string;
    title: string;
    machineId: string;
    agentConfigId: string;
    ownerId: string;
    project?: ScheduleProject;
    runConfig?: ScheduleAgent;
  }[];
};
type Time = { hour: number; minute: number; timeZone?: string };
export type ScheduleRule =
  | { kind: 'manual' }
  | { kind: 'minutes'; every: number }
  | { kind: 'hours'; every: number }
  | ({ kind: 'daily' } & Time)
  | ({ kind: 'weekdays' } & Time)
  | ({ kind: 'weekly'; weekdays: number[] } & Time)
  | ({ kind: 'monthly'; days: number[] } & Time)
  | { kind: 'once'; at: string };
export type ScheduleProposal = {
  proposalId: string;
  title: string;
  prompt: string;
  rule: ScheduleRule;
  destination?:
    | { kind: 'new_session' | 'own_session' }
    | { kind: 'existing_session'; sessionId: string };
  target?: {
    agentConfigId?: string;
    agentRoleId?: string;
    machineId?: string;
    project?: ScheduleProject;
  };
  outcome?: 'created' | 'dismissed';
  scheduleId?: string;
  proposedBy?: { agentConfigId?: string; name?: string };
};
export type ScheduleProposalRef = {
  sessionId: string;
  entryId: string;
  itemIndex: number;
  proposalId: string;
};
export type ScheduleRequest = { workspaceId: string } & (
  | { action: 'list' }
  | { action: 'context' }
  | { action: 'worktree'; projectId: string }
  | { action: 'show'; scheduleId: string }
  | {
      action: 'create' | 'edit';
      scheduleId: string;
      requestId: string;
      draft: ScheduleDraft;
      proposal?: ScheduleProposalRef;
    }
  | {
      action: 'pause' | 'resume' | 'run';
      scheduleId: string;
      requestId: string;
    }
  | { action: 'delete'; scheduleId: string }
  | { action: 'proposal'; ref: ScheduleProposalRef }
);
export type ScheduleList = {
  rows: ScheduleRow[];
  runtimes: ScheduleRuntimeRow[];
};
export type ScheduleDetail = {
  document: ScheduleDocument;
  runtime?: ScheduleRuntimeRow;
  next: number[];
};
export type ScheduleProposalDetail = {
  proposal: ScheduleProposal;
  conversation: ScheduleContext['sessions'][number];
};
export type ScheduleResult =
  | ScheduleList
  | ScheduleContext
  | ScheduleDetail
  | ScheduleProposalDetail
  | { available: boolean }
  | { ok: true; scheduleId: string };
export type ScheduleService = (
  request: ScheduleRequest,
) => Promise<ScheduleResult>;
