import type { NativeListSection } from '@lody-ios/kit';
import type { Catalog } from '@lody/cloud-runtime/models/catalog';
import {
  machineState,
  unknownPresence,
  type MachinePresence,
} from '@lody/cloud-runtime/models/machines';
import type {
  RemoteSetting,
  SettingsRequest,
} from '@lody/cloud-runtime/models/settings';
import { relativeTime } from '../../ui/time.ts';
import { t } from '../../lib/i18n/index.ts';
import { agentUsageRows } from './agent-usage.ts';

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

export function remoteSettingsPlaceholder({
  items,
  loading,
  error,
}: {
  items: RemoteSetting[];
  loading: boolean;
  error: string;
}) {
  if (items.length) return '';
  if (error) return '';
  if (loading) return t('settings.remote.loading');
  return t('settings.remote.empty');
}

function settingValue(item: RemoteSetting) {
  if (item.kind !== 'mcp') return undefined;
  return t(
    item.enabledByDefault
      ? 'settings.remote.enabled'
      : 'settings.remote.disabled',
  );
}

function joinFooter(...parts: (string | undefined)[]) {
  return parts.filter(Boolean).join('\n') || undefined;
}

export function remoteSettingsSections({
  kind,
  items,
  error,
  connected,
  agentUsage,
  machinePresence = unknownPresence,
  syncedAt,
  now,
}: {
  kind: RemoteSetting['kind'];
  items: RemoteSetting[];
  loading?: boolean;
  error: string;
  connected: boolean;
  agentUsage?: Catalog['agentUsage'];
  machinePresence?: MachinePresence;
  syncedAt?: number;
  now?: number;
}): NativeListSection[] {
  const synced =
    syncedAt === undefined
      ? undefined
      : t('settings.remote.syncedAt', { time: relativeTime(syncedAt, now) });
  const presence = connected && !error ? machinePresence : unknownPresence;
  const settingRows = items.map((item) => ({
    id: remoteSettingId(item),
    title: item.name || item.id,
    subtitle: [
      kind === 'machine'
        ? [item.detail, t(`devices.${machineState(presence, item.id)}`)]
            .filter(Boolean)
            .join(' · ')
        : item.detail,
      kind === 'machine' ? item.id : undefined,
      kind === 'agent' ? undefined : item.machineName,
      item.readOnly ? t('settings.remote.readOnly') : undefined,
    ]
      .filter(Boolean)
      .join(kind === 'machine' ? '\n' : ' · '),
    wrapSubtitle: kind !== 'mcp',
    value: settingValue(item),
    disclosure: !item.readOnly,
    action: !item.readOnly,
  }));
  const content: NativeListSection[] = [];
  if (kind === 'agent') {
    const groups = new Map<
      string,
      {
        settings: NativeListSection;
        usage: NativeListSection;
        providers: Set<string>;
      }
    >();
    for (const [index, item] of items.entries()) {
      const machine = item.machineId ?? item.machineName ?? '';
      let group = groups.get(machine);
      if (!group) {
        const name =
          item.machineName || item.machineId || t('settings.remote.machine');
        const identity = item.machineId
          ? t('settings.remote.machineIdentity', { id: item.machineId })
          : undefined;
        let usageFooter = t('settings.usage.cached');
        if (!connected) usageFooter = t('settings.usage.offline');
        else if (machineState(presence, machine) === 'online')
          usageFooter = t('settings.usage.shared');
        group = {
          settings: {
            id: `machine:${machine}`,
            header: name,
            footer: joinFooter(
              identity,
              t('settings.remote.agentSource'),
              !connected || error
                ? t('settings.remote.agentCached')
                : undefined,
              synced,
            ),
            rows: [],
          },
          usage: {
            id: `machine:${machine}:usage`,
            header: t('settings.usage.machineTitle', { name }),
            footer: joinFooter(identity, usageFooter),
            rows: [],
          },
          providers: new Set(),
        };
        groups.set(machine, group);
      }
      group.settings.rows.push(settingRows[index]!);
      const reported = agentUsage?.[item.machineId ?? ''];
      const config = reported?.configs.find((config) => config.id === item.id);
      if (!config?.eligible || group.providers.has(config.provider)) continue;
      const rows = agentUsageRows(item, reported);
      if (!rows.length) continue;
      group.providers.add(config.provider);
      group.usage.rows.push(...rows);
    }
    for (const [machine, group] of groups) {
      if (!group.usage.rows.length)
        group.usage.rows.push({
          id: `usage:${machine}:unavailable`,
          title: t('settings.usage.empty'),
          subtitle: t('settings.usage.supported'),
          wrapSubtitle: true,
        });
      content.push(group.settings, group.usage);
    }
    if (!groups.size && synced)
      content.push({
        id: 'settings',
        footer: joinFooter(
          !connected || error ? t('settings.remote.agentCached') : undefined,
          synced,
        ),
        rows: [],
      });
  } else if (items.length || synced || !error) {
    content.push({
      id: 'settings',
      footer: joinFooter(
        error ? undefined : t(`settings.remote.${kind}Hint`),
        kind === 'machine' ? t('settings.remote.machineOwnerHint') : undefined,
        kind === 'machine' && items.length && (!connected || error)
          ? t('settings.remote.machineCached')
          : undefined,
        synced,
      ),
      rows: settingRows,
    });
  }
  if (!error) return content;
  return [
    ...content,
    {
      id: 'error',
      footer: error,
      rows: [
        {
          id: 'retry',
          title: t('settings.remote.retry'),
          action: true,
          image: 'arrow.clockwise',
        },
      ],
    },
  ];
}
