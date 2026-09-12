import { useEffect, useRef, useState } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { requestSettings } from '@/cloud/settings';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import type { RemoteSetting, SettingsRequest } from '@/models/settings';
import { t } from '../lib/i18n/index.ts';
import { agentUsageRows } from '@/features/settings/agent-usage';
import type { Catalog } from '@/models/catalog';
import { RemoteSettingEditorScreen } from './RemoteSettingEditorScreen';

export type SettingsService = (
  request: SettingsRequest,
) => Promise<RemoteSetting[]>;
type Params = { kind: RemoteSetting['kind'] };
export const settingsTitle = (kind: RemoteSetting['kind']) =>
  t(`settings.remote.${kind}`);

const settingId = (item: RemoteSetting) =>
  `setting:${item.kind}:${item.machineId ?? ''}:${item.id}`;

function settingValue(item: RemoteSetting) {
  if (item.kind !== 'mcp') return undefined;
  return t(
    item.enabledByDefault
      ? 'settings.remote.enabled'
      : 'settings.remote.disabled',
  );
}

export function RemoteSettingsView({
  kind,
  workspaceId,
  service = requestSettings,
  agentUsage,
  connected = true,
  refreshUsage,
  machineNames,
}: Params & {
  workspaceId: string;
  service?: SettingsService;
  agentUsage?: Catalog['agentUsage'];
  connected?: boolean;
  refreshUsage?: () => void;
  machineNames?: Catalog['machineNames'];
}) {
  const colors = usePalette();
  const { present } = usePageRuntime();
  const [items, setItems] = useState<RemoteSetting[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const requestId = useRef(0);
  const visibleItems: RemoteSetting[] =
    items !== null || kind !== 'agent'
      ? (items ?? [])
      : Object.entries(agentUsage ?? {}).flatMap(([machineId, usage]) =>
          usage.configs.map((config) => ({
            kind: 'agent' as const,
            id: config.id,
            name: config.name,
            machineId,
            machineName: machineNames?.[machineId] ?? machineId,
            detail: config.provider,
          })),
        );
  const settingRows = visibleItems.map((item) => ({
    id: settingId(item),
    title: item.name || item.id,
    subtitle: [
      item.detail,
      item.machineName,
      item.readOnly ? t('settings.remote.readOnly') : undefined,
    ]
      .filter(Boolean)
      .join(' · '),
    value: settingValue(item),
    disclosure: items !== null && !item.readOnly,
    action: items !== null && !loading && !error && !item.readOnly,
  }));
  async function load() {
    const id = ++requestId.current;
    setLoading(true);
    setError('');
    try {
      const result = await service({ workspaceId, kind });
      if (id === requestId.current) setItems(result);
    } catch (cause) {
      if (id === requestId.current)
        setError(
          cause instanceof Error
            ? cause.message
            : t('settings.remote.loadFailed'),
        );
    } finally {
      if (id === requestId.current) setLoading(false);
    }
  }
  useEffect(() => {
    setItems(null);
    void load();
    return () => {
      requestId.current++;
    };
  }, [workspaceId, kind, service]);
  let placeholder = t('settings.remote.empty');
  if (loading) placeholder = t('settings.remote.loading');
  if (error) placeholder = '';
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      refreshing={loading}
      onRefresh={() => {
        refreshUsage?.();
        void load();
      }}
      placeholder={placeholder}
      sections={[
        ...(kind === 'agent'
          ? visibleItems.map((item, index) => {
              const usageRows = agentUsageRows(
                item,
                agentUsage?.[item.machineId ?? ''],
              );
              let footer: string | undefined;
              if (usageRows.length)
                footer = connected
                  ? t('settings.usage.shared')
                  : t('settings.usage.offline');
              return {
                id: settingId(item),
                rows: [settingRows[index]!, ...usageRows],
                footer,
              };
            })
          : [
              {
                id: 'settings',
                footer: error ? undefined : t(`settings.remote.${kind}Hint`),
                rows: settingRows,
              },
            ]),
        ...(error
          ? [
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
            ]
          : []),
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'retry') {
          void load();
          return;
        }
        const item = items?.find((item) => settingId(item) === id);
        if (!item || item.readOnly || loading || error) return;
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
          if (result.status === 'completed') void load();
        });
      }}
    />
  );
}

function View() {
  const { params, cancel } = usePageRuntime<Params>();
  const { selected, catalog, connected, refresh } = useCatalog();
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
      machineNames={catalog.machineNames}
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
