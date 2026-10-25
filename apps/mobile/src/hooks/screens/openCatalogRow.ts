import { openRoute } from '@/lib/presentation/appNavigation';
import type { Catalog } from '@lody/cloud-runtime/models/catalog';
import { requestOpenSession } from '@/features/sessions/sessionNav';

export function openCatalogRow(
  id: string,
  catalog: Catalog,
  findQuery?: string,
) {
  if (id.startsWith('project:')) {
    const projectId = id.slice(8);
    openRoute(
      { pathname: '/project/[projectId]', params: { projectId } },
      { projectId },
    );
    return;
  }
  const session = catalog.sessions.find((s) => s.id === id);
  if (session) void requestOpenSession(session, findQuery);
}
