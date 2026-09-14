import { archiveSession, pinSession, markSessionRead } from '@lody-ios/kit';
import { Share } from 'react-native';
import { showToast } from '../../ui/toast.ts';
import type { Catalog, Session } from '../../models/catalog.ts';
import { t } from '../../lib/i18n/index.ts';
import { openCatalogRow } from '../../hooks/screens/openCatalogRow.ts';
import { requestNewSession } from './sessionNav.ts';
import { isChatSession, projectIdOfRow } from './inbox.ts';
import { sessionShareUrl } from './sessionShare.ts';

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
  const url = sessionShareUrl(workspace, sessionId);
  if (!url) {
    showToast(t('session.toast.shareFailed'));
    return;
  }
  void Share.share({ url }).catch(() => {
    showToast(t('session.toast.shareFailed'));
  });
}

export function sessionRowAction(
  workspaceId: string,
  catalog: Catalog,
  sessionId: string,
  actionId: string,
) {
  const session = catalog.sessions.find((s) => s.id === sessionId);
  if (!session) return;
  if (actionId === 'archive')
    void setArchived(workspaceId, session, !session.archived);
  if (actionId === 'pin') void setPinned(workspaceId, session, !session.pinned);
  if (actionId === 'read') void setRead(workspaceId, session);
}

export function listRowAction(
  workspace: { id: string; slug: string | null },
  catalog: Catalog,
  id: string,
  actionId: string,
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
  sessionRowAction(workspace.id, catalog, id, actionId);
}
