import type { NativeListRow, NativeListSection } from '@lody-ios/kit';
import type { Catalog } from '@lody/cloud-runtime/models/catalog';
import {
  machineState,
  unknownPresence,
  type MachinePresence,
  type MachineState,
} from '@lody/cloud-runtime/models/machines';
import type {
  RemoteSetting,
  SettingsRequest,
} from '@lody/cloud-runtime/models/settings';
import { t } from '../../lib/i18n/index.ts';
import { agentIcon } from '../sessions/status.ts';
import { agentUsageRings, type UsageRing } from './agent-usage.ts';

export type SettingsService = (
  request: SettingsRequest,
) => Promise<RemoteSetting[]>;

export type SavedRemoteSettings = {
  items: RemoteSetting[];
  syncedAt: number;
};

export type SettingsListCache = {
  read(
    workspaceId: string,
    kind: RemoteSetting['kind'],
  ): Promise<SavedRemoteSettings | null>;
  write(
    workspaceId: string,
    kind: RemoteSetting['kind'],
    snapshot: SavedRemoteSettings,
  ): void;
};

export const remoteSettingId = (item: RemoteSetting) =>
  `setting:${item.kind}:${item.machineId ?? ''}:${item.id}`;

export const remoteSettingsKey = (
  userId: string,
  workspaceId: string,
  kind: RemoteSetting['kind'],
) => `remote-settings:${userId}:${workspaceId}:${kind}`;

export function parseSavedRemoteSettings(
  saved: unknown,
  kind: RemoteSetting['kind'],
): SavedRemoteSettings | null {
  if (!saved || typeof saved !== 'object') return null;
  const value = saved as SavedRemoteSettings;
  if (!Array.isArray(value.items) || !Number.isFinite(value.syncedAt))
    return null;
  if (
    !value.items.every(
      (item) =>
        item &&
        item.kind === kind &&
        typeof item.id === 'string' &&
        typeof item.name === 'string',
    )
  )
    return null;
  return { items: value.items, syncedAt: value.syncedAt };
}

export function memoryRemoteSettingsCache(): SettingsListCache {
  const db = new Map<string, SavedRemoteSettings>();
  return {
    async read(workspaceId, kind) {
      return db.get(`${workspaceId}:${kind}`) ?? null;
    },
    write(workspaceId, kind, snapshot) {
      db.set(`${workspaceId}:${kind}`, snapshot);
    },
  };
}

export async function loadRemoteSettings({
  workspaceId,
  kind,
  service,
  cache,
  reuse,
  onCached,
  now = Date.now(),
}: {
  workspaceId: string;
  kind: RemoteSetting['kind'];
  service: SettingsService;
  cache?: SettingsListCache;
  reuse?: SavedRemoteSettings | null;
  onCached?: (saved: SavedRemoteSettings) => void;
  now?: number;
}): Promise<{ live?: SavedRemoteSettings; error?: string }> {
  if (!reuse) {
    const saved = parseSavedRemoteSettings(
      await cache?.read(workspaceId, kind),
      kind,
    );
    if (saved) onCached?.(saved);
  }
  try {
    const items = await service({ workspaceId, kind });
    const live = { items, syncedAt: now };
    cache?.write(workspaceId, kind, live);
    return { live };
  } catch (cause) {
    return {
      error:
        cause instanceof Error
          ? cause.message
          : t('settings.remote.loadFailed'),
    };
  }
}

function settingValue(item: RemoteSetting) {
  if (item.kind !== 'mcp') return undefined;
  return t(
    item.enabledByDefault
      ? 'settings.mcp.defaultOn'
      : 'settings.mcp.defaultOff',
  );
}

export function statusHeader(name: string, state: MachineState) {
  if (state === 'unknown') return { header: name };
  return {
    header: `${name} · ${t(`devices.${state}`)}`,
    headerStatus: state,
  };
}

const lock = {
  trailingSymbol: 'lock',
  trailingSymbolLabel: t('settings.remote.ownerOnly'),
};

function machineRows(
  items: RemoteSetting[],
  presence: MachinePresence,
): NativeListRow[] {
  const names = new Map<string, number>();
  for (const item of items)
    names.set(item.name, (names.get(item.name) ?? 0) + 1);
  return items.map((item) => {
    const state = machineState(presence, item.id);
    const duplicate = (names.get(item.name) ?? 0) > 1;
    return {
      id: remoteSettingId(item),
      title: item.name || item.id,
      subtitle: [t(`devices.${state}`), item.detail, duplicate ? item.id : '']
        .filter(Boolean)
        .join(' · '),
      status: state,
      image: 'desktopcomputer',
      disclosure: !item.readOnly,
      action: !item.readOnly,
      ...(item.readOnly ? lock : {}),
    };
  });
}

function mcpRows(items: RemoteSetting[]): NativeListRow[] {
  return items.map((item) => ({
    id: remoteSettingId(item),
    title: item.name || item.id,
    subtitle: [
      item.detail,
      item.machineName,
      item.configured === false ? t('settings.mcp.notConfigured') : undefined,
    ]
      .filter(Boolean)
      .join(' · '),
    wrapSubtitle: true,
    value: settingValue(item),
    disclosure: !item.readOnly,
    action: !item.readOnly,
    ...(item.readOnly ? lock : {}),
  }));
}

function agentFooter(state: MachineState, rings: boolean) {
  if (!rings)
    return state === 'offline' ? t('settings.usage.noneOffline') : undefined;
  if (state === 'online')
    return `${t('settings.usage.paceFooter')}\n${t('settings.usage.sharedShort')}`;
  if (state === 'offline') return t('settings.usage.lastOffline');
  return t('settings.usage.lastUnknown');
}

function agentSections(
  items: RemoteSetting[],
  presence: MachinePresence,
  agentUsage: Catalog['agentUsage'],
): NativeListSection[] {
  const groups = new Map<
    string,
    {
      section: NativeListSection;
      state: MachineState;
      rings: UsageRing[];
      providers: Set<string>;
    }
  >();
  for (const item of items) {
    const machine = item.machineId ?? item.machineName ?? '';
    let group = groups.get(machine);
    if (!group) {
      const state = machineState(presence, machine);
      group = {
        section: {
          id: `machine:${machine}`,
          ...statusHeader(
            item.machineName || item.machineId || t('settings.remote.machine'),
            state,
          ),
          rows: [],
        },
        state,
        rings: [],
        providers: new Set(),
      };
      groups.set(machine, group);
    }
    group.section.rows.push({
      id: remoteSettingId(item),
      title: item.name || item.id,
      image: 'sparkles',
      imageAsset: agentIcon(item.detail),
      disclosure: !item.readOnly,
      action: !item.readOnly,
      ...(item.readOnly ? lock : {}),
    });
    const reported = agentUsage?.[item.machineId ?? ''];
    const config = reported?.configs.find((config) => config.id === item.id);
    if (!config?.eligible || group.providers.has(config.provider)) continue;
    const rings = agentUsageRings(item, reported);
    if (!rings.length) continue;
    group.providers.add(config.provider);
    group.rings.push(...rings);
  }
  return [...groups.values()].map(({ section, state, rings }) => {
    return {
      ...section,
      footer: agentFooter(state, rings.length > 0),
      ...(rings.length
        ? {
            visual: {
              type: 'quotas' as const,
              dimmed: state !== 'online',
              items:
                state === 'online'
                  ? rings
                  : rings.map(
                      ({
                        pace: _pace,
                        detail: _detail,
                        tone: _tone,
                        ...ring
                      }) => ring,
                    ),
            },
          }
        : {}),
    };
  });
}

export function remoteSettingsSections({
  kind,
  items,
  error,
  connected,
  agentUsage,
  machinePresence = unknownPresence,
}: {
  kind: RemoteSetting['kind'];
  items: RemoteSetting[];
  error: string;
  connected: boolean;
  agentUsage?: Catalog['agentUsage'];
  machinePresence?: MachinePresence;
}): NativeListSection[] {
  const presence = connected && !error ? machinePresence : unknownPresence;
  if (kind === 'agent') return agentSections(items, presence, agentUsage);
  if (!items.length) return [];
  if (kind === 'machine')
    return [
      {
        id: 'settings',
        footer: t('settings.remote.machineFooter'),
        rows: machineRows(items, presence),
      },
    ];
  return [
    {
      id: 'settings',
      footer: t('settings.remote.mcpHint'),
      rows: mcpRows(items),
    },
  ];
}
