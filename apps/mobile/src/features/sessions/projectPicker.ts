import type { NativeListRow, NativeListSection } from '@lody-ios/kit';
import type { Project } from '../../models/catalog.ts';
import { t } from '../../lib/i18n/index.ts';

export function isGithubProjectId(id: string) {
  return id.startsWith('github:');
}

export function projectPickerSegment(selectedId: string) {
  if (isGithubProjectId(selectedId)) return 1;
  return 0;
}

export function projectPickerSegments() {
  return [t('projectPicker.local'), t('projectPicker.github')];
}

export function projectPickerSearchPlaceholder(segment: number) {
  if (segment === 1) return t('projectPicker.searchGithub');
  return t('projectPicker.searchLocal');
}

export function splitPickerProjects(
  projects: Project[],
  repositories?: Project[],
) {
  return {
    local: projects.filter((project) => !isGithubProjectId(project.id)),
    github:
      repositories ??
      projects.filter((project) => isGithubProjectId(project.id)),
  };
}

export function filterPickerProjects(projects: Project[], query: string) {
  const term = query.trim().toLocaleLowerCase();
  if (!term) return projects;
  return projects.filter((project) =>
    [project.name, project.rootPath, project.id]
      .join(' ')
      .toLocaleLowerCase()
      .includes(term),
  );
}

export function githubPickerStatusRows({
  loaded,
  failed,
  empty,
}: {
  loaded: boolean;
  failed: boolean;
  empty: boolean;
}): NativeListRow[] {
  if (!loaded) {
    return [
      {
        id: 'github-retry',
        title: failed ? t('projectPicker.githubFailed') : t('common.reading'),
        image: failed ? 'arrow.clockwise' : undefined,
        action: failed,
      },
    ];
  }
  if (empty) {
    return [{ id: 'github-empty', title: t('projectPicker.githubEmpty') }];
  }
  return [];
}

export function projectPickerSections({
  segment,
  localRows,
  githubRows,
  githubEmpty,
}: {
  segment: number;
  localRows: NativeListRow[];
  githubRows: NativeListRow[];
  githubEmpty: boolean;
}): NativeListSection[] {
  if (segment === 1) {
    return [
      {
        id: 'github',
        footer: githubEmpty ? t('projectPicker.githubHint') : undefined,
        rows: githubRows,
      },
    ];
  }
  return [{ id: 'local', rows: localRows }];
}
