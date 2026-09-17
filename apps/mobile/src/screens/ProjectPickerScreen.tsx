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
import {
  filterPickerProjects,
  githubPickerStatusRows,
  isGithubProjectId,
  projectPickerSearchPlaceholder,
  projectPickerSegment,
  projectPickerSegments,
  projectPickerSections,
  splitPickerProjects,
} from '@/features/sessions/projectPicker';

type Params = { workspaceId: string; projects: Project[]; selectedId: string };
function View() {
  const { params, finish, present } = usePageRuntime<Params, Project>();
  const colors = usePalette();
  const { catalog } = useCatalog();
  const opening = useRef(false);
  const [repositories, setRepositories] = useState<Project[]>();
  const [failed, setFailed] = useState(false);
  const [revision, setRevision] = useState(0);
  const [segment, setSegment] = useState(() =>
    projectPickerSegment(params.selectedId),
  );
  const [queries, setQueries] = useState(['', '']);
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
  const { local, github } = splitPickerProjects(params.projects, repositories);
  const query = queries[segment] ?? '';
  const searching = query.trim().length > 0;
  const visibleLocal = filterPickerProjects(local, queries[0] ?? '');
  const visibleGithub = filterPickerProjects(github, queries[1] ?? '');
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
    image: isGithubProjectId(project.id) ? undefined : 'folder',
    imageAsset: isGithubProjectId(project.id) ? 'lody-mark-github' : undefined,
    selected: project.id === params.selectedId,
    action: true,
  });
  const githubRows = [
    ...visibleGithub.map(row),
    ...(queries[1]?.trim()
      ? []
      : githubPickerStatusRows({
          loaded: repositories !== undefined,
          failed,
          empty: github.length === 0,
        })),
  ];
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
      placeholder={
        searching ? t('projectPicker.noMatch') : t('projectPicker.empty')
      }
      segments={projectPickerSegments()}
      selectedSegment={segment}
      searchPlaceholder={projectPickerSearchPlaceholder(segment)}
      searchText={query}
      onSegmentChange={({ nativeEvent }) =>
        setSegment(nativeEvent.index === 1 ? 1 : 0)
      }
      onSearchChange={({ nativeEvent }) => {
        const text = nativeEvent.text;
        setQueries((current) => {
          const next = [current[0] ?? '', current[1] ?? ''];
          next[segment] = text;
          return next;
        });
      }}
      sections={projectPickerSections({
        segment,
        localRows: visibleLocal.map(row),
        githubRows,
        githubEmpty:
          !(queries[1] ?? '').trim() &&
          repositories !== undefined &&
          repositories.length === 0,
      })}
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
