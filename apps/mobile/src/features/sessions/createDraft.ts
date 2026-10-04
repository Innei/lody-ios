import type { ChatDraftAttachment } from '@lody-ios/kit';
import type { Session } from '../../models/catalog.ts';
import type {
  CreatedSession,
  CreationOptions,
  ModelChoice,
  PendingSession,
} from '../../models/send.ts';
import { draftTitle } from './draftTitle.ts';
import { t } from '../../lib/i18n/index.ts';

export type NativeCreateDraft = {
  sessionId: string;
  userId: string;
  workspaceId: string;
  projectId?: string;
  projectName: string;
  branch?: string;
  agent: CreationOptions['agents'][number];
  choice: ModelChoice;
  reasoningEffortConfigId?: string;
};

export type ComposerPayload = {
  id: string;
  text: string;
  startedAt: number;
  attachments: ChatDraftAttachment[];
};

export function pendingSessionFromDraft(
  draft: NativeCreateDraft,
  payload: ComposerPayload,
  createdAt = new Date().toISOString(),
): { record: PendingSession; created: CreatedSession } {
  const { agent } = draft;
  const session: Session = {
    id: draft.sessionId,
    projectId: draft.projectId ?? `${agent.machineId}:unassigned`,
    machineId: agent.machineId,
    cliType: agent.cliType,
    agentType: agent.agentType,
    title: draftTitle(payload.text),
    status: 'idle',
    archived: false,
    pinned: false,
    createdAt,
  };
  const send = {
    id: payload.id,
    text: payload.text,
    startedAt: payload.startedAt,
    attachments: payload.attachments,
    phase: 'waiting' as const,
    choice: {
      ...draft.choice,
      reasoningEffortConfigId: draft.reasoningEffortConfigId,
    },
    creation: JSON.stringify({
      workspaceId: draft.workspaceId,
      sessionId: session.id,
      machineId: session.machineId,
      agentConfigId: agent.id,
      userId: draft.userId,
      title: session.title,
      ...(draft.projectId ? { projectId: draft.projectId } : {}),
      ...(draft.branch ? { branch: draft.branch } : {}),
    }),
  };
  return {
    record: { session, send },
    created: {
      composerRelayId: payload.id,
      session,
      projectName: draft.projectId
        ? draft.projectName
        : t('inbox.section.chat'),
      machineName: agent.machineName,
      ...draft.choice,
    },
  };
}
