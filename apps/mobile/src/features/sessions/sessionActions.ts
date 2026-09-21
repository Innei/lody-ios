import {
  archiveSession,
  deleteSession,
  pinSession,
  markSessionRead,
  renameSession,
} from '@lody-ios/kit';
import { Alert } from 'react-native';
import { showToast } from '../../ui/toast.ts';
import type { Catalog, Session } from '../../models/catalog.ts';
import { t } from '../../lib/i18n/index.ts';
import { openCatalogRow } from '../../hooks/screens/openCatalogRow.ts';
import { requestNewSession, requestShareSession } from './sessionNav.ts';
import { isChatSession, projectIdOfRow } from './inbox.ts';
import {
  sessionDeletionTargets,
  sessionDeletionBlocked,
} from '../../models/sessionDeletion.ts';

type DeletionEvent = {
  workspaceId: string;
  sessionIds: string[];
  state: 'deleting' | 'deleted' | 'failed';
};
const deletionListeners = new Set<(event: DeletionEvent) => void>();
const deleting = new Set<string>();
export function isSessionDeleting(workspaceId: string, sessionId: string) {
  return deleting.has(JSON.stringify([workspaceId, sessionId]));
}
export function subscribeSessionDeletion(
  listener: (event: DeletionEvent) => void,
) {
  deletionListeners.add(listener);
  return () => {
    deletionListeners.delete(listener);
  };
}

export function confirmSessionDeletion(
  workspaceId: string,
  session: Session,
  catalog: Catalog,
  request = deleteSession,
) {
  const targets = sessionDeletionTargets(catalog.sessions, session.id);
  const sessionIds = targets.map((item) => item.id);
  const keys = sessionIds.map((id) => JSON.stringify([workspaceId, id]));
  if (keys.some((key) => deleting.has(key))) return;
  if (sessionDeletionBlocked(targets)) {
    Alert.alert(t('session.delete.title'), t('session.delete.busy'));
    return;
  }
  let message =
    targets.length > 1
      ? t('session.delete.withTabs', {
          title: session.title,
          count: targets.length - 1,
        })
      : t('session.delete.message', { title: session.title });
  if (!isChatSession(session)) message += '\n\n' + t('session.delete.worktree');
  Alert.alert(t('session.delete.title'), message, [
    { text: t('common.cancel'), style: 'cancel' },
    {
      text: t('session.action.delete'),
      style: 'destructive',
      onPress: () => {
        if (keys.some((key) => deleting.has(key))) return;
        keys.forEach((key) => deleting.add(key));
        const emit = (state: DeletionEvent['state']) => {
          if (state !== 'deleting') keys.forEach((key) => deleting.delete(key));
          deletionListeners.forEach((listener) =>
            listener({ workspaceId, sessionIds, state }),
          );
        };
        emit('deleting');
        showToast(t('session.delete.pending'), 'info');
        void request(
          JSON.stringify({ workspaceId, sessionId: session.id, sessionIds }),
        )
          .then(() => {
            emit('deleted');
            showToast(t('session.delete.success'), 'info');
          })
          .catch(() => {
            emit('failed');
            showToast(t('session.delete.failed'));
          });
      },
    },
  ]);
}

export async function setArchived(
  workspaceId: string,
  session: Session,
  archived: boolean,
) {
  try {
    await archiveSession(
      JSON.stringify({ workspaceId, sessionId: session.id, archived }),
    );
    showToast(
      t(archived ? 'session.toast.archived' : 'session.toast.unarchived'),
    );
  } catch {
    showToast(
      t(
        archived
          ? 'session.toast.archiveFailed'
          : 'session.toast.unarchiveFailed',
      ),
    );
  }
}

export async function setPinned(
  workspaceId: string,
  session: Session,
  pinned: boolean,
) {
  try {
    await pinSession(
      JSON.stringify({ workspaceId, sessionId: session.id, pinned }),
    );
  } catch {
    showToast(
      t(pinned ? 'session.toast.pinFailed' : 'session.toast.unpinFailed'),
    );
  }
}

export async function setTitle(
  workspaceId: string,
  session: Session,
  title: string,
) {
  const next = title.trim().slice(0, 200);
  if (!next) return;
  try {
    await renameSession(
      JSON.stringify({ workspaceId, sessionId: session.id, title: next }),
    );
  } catch {
    showToast(t('session.toast.renameFailed'));
  }
}

function promptRename(workspaceId: string, session: Session) {
  Alert.prompt(
    t('session.action.rename'),
    undefined,
    [
      { text: t('common.cancel'), style: 'cancel' },
      {
        text: t('session.action.rename'),
        onPress: (value?: string) => {
          void setTitle(workspaceId, session, value ?? '');
        },
      },
    ],
    'plain-text',
    session.title,
  );
}

export async function setRead(workspaceId: string, session: Session) {
  if (
    session.lastMessageAt === undefined ||
    (session.lastReadAt !== undefined &&
      session.lastReadAt >= session.lastMessageAt)
  )
    return;
  const lastReadAt = Math.max(Date.now(), session.lastMessageAt);
  try {
    await markSessionRead(
      JSON.stringify({ workspaceId, sessionId: session.id, lastReadAt }),
    );
  } catch {
    showToast(t('session.toast.readFailed'));
  }
}

export function shareSession(
  workspace: { id: string; slug: string | null },
  sessionId: string,
) {
  void requestShareSession(workspace.id, sessionId).catch(() => {
    showToast(t('session.toast.shareFailed'));
  });
}

export function sessionRowAction(
  workspaceId: string,
  catalog: Catalog,
  sessionId: string,
  actionId: string,
  deleteRequest = deleteSession,
) {
  const session = catalog.sessions.find((s) => s.id === sessionId);
  if (!session) return;
  if (actionId === 'delete')
    confirmSessionDeletion(workspaceId, session, catalog, deleteRequest);
  if (actionId === 'archive')
    void setArchived(workspaceId, session, !session.archived);
  if (actionId === 'pin') void setPinned(workspaceId, session, !session.pinned);
  if (actionId === 'read') void setRead(workspaceId, session);
  if (actionId === 'rename') promptRename(workspaceId, session);
}

export function listRowAction(
  workspace: { id: string; slug: string | null },
  catalog: Catalog,
  id: string,
  actionId: string,
  deleteRequest = deleteSession,
) {
  if (actionId === 'copyPath') return;
  if (actionId === 'open') {
    const projectId = projectIdOfRow(id);
    openCatalogRow(projectId ? `project:${projectId}` : id, catalog);
    return;
  }
  if (actionId === 'newChat') {
    void requestNewSession(workspace.id, catalog, undefined, 'chat');
    return;
  }
  if (actionId === 'newSession') {
    const projectId = projectIdOfRow(id);
    const session = catalog.sessions.find((item) => item.id === id);
    if (session && isChatSession(session)) {
      void requestNewSession(workspace.id, catalog, undefined);
      return;
    }
    void requestNewSession(
      workspace.id,
      catalog,
      projectId ?? session?.projectId,
    );
    return;
  }
  if (actionId === 'share') {
    shareSession(workspace, id);
    return;
  }
  sessionRowAction(workspace.id, catalog, id, actionId, deleteRequest);
}
