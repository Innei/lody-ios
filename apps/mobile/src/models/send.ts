import type { ChatDraftAttachment } from '@lody-ios/kit';
import type { Session } from '@lody/cloud-runtime/models/catalog';

export type PendingSend = {
  id: string;
  text: string;
  startedAt: number;
  attachments: ChatDraftAttachment[];
  queue?: boolean;
  guide?: boolean;
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
    configOptionValues?: Record<string, string | boolean>;
  };
};
export type PendingSession = { session: Session; send: PendingSend };

export type CreatedSession = {
  composerRelayId?: string;
  session: Session;
  projectName: string;
  machineName: string;
  modelId?: string;
  effort?: string;
  modeId?: string;
};
