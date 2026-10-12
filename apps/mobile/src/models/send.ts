import type { ChatDraftAttachment } from '@lody-ios/kit';
import type { Session } from '@lody/cloud-runtime/models/catalog';
import type { RunOptionsChoice } from '@lody/cloud-runtime/models/run-options';
import type { ModelChoice } from '@lody/cloud-runtime/models/send';

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
  choice: RunOptionsChoice & {
    modelId?: string | null;
    effort?: string | null;
    modeId?: string;
    reasoningEffortConfigId?: string;
    configOptionValues?: Record<string, string | boolean>;
  };
};
export type PendingSession = { session: Session; send: PendingSend };

export type CreatedSession = ModelChoice & {
  composerRelayId?: string;
  session: Session;
  projectName: string;
  machineName: string;
};
