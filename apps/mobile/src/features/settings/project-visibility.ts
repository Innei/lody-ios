import type { NativeListSection } from '@lody-ios/kit';
import {
  machineState,
  unknownPresence,
  type MachinePresence,
} from '@lody/cloud-runtime/models/machines';
import type { Catalog } from '@lody/cloud-runtime/models/catalog';
import { t } from '../../lib/i18n/index.ts';
import { statusHeader } from './remote-settings.ts';
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
const sharedSymbol = (shared: boolean) => (shared ? 'person.2' : 'lock');

export function visibilitySections(
  snapshot: VisibilitySnapshot | undefined,
  catalog: Catalog,
  enabled: boolean,
  presence: MachinePresence = unknownPresence,
): NativeListSection[] {
  const groups = new Map<string, NativeListSection>();
  const section = (machine: string) => {
    let group = groups.get(machine);
    if (!group) {
      group = {
        id: machine,
        ...statusHeader(
          catalog.machineNames?.[machine] || machine,
          machineState(presence, machine),
        ),
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
    const value = t(
      row.sharedWithTeam
        ? 'settings.projects.sharedValue'
        : 'settings.projects.private',
    );
    section(row.machineId).rows.push({
      id: visibilityId(row),
      title: project?.name || row.localProjectId,
      subtitle: owned ? project?.rootPath : t('settings.projects.othersOwner'),
      subtitleMono: owned,
      image: 'folder',
      accessibilityValue: value,
      value,
      valueSymbol: sharedSymbol(row.sharedWithTeam),
      action: owned && enabled,
      options: owned
        ? [
            {
              id: 'shared',
              title: t('settings.projects.shared'),
              symbol: sharedSymbol(true),
              selected: row.sharedWithTeam,
            },
            {
              id: 'private',
              title: t('settings.projects.private'),
              symbol: sharedSymbol(false),
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
      subtitleMono: true,
      image: 'folder',
      value: t('settings.projects.unknownShort'),
      valueSymbol: 'questionmark.circle',
      accessibilityValue: t('settings.projects.unknown'),
    });
  }
  return [...groups.values()];
}
