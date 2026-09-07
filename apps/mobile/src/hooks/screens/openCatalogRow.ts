import { router } from 'expo-router';
import type { Catalog } from '@/models/catalog';
import { requestOpenSession } from '@/features/sessions/sessionNav';

export function openCatalogRow(id: string, catalog: Catalog) {
  if (id.startsWith('project:')) {
    router.push({
      pathname: '/project/[projectId]',
      params: { projectId: id.slice(8) },
    });
    return;
  }
  const session = catalog.sessions.find((s) => s.id === id);
  if (session) void requestOpenSession(session);
}
