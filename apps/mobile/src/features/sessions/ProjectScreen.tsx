import { Stack } from 'expo-router';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/theme/palette';
import { byActivity, sessionRow } from './inbox';
import { requestNewSession } from './sessionNav';
import { sessionRowAction } from './sessionActions';
import { openCatalogRow } from '@/hooks/screens/openCatalogRow';
import { t } from '../../i18n/index.ts';

function ProjectScreen() {
  const {
    params: { projectId },
  } = usePageRuntime<{ projectId: string }>();
  const { catalog, selected, loading, connected, refresh } = useCatalog();
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
  return (
    <>
      <Stack.Screen
        options={{
          title: project?.name ?? t('project.title'),
          headerLargeTitle: false,
        }}
      />
      {project && !project.id.endsWith(':unassigned') ? (
        <Stack.Toolbar placement="right">
          <Stack.Toolbar.Button
            icon="plus"
            accessibilityLabel={t('project.newSession.accessibility')}
            onPress={() => {
              if (selected)
                void requestNewSession(selected.id, catalog, projectId);
            }}
          />
        </Stack.Toolbar>
      ) : null}
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        contentStyle
        sections={sections}
        refreshing={loading}
        onRefresh={refresh}
        placeholder={placeholder}
        onRowPress={({ nativeEvent }) =>
          openCatalogRow(nativeEvent.id, catalog)
        }
        onRowAction={({ nativeEvent: { id, actionId } }) => {
          if (selected) sessionRowAction(selected.id, catalog, id, actionId);
        }}
      />
    </>
  );
}
export const projectPage = definePage<{ projectId: string }>({
  id: 'project',
  title: t('project.title'),
  Component: ProjectScreen,
  parseRouteParams: ({ projectId }) => ({
    projectId: (Array.isArray(projectId) ? projectId[0] : projectId) ?? '',
  }),
  presentation: { style: 'push', headerVariant: 'transparent' },
});
