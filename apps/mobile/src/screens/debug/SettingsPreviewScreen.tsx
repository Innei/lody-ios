import { useCallback, useMemo, useRef, useState } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import { memoryRemoteSettingsCache } from '@/features/settings/remote-settings';
import {
  RemoteSettingsView,
  settingsTitle,
  type SettingsService,
} from '../RemoteSettingsScreen';
import type { RemoteSetting } from '@/models/settings';
import type { Catalog } from '@/models/catalog';
import { projectRows } from '@/cloud/catalog/model';
import { t } from '../../lib/i18n/index.ts';

function View() {
  const { push } = usePageRuntime();
  const rows = useRef<RemoteSetting[]>([
    { kind: 'machine', id: 'm1', name: 'Studio Mac', detail: 'macOS' },
    {
      kind: 'agent',
      id: 'a1',
      machineId: 'm1',
      name: 'Codex',
      prompt: 'Keep changes focused.',
      detail: 'codex',
      machineName: 'Studio Mac',
    },
    {
      kind: 'agent',
      id: 'a2',
      machineId: 'm1',
      name: 'Claude',
      detail: 'claude',
      machineName: 'Studio Mac',
      readOnly: true,
    },
    {
      kind: 'agent',
      id: 'a3',
      machineId: 'm1',
      name: 'Kimi',
      detail: 'kimi',
      machineName: 'Studio Mac',
    },
    {
      kind: 'agent',
      id: 'a4',
      machineId: 'm1',
      name: 'Custom API',
      detail: 'codex',
      machineName: 'Studio Mac',
    },
    {
      kind: 'mcp',
      id: 'c1',
      name: 'Documentation',
      detail: 'http',
      enabledByDefault: false,
    },
  ]);
  const failLoad = useRef(true),
    failSave = useRef(true);
  const service = useCallback<SettingsService>(async (request) => {
    if (!__DEV__) throw new Error('Development only');
    if (failLoad.current) {
      failLoad.current = false;
      throw new Error(t('settings.remote.loadFailed'));
    }
    if (request.edit) {
      if (request.kind === 'agent' && failSave.current) {
        failSave.current = false;
        throw new Error(t('settings.remote.saveFailed'));
      }
      const edit = request.edit;
      rows.current = rows.current.map((row) =>
        row.id === edit.item.id
          ? {
              ...row,
              name: edit.name.trim(),
              ...(request.kind === 'agent' ? { prompt: edit.prompt } : {}),
              ...(request.kind === 'mcp'
                ? { enabledByDefault: edit.enabledByDefault }
                : {}),
            }
          : row,
      );
    }
    return rows.current.filter((row) => row.kind === request.kind);
  }, []);
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      sections={[
        {
          id: 'remote',
          rows: (['machine', 'agent', 'mcp'] as const).map((kind) => ({
            id: `settings-${kind}`,
            title: settingsTitle(kind),
            disclosure: true,
            action: true,
            navigates: true,
          })),
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        const kind = id.slice('settings-'.length);
        if (kind !== 'machine' && kind !== 'agent' && kind !== 'mcp') return;
        void push(
          SettingsListPreviewScreen,
          { kind, service },
          { title: settingsTitle(kind) },
        );
      }}
    />
  );
}

const SettingsListPreviewScreen = definePage<{
  kind: RemoteSetting['kind'];
  service: SettingsService;
}>({
  id: 'settings-list-preview',
  title: t('settings.remote.title'),
  Component: () => {
    const { params } = usePageRuntime<{
      kind: RemoteSetting['kind'];
      service: SettingsService;
    }>();
    const [offline, setOffline] = useState(false);
    const [percent, setPercent] = useState(32);
    const cache = useMemo(memoryRemoteSettingsCache, []);
    const agentUsage = previewUsage(percent);
    const service = useCallback<SettingsService>(
      async (request) => {
        if (offline) throw new Error(t('settings.remote.loadFailed'));
        return params.service(request);
      },
      [offline, params.service],
    );
    return (
      <RemoteSettingsView
        {...params}
        service={service}
        workspaceId="offline-settings"
        agentUsage={agentUsage}
        connected={!offline}
        cache={cache}
        refreshUsage={() => {
          if (offline) setPercent(72);
          setOffline(!offline);
        }}
      />
    );
  },
  parseRouteParams: () => {
    throw new Error('Open from settings preview');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});

function previewUsage(percent: number): Catalog['agentUsage'] {
  const configs = [
    ['a1', 'Codex', 'codex'],
    ['a2', 'Claude', 'claude'],
    ['a3', 'Kimi', 'kimi'],
    ['a4', 'Custom API', 'codex'],
  ].map(([id, name, provider]) => ({
    key: ['agentConfig', id],
    value: {
      id,
      name,
      agentType: provider,
      cliType: 'builtin',
      machineId: 'm1',
      env: id === 'a4' ? { API_KEY: 'offline-fixture' } : {},
    },
  }));
  return projectRows(
    [
      ...configs,
      ...[
        {
          provider: 'codex',
          id: 'codex',
          windows: [
            {
              usedPercent: percent,
              windowDurationSeconds: 18000,
              resetsAtEpochSeconds: 1900000000,
            },
            {
              usedPercent: 61,
              windowDurationSeconds: 604800,
              resetsAtEpochSeconds: 1900400000,
            },
          ],
        },
        {
          provider: 'codex',
          id: 'codex_bengalfox',
          windows: [
            {
              usedPercent: 8,
              windowDurationSeconds: 604800,
              resetsAtEpochSeconds: null,
            },
          ],
        },
        {
          provider: 'claude',
          id: 'claude',
          windows: [
            {
              usedPercent: 100,
              windowDurationSeconds: 18000,
              resetsAtEpochSeconds: 1,
            },
          ],
        },
      ].map((q) => ({
        key: ['rateLimit', q.provider, q.id],
        value: {
          limitId: q.id,
          scope: { providerId: q.provider },
          windows: q.windows,
        },
      })),
    ],
    'm1',
  ).agentUsage;
}

export const SettingsPreviewScreen = definePage({
  id: 'settings-preview',
  title: t('settings.remote.title'),
  presentation: { headerVariant: 'transparent' },
  Component: View,
});
