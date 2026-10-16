import type { NativeListSection } from '@lody-ios/kit';
import type { Catalog } from '@lody/cloud-runtime/models/catalog';
import { t } from '../../lib/i18n/index.ts';
import {
  type VisibilitySnapshot,
  type VisibilityRow,
  type VisibilityRequest,
  type VisibilityService,
} from '../../models/project-visibility.ts';
export type {
  VisibilitySnapshot,
  VisibilityRow,
  VisibilityRequest,
  VisibilityService,
} from '../../models/project-visibility.ts';
export const visibilityId = (
  row: Pick<VisibilityRow, 'machineId' | 'localProjectId'>,
) =>
  `visibility:${encodeURIComponent(row.machineId)}:${encodeURIComponent(row.localProjectId)}`;
export function visibilitySections(
  snapshot: VisibilitySnapshot | undefined,
  catalog: Catalog,
  enabled: boolean,
): NativeListSection[] {
  const groups = new Map<string, NativeListSection>();
  const section = (machine: string) => {
    let group = groups.get(machine);
    if (!group) {
      group = {
        id: machine,
        header: catalog.machineNames?.[machine] || machine,
        footer: machine,
        rows: [],
      };
      groups.set(machine, group);
    }
    return group;
  };
  for (const row of snapshot?.rows ?? []) {
    const project = catalog.projects.find(
      (item) => item.id === `${row.machineId}:local:${row.localProjectId}`,
    );
    const owned = row.ownerUserId === snapshot?.userId;
    section(row.machineId).rows.push({
      id: visibilityId(row),
      title: project?.name || row.localProjectId,
      subtitle: [
        project?.rootPath,
        owned ? undefined : t('settings.projects.readonly'),
      ]
        .filter(Boolean)
        .join('\n'),
      wrapSubtitle: true,
      accessibilityValue: t(
        row.sharedWithTeam
          ? 'settings.projects.sharedValue'
          : 'settings.projects.private',
      ),
      value: t(
        row.sharedWithTeam
          ? 'settings.projects.sharedValue'
          : 'settings.projects.private',
      ),
      action: owned && enabled,
      options: owned
        ? [
            {
              id: 'shared',
              title: t('settings.projects.shared'),
              selected: row.sharedWithTeam,
            },
            {
              id: 'private',
              title: t('settings.projects.private'),
              selected: !row.sharedWithTeam,
            },
          ]
        : undefined,
    });
  }
  for (const project of catalog.projects) {
    const prefix = `${project.machineId}:local:`;
    if (!project.id.startsWith(prefix)) continue;
    const id = project.id.slice(prefix.length);
    if (
      snapshot?.rows.some(
        (row) =>
          row.machineId === project.machineId && row.localProjectId === id,
      )
    )
      continue;
    section(project.machineId).rows.push({
      id: `unknown:${project.id}`,
      title: project.name,
      subtitle: project.rootPath,
      value: t('settings.projects.unknown'),
      accessibilityValue: t('settings.projects.unknown'),
    });
  }
  return [...groups.values()];
}
