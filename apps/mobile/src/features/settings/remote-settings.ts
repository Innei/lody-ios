import type { NativeListSection } from '@lody-ios/kit';
import type { Catalog } from '../../models/catalog.ts';
import type { RemoteSetting, SettingsRequest } from '../../models/settings.ts';
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
  syncedAt,
  now,
}: {
  kind: RemoteSetting['kind'];
  items: RemoteSetting[];
  loading?: boolean;
  error: string;
  connected: boolean;
  agentUsage?: Catalog['agentUsage'];
  syncedAt?: number;
  now?: number;
}): NativeListSection[] {
  const synced =
    syncedAt === undefined
      ? undefined
      : t('settings.remote.syncedAt', { time: relativeTime(syncedAt, now) });
  const settingRows = items.map((item) => ({
    id: remoteSettingId(item),
    title: item.name || item.id,
    subtitle: [
      item.detail,
      item.machineName,
      item.readOnly ? t('settings.remote.readOnly') : undefined,
    ]
      .filter(Boolean)
      .join(' · '),
    value: settingValue(item),
    disclosure: !item.readOnly,
    action: !item.readOnly,
  }));
  const content: NativeListSection[] = [];
  if (kind === 'agent') {
    for (const [index, item] of items.entries()) {
      const usageRows = agentUsageRows(
        item,
        agentUsage?.[item.machineId ?? ''],
      );
      let usage: string | undefined;
      if (usageRows.length) {
        if (connected) usage = t('settings.usage.shared');
        else usage = t('settings.usage.offline');
      }
      content.push({
        id: remoteSettingId(item),
        rows: [settingRows[index]!, ...usageRows],
        footer: joinFooter(
          usage,
          index === items.length - 1 ? synced : undefined,
        ),
      });
    }
  } else if (items.length || synced || !error) {
    content.push({
      id: 'settings',
      footer: joinFooter(
        error ? undefined : t(`settings.remote.${kind}Hint`),
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
