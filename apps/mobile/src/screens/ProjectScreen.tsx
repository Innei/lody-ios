import { Stack } from 'expo-router';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import {
  useProjectModel,
  type ProjectModel,
} from '@/features/sessions/useProjectModel';
import { isChatProjectId } from '@/features/sessions/inbox';
import { openCatalogRow } from '@/hooks/screens/openCatalogRow';
import { t } from '@/lib/i18n';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

function ProjectList({ model }: { model: ProjectModel }) {
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={model.colors.accent}
      contentStyle
      sections={model.sections}
      placeholder={model.placeholder}
      previewUserId={model.account?.user.id}
      previewWorkspaceId={model.selected?.id}
      onRowPress={({ nativeEvent: { id } }) =>
        openCatalogRow(id, model.catalog)
      }
      onRowAction={({ nativeEvent: { id, actionId } }) =>
        model.rowAction(id, actionId)
      }
    />
  );
}

function View() {
  const {
    params: { projectId },
  } = usePageRuntime<{ projectId: string }>();
  const model = useProjectModel(projectId);
  return (
    <>
      <Stack.Screen
        options={{
          title: model.project?.name ?? t('project.title'),
          headerLargeTitle: false,
        }}
      />
      {model.project && !isChatProjectId(model.project.id) ? (
        <Stack.Toolbar placement="right">
          <Stack.Toolbar.Button
            icon="plus"
            accessibilityLabel={t('project.newSession.accessibility')}
            onPress={model.newSession}
          />
        </Stack.Toolbar>
      ) : null}
      <ProjectList model={model} />
    </>
  );
}
export const ProjectScreen = definePage<{ projectId: string }>({
  id: 'project',
  title: t('project.title'),
  Component: View,
  parseRouteParams: ({ projectId }) => ({
    projectId: (Array.isArray(projectId) ? projectId[0] : projectId) ?? '',
  }),
  presentation: { style: 'push', headerVariant: 'transparent' },
});
