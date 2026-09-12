import { useEffect } from 'react';
import { Stack } from 'expo-router';
import { NativeGroupedList } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { activeSessionSections } from '@/features/sessions/inbox';
import { openCatalogRow } from '@/hooks/screens/openCatalogRow';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';

type Params = { workspaceId: string; userId: string };

function Activity() {
  const { params } = usePageRuntime<Params>();
  const { account, localReady } = useAuth();
  const { catalog, selected, setWorkspaceId, loading, connected } =
    useCatalog();
  const colors = usePalette();
  const allowed =
    account?.user.id === params.userId &&
    account?.workspaces.some(
      (workspace) => workspace.id === params.workspaceId,
    );
  useEffect(() => {
    if (allowed && selected?.id !== params.workspaceId)
      setWorkspaceId(params.workspaceId);
  }, [allowed, params.workspaceId, selected?.id, setWorkspaceId]);
  const ready = allowed && selected?.id === params.workspaceId;
  const activeCatalog = { ...catalog, sessions: ready ? catalog.sessions : [] };
  let placeholder = t('native.liveActivity.empty');
  if (!localReady || (allowed && (!ready || loading)))
    placeholder = t('common.loading');
  else if (!allowed) placeholder = t('notifications.route.wrongAccount');
  else if (!connected) placeholder = t('project.offline');
  return (
    <>
      <Stack.Screen
        options={{
          title: t('inbox.settings.view.activity'),
          headerLargeTitle: false,
        }}
      />
      <NativeGroupedList
        style={{ flex: 1 }}
        contentStyle
        accent={colors.accent}
        sections={activeSessionSections(activeCatalog, colors.accent)}
        placeholder={placeholder}
        onRowPress={({ nativeEvent }) =>
          openCatalogRow(nativeEvent.id, activeCatalog)
        }
      />
    </>
  );
}

export const ActivityScreen = definePage<Params>({
  id: 'activity',
  title: t('inbox.settings.view.activity'),
  Component: Activity,
  parseRouteParams: ({ workspaceId, userId }) => ({
    workspaceId:
      (Array.isArray(workspaceId) ? workspaceId[0] : workspaceId) ?? '',
    userId: (Array.isArray(userId) ? userId[0] : userId) ?? '',
  }),
  presentation: { style: 'push', headerVariant: 'transparent' },
});
