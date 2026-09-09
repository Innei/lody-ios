import type { ChatDraftAttachment } from '@lody-ios/kit';
import type { Project, Session } from './catalog.ts';

export type CapabilityChoice = {
  id: string;
  name: string;
  description?: string;
};

export type Capability = {
  machineId: string;
  cliType: string;
  agentType: string;
  models: CapabilityChoice[];
  modes: CapabilityChoice[];
  reasoningEfforts: Record<string, string[]>;
  reasoningEffortConfigId?: string;
  steer: boolean;
};

export type CreationOptions = {
  sessionId: string;
  project: Project;
  agents: {
    id: string;
    name: string;
    machineId: string;
    machineName: string;
    cliType: string;
    agentType: string;
  }[];
  capabilities: Capability[];
};

export type PendingSend = {
  id: string;
  text: string;
  startedAt: number;
  attachments: ChatDraftAttachment[];
  queue?: boolean;
  phase:
    | 'waiting'
    | 'creating'
    | 'sending'
    | 'accepted'
    | 'queued'
    | 'uploaded'
    | 'unknown'
    | 'failed';
  reason?: string;
  creation?: string;
  choice: {
    modelId?: string | null;
    effort?: string | null;
    modeId?: string;
    reasoningEffortConfigId?: string;
  };
};
export type PendingSession = { session: Session; send: PendingSend };

export type ModelChoice = {
  modelId?: string;
  effort?: string;
  modeId?: string;
};

export type ProjectPrefs = ModelChoice & {
  machineId?: string;
  agentKey?: string;
};

export type CreatePrefs = {
  projectId?: string;
  projects?: Record<string, ProjectPrefs>;
  modelChoices?: Record<string, ModelChoice>;
};

export type CreatedSession = {
  session: Session;
  modelId?: string;
  effort?: string;
  modeId?: string;
};
