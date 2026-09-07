import { archiveSession, pinSession } from '@lody-ios/kit';
import { showToast } from '../../ui/toast.ts';
import type { Catalog, Session } from '../../models/catalog.ts';
import { t } from '../../i18n/index.ts';

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
