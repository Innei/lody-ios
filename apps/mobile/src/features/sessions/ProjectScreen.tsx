import { Stack } from 'expo-router';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { useCatalog } from '@/cloud/CatalogProvider';
import { usePalette } from '@/theme/palette';
import { byActivity, sessionRow } from './inbox';
import { newSession, openCatalogRow, sessionRowAction } from './navigation';

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
      header: archived ? '已归档' : undefined,
      rows: sessions
        .filter((s) => s.archived === archived)
        .map((s) => sessionRow(s, colors.accent)),
    }))
    .filter((section) => section.rows.length);
  let placeholder = '还没有会话，点右上角开始';
  if (loading) placeholder = '正在载入…';
  else if (!connected) placeholder = '连接已中断，下拉重新同步';
  return (
    <>
      <Stack.Screen
        options={{ title: project?.name ?? '项目', headerLargeTitle: false }}
      />
      {project && !project.id.endsWith(':unassigned') ? (
        <Stack.Toolbar placement="right">
          <Stack.Toolbar.Button
            icon="plus"
            accessibilityLabel="在此项目新建会话"
            onPress={() => {
              if (selected) void newSession(selected.id, catalog, projectId);
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
  title: '项目',
  Component: ProjectScreen,
  parseRouteParams: ({ projectId }) => ({
    projectId: (Array.isArray(projectId) ? projectId[0] : projectId) ?? '',
  }),
  presentation: { style: 'push', headerVariant: 'transparent' },
});
