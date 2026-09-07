import { useMemo, useRef } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { useSheetHeader } from '@/presentation/SheetStack';
import type { Project } from '@/models/catalog';
import { usePalette } from '@/theme/palette';
import { directoryPage } from './DirectoryScreen';
import { t } from '../../i18n/index.ts';

type Params = { workspaceId: string; projects: Project[]; selectedId: string };
function ProjectPickerScreen() {
  const { params, finish, present } = usePageRuntime<Params, Project>();
  const colors = usePalette();
  const opening = useRef(false);
  const items = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'folder.badge.plus' },
        accessibilityLabel: t('projectPicker.browse.accessibility'),
        onPress: async () => {
          if (opening.current) return;
          opening.current = true;
          try {
            const result = await present(directoryPage, {
              workspaceId: params.workspaceId,
              browserId: `${Date.now()}-${Math.random()}`,
            });
            if (result.status === 'completed') finish(result.value);
          } finally {
            opening.current = false;
          }
        },
      },
    ],
    [params.workspaceId, present, finish],
  );
  useSheetHeader(items);
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      transparent
      accent={colors.accent}
      placeholder={t('projectPicker.empty')}
      sections={[
        {
          id: 'projects',
          rows: params.projects.map((p) => ({
            id: p.id,
            title: p.name,
            subtitle: p.rootPath || t('project.cloud'),
            subtitleMono: !!p.rootPath,
            image: p.id === params.selectedId ? 'checkmark' : undefined,
            action: true,
          })),
        },
      ]}
      onRowPress={({ nativeEvent }) => {
        const project = params.projects.find((p) => p.id === nativeEvent.id);
        if (project) finish(project);
      }}
    />
  );
}
export const projectPickerPage = definePage<Params, Project>({
  id: 'project-picker',
  title: t('create.row.selectProject'),
  Component: ProjectPickerScreen,
  parseRouteParams: () => {
    throw new Error('请从新建会话打开');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
