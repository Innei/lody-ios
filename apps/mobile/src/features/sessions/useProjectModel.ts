import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { useSessionListCatalog } from './useSessionListCatalog';
import { byActivity, sessionRow } from './inbox';
import { requestNewSession } from './sessionNav';
import { listRowAction } from './sessionActions';

export function useProjectModel(projectId: string) {
  const { catalog: sourceCatalog, selected, loading, connected } = useCatalog();
  const { account } = useAuth();
  const catalog = useSessionListCatalog(
    sourceCatalog,
    account?.user.id ?? '',
    selected?.id ?? '',
  );
  const colors = usePalette();
  const project = catalog.projects.find((p) => p.id === projectId);
  const sessions = catalog.sessions
    .filter((s) => s.projectId === projectId)
    .sort(byActivity);
  const sections = [false, true]
    .map((archived) => ({
      id: archived ? 'archived' : 'sessions',
      header: archived ? t('session.state.archived') : undefined,
      rows: sessions
        .filter((s) => s.archived === archived)
        .map((s) => sessionRow(s, colors.accent)),
    }))
    .filter((section) => section.rows.length);
  let placeholder = t('project.empty');
  if (loading) placeholder = t('common.loading');
  else if (!connected) placeholder = t('project.offline');
  return {
    account,
    catalog,
    colors,
    newSession: () => {
      if (selected) void requestNewSession(selected.id, catalog, projectId);
    },
    placeholder,
    project,
    sections,
    selected,
    rowAction: (id: string, actionId: string) => {
      if (selected) listRowAction(selected.id, catalog, id, actionId);
    },
  };
}

export type ProjectModel = ReturnType<typeof useProjectModel>;
