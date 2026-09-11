import { useEffect, useMemo, useRef, useState } from 'react';
import {
  githubRepositories,
  NativeGroupedList,
  type NativeListRow,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import type { Project } from '@/models/catalog';
import { githubProject } from '@/cloud/catalog/model';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/lib/theme/palette';
import { DirectoryScreen } from './DirectoryScreen';
import { t } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';

type Params = { workspaceId: string; projects: Project[]; selectedId: string };
function View() {
  const { params, finish, present } = usePageRuntime<Params, Project>();
  const colors = usePalette();
  const { catalog } = useCatalog();
  const opening = useRef(false);
  const [repositories, setRepositories] = useState<Project[]>();
  const [failed, setFailed] = useState(false);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let active = true;
    setFailed(false);
    void githubRepositories(params.workspaceId)
      .then((names) => {
        if (!active) return;
        setRepositories(
          names.flatMap((name) => {
            const project = githubProject(name);
            return project ? [project] : [];
          }),
        );
      })
      .catch(() => {
        if (active) setFailed(true);
      });
    return () => {
      active = false;
    };
  }, [params.workspaceId, revision]);
  const local = params.projects.filter(
    (project) => !project.id.startsWith('github:'),
  );
  const github =
    repositories ??
    params.projects.filter((project) => project.id.startsWith('github:'));
  const projects = [...local, ...github];
  const row = (project: Project): NativeListRow => ({
    id: project.id,
    title: project.name,
    subtitle: [
      catalog.machineNames?.[project.machineId] ?? project.machineId,
      project.rootPath,
    ]
      .filter(Boolean)
      .join(' · '),
    subtitleMono: !!project.rootPath,
    image: project.id.startsWith('github:') ? undefined : 'folder',
    imageAsset: project.id.startsWith('github:')
      ? 'lody-mark-github'
      : undefined,
    selected: project.id === params.selectedId,
    action: true,
  });
  const githubRows = github.map(row);
  if (!repositories) {
    githubRows.push({
      id: 'github-retry',
      title: failed ? t('projectPicker.githubFailed') : t('common.reading'),
      image: failed ? 'arrow.clockwise' : undefined,
      action: failed,
    });
  } else if (!github.length) {
    githubRows.push({
      id: 'github-empty',
      title: t('projectPicker.githubEmpty'),
    });
  }
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
            const result = await present(DirectoryScreen, {
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
          id: 'github',
          header: t('projectPicker.github'),
          footer:
            repositories?.length === 0
              ? t('projectPicker.githubHint')
              : undefined,
          rows: githubRows,
        },
        {
          id: 'local',
          header: t('projectPicker.local'),
          rows: local.map(row),
        },
      ]}
      onRowPress={({ nativeEvent }) => {
        if (nativeEvent.id === 'github-retry') {
          setRevision((value) => value + 1);
          return;
        }
        const project = projects.find((p) => p.id === nativeEvent.id);
        if (project) finish(project);
      }}
    />
  );
}
export const ProjectPickerScreen = definePage<Params, Project>({
  id: 'project-picker',
  title: t('create.row.selectProject'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from the new session screen');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
