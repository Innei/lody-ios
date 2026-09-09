import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/lib/theme/palette';
import { byActivity, sessionRow } from '@/features/sessions/inbox';
import { listRowAction } from '@/features/sessions/sessionActions';
import { openCatalogRow } from '@/hooks/screens/openCatalogRow';
import { t } from '../lib/i18n/index.ts';

function View() {
  const { catalog, selected, loading, refresh } = useCatalog();
  const { account } = useAuth();
  const colors = usePalette();
  const names = new Map(catalog.projects.map((p) => [p.id, p.name]));
  const rows = catalog.sessions
    .filter((s) => s.archived)
    .sort(byActivity)
    .map((s) => sessionRow(s, colors.accent, names.get(s.projectId)));
  return (
    <>
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        contentStyle
        sections={rows.length ? [{ id: 'archived', rows }] : []}
        refreshing={loading}
        onRefresh={refresh}
        placeholder={
          loading ? t('common.loading') : t('settings.archived.empty')
        }
        previewUserId={account?.user.id}
        previewWorkspaceId={selected?.id}
        onRowPress={({ nativeEvent }) =>
          openCatalogRow(nativeEvent.id, catalog)
        }
        onRowAction={({ nativeEvent: { id, actionId } }) => {
          if (selected) listRowAction(selected.id, catalog, id, actionId);
        }}
      />
    </>
  );
}

export const ArchivedSessionsScreen = definePage({
  id: 'archived-sessions',
  title: t('settings.archived.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
