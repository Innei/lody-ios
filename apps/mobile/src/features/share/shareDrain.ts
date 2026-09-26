import type { ChatDraftAttachment } from '@lody-ios/kit';
import type { Session } from '../../models/catalog.ts';
import type { CreationOptions, PendingSession } from '../../models/send.ts';
import {
  pendingSessionFromDraft,
  type NativeCreateDraft,
} from '../sessions/createDraft.ts';

export type ShareEntry = {
  id: string;
  userId: string;
  workspaceId: string;
  projectId?: string;
  context: 'project' | 'chat';
  text: string;
  attachments: ChatDraftAttachment[];
  draft?: NativeCreateDraft;
};

export type ShareStep =
  | { kind: 'idle' }
  | { kind: 'discard'; id: string }
  | { kind: 'workspace'; id: string }
  | { kind: 'wait' }
  | { kind: 'deliver'; entry: ShareEntry };

export function nextShareStep(
  entries: ShareEntry[],
  state: {
    userId: string;
    workspaceIds: string[];
    selectedId?: string;
    loading: boolean;
    skip?: ReadonlySet<string>;
  },
): ShareStep {
  const entry = entries.find((item) => !state.skip?.has(item.id));
  if (!entry) return { kind: 'idle' };
  if (
    entry.userId !== state.userId ||
    !state.workspaceIds.includes(entry.workspaceId)
  )
    return { kind: 'discard', id: entry.id };
  if (state.selectedId !== entry.workspaceId)
    return { kind: 'workspace', id: entry.workspaceId };
  if (state.loading) return { kind: 'wait' };
  return { kind: 'deliver', entry };
}

export function selectionAvailable(
  draft: NativeCreateDraft,
  options: CreationOptions,
) {
  const agent = options.agents.find(
    (item) =>
      item.id === draft.agent.id && item.machineId === draft.agent.machineId,
  );
  if (!agent) return false;
  const modelId = draft.choice.modelId;
  if (!modelId) return true;
  return options.capabilities.some(
    (capability) =>
      capability.machineId === agent.machineId &&
      capability.cliType === agent.cliType &&
      capability.agentType === agent.agentType &&
      capability.models.some((model) => model.id === modelId),
  );
}

export type ShareDeps = {
  adopt: (id: string) => ShareEntry;
  remove: (id: string) => void;
  agentAvailable: (draft: NativeCreateDraft) => Promise<boolean>;
  put: (record: PendingSession) => Promise<unknown>;
  openSession: (session: Session) => void;
  openForm: (entry: ShareEntry) => Promise<unknown>;
  toast: (key: 'shareInbox.unreadable' | 'shareInbox.saveFailed') => void;
  now: () => number;
};

export async function deliverShare(
  entry: ShareEntry,
  deps: ShareDeps,
): Promise<'done' | 'kept'> {
  let adopted: ShareEntry;
  try {
    adopted = deps.adopt(entry.id);
  } catch {
    deps.remove(entry.id);
    deps.toast('shareInbox.unreadable');
    return 'done';
  }
  const { draft } = adopted;
  if (!draft || !(await deps.agentAvailable(draft))) {
    deps.remove(entry.id);
    await deps.openForm(adopted);
    return 'done';
  }
  const { record } = pendingSessionFromDraft(draft, {
    id: `share-${entry.id}`,
    text: adopted.text,
    startedAt: deps.now(),
    attachments: adopted.attachments,
  });
  try {
    await deps.put(record);
  } catch {
    deps.toast('shareInbox.saveFailed');
    return 'kept';
  }
  deps.remove(entry.id);
  deps.openSession(record.session);
  return 'done';
}
