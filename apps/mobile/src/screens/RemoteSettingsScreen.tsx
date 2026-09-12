import { useEffect, useMemo, useRef, useState } from 'react';
import { NativeGroupedList, NativeSymbolButton } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { requestSettings } from '@/cloud/settings';
import { readLocal, writeLocal } from '@/cloud/kv';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePalette } from '@/lib/theme/palette';
import type { RemoteSetting } from '@/models/settings';
import { t } from '../lib/i18n/index.ts';
import {
  loadRemoteSettings,
  parseSavedRemoteSettings,
  remoteSettingId,
  remoteSettingsKey,
  remoteSettingsPlaceholder,
  remoteSettingsSections,
  type SavedRemoteSettings,
  type SettingsListCache,
  type SettingsService,
} from '@/features/settings/remote-settings';
import type { Catalog } from '@/models/catalog';
import { RemoteSettingEditorScreen } from './RemoteSettingEditorScreen';

export type { SettingsService };
type Params = { kind: RemoteSetting['kind'] };
export const settingsTitle = (kind: RemoteSetting['kind']) =>
  t(`settings.remote.${kind}`);

function localRemoteSettingsCache(userId: string): SettingsListCache {
  return {
    async read(workspaceId, kind) {
      return parseSavedRemoteSettings(
        await readLocal<SavedRemoteSettings>(
          remoteSettingsKey(userId, workspaceId, kind),
        ),
        kind,
      );
    },
    write(workspaceId, kind, snapshot) {
      void writeLocal(remoteSettingsKey(userId, workspaceId, kind), snapshot);
    },
  };
}

export function RemoteSettingsView({
  kind,
  workspaceId,
  service = requestSettings,
  agentUsage,
  connected = true,
  refreshUsage,
  cache,
}: Params & {
  workspaceId: string;
  service?: SettingsService;
  agentUsage?: Catalog['agentUsage'];
  connected?: boolean;
  refreshUsage?: () => void;
  cache?: SettingsListCache;
}) {
  const colors = usePalette();
  const { present } = usePageRuntime();
  const [items, setItems] = useState<RemoteSetting[]>([]);
  const [syncedAt, setSyncedAt] = useState<number>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const requestId = useRef(0);
  const scope = `${workspaceId}:${kind}`;
  const scopeRef = useRef(scope);
  const snapshotRef = useRef<SavedRemoteSettings | null>(null);
  snapshotRef.current =
    items.length && syncedAt !== undefined ? { items, syncedAt } : null;

  function apply(saved: SavedRemoteSettings) {
    snapshotRef.current = saved;
    setItems(saved.items);
    setSyncedAt(saved.syncedAt);
  }

  function refresh(reuse: SavedRemoteSettings | null) {
    const id = ++requestId.current;
    setLoading(true);
    setError('');
    void loadRemoteSettings({
      workspaceId,
      kind,
      service,
      cache,
      reuse,
      onCached: (saved) => {
        if (id === requestId.current) apply(saved);
      },
    }).then((result) => {
      if (id !== requestId.current) return;
      if (result.live) apply(result.live);
      setError(result.error ?? '');
      setLoading(false);
    });
  }

  useEffect(() => {
    const switched = scopeRef.current !== scope;
    scopeRef.current = scope;
    if (switched) {
      snapshotRef.current = null;
      setItems([]);
      setSyncedAt(undefined);
    }
    refresh(switched ? null : snapshotRef.current);
    return () => {
      requestId.current++;
    };
  }, [scope, service, cache]);

  const headerRefresh = useMemo(
    () => (
      <NativeSymbolButton
        accessibilityName={
          loading ? t('settings.remote.loading') : t('settings.remote.refresh')
        }
        symbol="arrow.clockwise"
        tint="blue"
        loading={loading}
        style={{ width: 44, height: 44 }}
        onPress={() => {
          refreshUsage?.();
          refresh(snapshotRef.current);
        }}
      />
    ),
    [loading, refreshUsage],
  );
  useSheetHeader(undefined, undefined, headerRefresh);

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      refreshing={loading}
      onRefresh={() => {
        refreshUsage?.();
        refresh(snapshotRef.current);
      }}
      placeholder={remoteSettingsPlaceholder({ items, loading, error })}
      sections={remoteSettingsSections({
        kind,
        items,
        loading,
        error,
        connected,
        agentUsage,
        syncedAt,
      })}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'retry') {
          refresh(snapshotRef.current);
          return;
        }
        const item = items.find((item) => remoteSettingId(item) === id);
        if (!item || item.readOnly) return;
        void present(
          RemoteSettingEditorScreen,
          {
            item,
            workspaceId,
            service,
          },
          {
            title: t(`settings.remote.edit${kind}`),
            sheetAllowedDetents: kind === 'agent' ? [1] : [0.5, 1],
            sheetGrabberVisible: kind !== 'agent',
          },
        ).then((result) => {
          if (result.status === 'completed') refresh(snapshotRef.current);
        });
      }}
    />
  );
}

function View() {
  const { params, cancel } = usePageRuntime<Params>();
  const { account } = useAuth();
  const { selected, catalog, connected, refresh } = useCatalog();
  const userId = account?.user.id;
  const cache = useMemo(
    () => (userId ? localRemoteSettingsCache(userId) : undefined),
    [userId],
  );
  useEffect(() => {
    if (!selected) cancel();
  }, [selected, cancel]);
  if (!selected) return null;
  return (
    <RemoteSettingsView
      key={selected.id}
      kind={params.kind}
      workspaceId={selected.id}
      agentUsage={catalog.agentUsage}
      connected={connected}
      refreshUsage={refresh}
      cache={cache}
    />
  );
}

export const RemoteSettingsScreen = definePage<Params>({
  id: 'remote-settings',
  title: t('settings.remote.title'),
  Component: View,
  parseRouteParams: ({ kind }) => {
    if (kind !== 'machine' && kind !== 'agent' && kind !== 'mcp')
      throw new Error('Invalid settings page');
    return { kind };
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
