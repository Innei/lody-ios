import { archiveSession, pinSession } from '@lody-ios/kit';
import { showToast } from '../../ui/toast.ts';
import type { Catalog, Session } from '../../models/catalog.ts';
import { t } from '../../lib/i18n/index.ts';
import { openCatalogRow } from '../../hooks/screens/openCatalogRow.ts';
import { requestNewSession } from './sessionNav.ts';
import { projectIdOfRow } from './inbox.ts';

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
}

export function listRowAction(
  workspaceId: string,
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
  if (actionId === 'newSession') {
    const projectId = projectIdOfRow(id);
    const session = catalog.sessions.find((item) => item.id === id);
    void requestNewSession(
      workspaceId,
      catalog,
      projectId ?? session?.projectId,
    );
    return;
  }
  sessionRowAction(workspaceId, catalog, id, actionId);
}
