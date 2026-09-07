import { router } from 'expo-router';
import { archiveSession, pinSession } from '@lody-ios/kit';
import { present } from '@/presentation';
import { showToast } from '@/ui/toast';
import type { Catalog, Session } from '@/cloud/model';
import { sessionPage } from './SessionScreen';
import { createSessionPage } from './CreateSessionScreen';

export async function openSession(session: Session) {
  try {
    await present(sessionPage, { session }, { title: session.title });
  } catch {
    showToast('暂时无法打开会话，请重试。');
  }
}
export async function newSession(
  workspaceId: string,
  catalog: Catalog,
  projectId?: string,
) {
  try {
    const result = await present(createSessionPage, {
      workspaceId,
      projects: catalog.projects,
      projectId,
    });
    if (result.status === 'completed')
      await present(
        sessionPage,
        {
          session: result.value.session,
          modelId: result.value.modelId,
          effort: result.value.effort,
          modeId: result.value.modeId,
        },
        { title: result.value.session.title },
      );
  } catch {
    showToast('暂时无法新建会话，请重试。');
  }
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
    showToast(archived ? '已归档' : '已取消归档');
  } catch {
    showToast(
      archived ? '暂时无法归档，请重试。' : '暂时无法取消归档，请重试。',
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
    showToast(pinned ? '暂时无法置顶，请重试。' : '暂时无法取消置顶，请重试。');
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
export function openCatalogRow(id: string, catalog: Catalog) {
  if (id.startsWith('project:')) {
    router.push({
      pathname: '/project/[projectId]',
      params: { projectId: id.slice(8) },
    });
    return;
  }
  const session = catalog.sessions.find((s) => s.id === id);
  if (session) void openSession(session);
}
