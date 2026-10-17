import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Linking } from 'react-native';
import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import type {
  MemoryAssociation,
  MemorySnapshot,
  MemoryStatus,
} from '@lody/cloud-runtime/models/memory';
import { memoryError, requestMemory, type MemoryService } from '@/cloud/memory';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { listState } from '@/features/settings/list-state';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';

const statusText = (status: MemoryStatus) =>
  t(`settings.memory.status.${status}`);
const entryId = (entry: MemoryAssociation) =>
  JSON.stringify([entry.providerId, entry.memoryId]);
const source = (snapshot: MemorySnapshot) =>
  snapshot.machines.find((m) => m.id === snapshot.machineId)?.name ??
  snapshot.machineId ??
  '';
const missing = (snapshot: MemorySnapshot, item: MemoryAssociation) =>
  snapshot.status === 'ready' &&
  item.providerId === 'nowledge-mem' &&
  !snapshot.identities.some((i) => i.id === item.memoryId);
function useMemoryScope(expected: string) {
  const { account } = useAuth();
  const { selected } = useCatalog();
  const { cancel } = usePageRuntime();
  const valid = expected === `${account?.user.id ?? ''}:${selected?.id ?? ''}`;
  useEffect(() => {
    if (!valid) cancel();
  }, [valid, cancel]);
  return valid;
}
type DetailParams = {
  workspaceId: string;
  item: MemoryAssociation;
  snapshot: MemorySnapshot;
  service: MemoryService;
  actorScope: string;
};
function Detail() {
  const { params, finish } = usePageRuntime<DetailParams>();
  const { item, snapshot, service, workspaceId } = params;
  const valid = useMemoryScope(params.actorScope);
  const current = useRef(valid);
  current.current = valid;
  const guard = useRef(false);
  const [busy, setBusy] = useState(false),
    [failure, setFailure] = useState(''),
    [uncertain, setUncertain] = useState(false);
  const colors = usePalette();
  if (!valid) return null;
  const remove = async () => {
    if (guard.current || !current.current || uncertain) return;
    guard.current = true;
    setBusy(true);
    try {
      await service({
        workspaceId,
        machineId: item.machineId,
        action: 'remove',
        base: item,
      });
      if (current.current) finish();
    } catch (cause) {
      if (current.current) {
        const error = memoryError(cause);
        setFailure(error.text);
        setUncertain(error.uncertain);
      }
    } finally {
      guard.current = false;
      setBusy(false);
    }
  };
  const cachedNotice = snapshot.cached
    ? {
        symbol: 'icloud.slash',
        text: t('settings.memory.cached'),
        tint: 'warning',
      }
    : undefined;
  const rows: NativeListSection['rows'] = [
    {
      id: 'memory-name',
      title: item.name,
      subtitle: item.description,
      wrapSubtitle: true,
    },
    {
      id: 'memory-id',
      title: t('settings.memory.identity'),
      subtitle: item.memoryId,
      wrapSubtitle: true,
    },
    {
      id: 'memory-source',
      title: source(snapshot),
      subtitle: item.machineId,
      wrapSubtitle: true,
    },
    {
      id: 'memory-provider',
      title: t('settings.memory.provider'),
      subtitle: item.providerId,
    },
    {
      id: 'memory-status',
      title:
        item.providerId === 'nowledge-mem'
          ? statusText(snapshot.status)
          : t('settings.memory.unverifiedProvider'),
      subtitle: missing(snapshot, item)
        ? t('settings.memory.missing')
        : undefined,
      wrapSubtitle: true,
    },
  ];
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      notice={
        failure
          ? {
              symbol: 'exclamationmark.triangle',
              text: failure,
              tint: 'warning',
            }
          : cachedNotice
      }
      sections={[
        { id: 'details', footer: t('settings.memory.contents'), rows },
        {
          id: 'remove',
          footer: t('settings.memory.removeHint'),
          rows: [
            {
              id: 'memory-remove',
              title: t('settings.memory.remove'),
              destructive: true,
              action: !busy && !uncertain && !snapshot.cached,
            },
          ],
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id !== 'memory-remove' || busy || uncertain || snapshot.cached)
          return;
        Alert.alert(
          t('settings.memory.remove'),
          t('settings.memory.removeConfirm', { name: item.name }),
          [
            { text: t('common.cancel'), style: 'cancel' },
            {
              text: t('settings.memory.remove'),
              style: 'destructive',
              onPress: () => void remove(),
            },
          ],
        );
      }}
    />
  );
}
const MemoryDetailScreen = definePage<DetailParams>({
  id: 'memory-detail',
  title: t('settings.memory.details'),
  Component: Detail,
  parseRouteParams: () => {
    throw new Error('Open memory details from settings');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});

export function MemorySettingsView({
  workspaceId,
  service = requestMemory,
}: {
  workspaceId: string;
  service?: MemoryService;
}) {
  const { account } = useAuth();
  const { selected } = useCatalog();
  const actorScope = `${account?.user.id ?? ''}:${selected?.id ?? ''}`;
  const { push } = usePageRuntime();
  const colors = usePalette();
  const [machineId, setMachine] = useState<string>();
  const [snapshot, setSnapshot] = useState<MemorySnapshot>();
  const [loading, setLoading] = useState(true),
    [failed, setFailed] = useState(false),
    [failure, setFailure] = useState(''),
    [uncertain, setUncertain] = useState(false);
  const [syncedAt, setSyncedAt] = useState<number>();
  const generation = useRef(0),
    writing = useRef(false);
  const refresh = useCallback(async () => {
    const id = ++generation.current;
    setLoading(true);
    setFailed(false);
    try {
      const next = await service({ workspaceId, machineId, action: 'list' });
      if (generation.current === id) {
        setSnapshot(next);
        setSyncedAt(Date.now());
        setUncertain(false);
        setFailure('');
      }
    } catch (cause) {
      if (generation.current === id) {
        setFailed(true);
        if (String(cause).includes('forbidden')) {
          setSnapshot(undefined);
          setFailure(t('settings.memory.forbidden'));
        }
      }
    } finally {
      if (generation.current === id) setLoading(false);
    }
  }, [workspaceId, machineId, service]);
  useEffect(() => {
    void refresh();
    return () => {
      generation.current++;
    };
  }, [refresh]);
  const importIdentity = async (id: string) => {
    if (
      !snapshot ||
      writing.current ||
      loading ||
      failed ||
      uncertain ||
      snapshot.cached ||
      snapshot.status !== 'ready'
    )
      return;
    writing.current = true;
    setLoading(true);
    const current = generation.current;
    try {
      const next = await service({
        workspaceId,
        machineId: snapshot.machineId,
        action: 'import',
        memoryId: id,
      });
      if (generation.current === current) {
        setSnapshot(next);
        setFailure('');
      }
    } catch (cause) {
      if (generation.current === current) {
        const error = memoryError(cause);
        const status = error.status;
        if (status)
          setSnapshot((previous) =>
            previous ? { ...previous, status, identities: [] } : previous,
          );
        setFailure(error.text);
        setUncertain(error.uncertain);
      }
    } finally {
      writing.current = false;
      if (generation.current === current) setLoading(false);
    }
  };
  const state = listState({
    title: t('settings.memory.unavailable'),
    hasData: !!snapshot,
    loading,
    failed,
    syncedAt,
    unconfirmed: uncertain,
    partial: snapshot?.cached ? t('settings.memory.cached') : undefined,
  });
  const unavailable = state.unavailable && {
    ...state.unavailable,
    message: failure || state.unavailable.message,
  };
  const sections: NativeListSection[] = [];
  if (snapshot) {
    sections.push({
      id: 'machines',
      header: t('settings.memory.source'),
      footer: t('settings.memory.ownOnly'),
      rows: snapshot.machines.map((machine) => ({
        id: `machine:${machine.id}`,
        title: machine.name,
        subtitle: machine.id,
        action: !loading,
        selected: machine.id === snapshot.machineId,
      })),
    });
    if (snapshot.machineId) {
      sections.push({
        id: 'provider',
        header: 'Nowledge Mem',
        footer: t('settings.memory.contents'),
        rows: [
          {
            id: 'provider-status',
            title: statusText(snapshot.status),
            wrapSubtitle: true,
          },
          ...(snapshot.status === 'not_installed'
            ? [
                {
                  id: 'provider-install',
                  title: t('settings.memory.install'),
                  action: true,
                  disclosure: true,
                },
              ]
            : []),
        ],
      });
      sections.push({
        id: 'saved',
        header: t('settings.memory.saved'),
        footer: snapshot.entries.length
          ? undefined
          : t('settings.memory.empty'),
        rows: snapshot.entries.map((item) => ({
          id: `saved:${entryId(item)}`,
          title: item.name,
          subtitle: [
            source(snapshot),
            item.providerId,
            item.memoryId,
            item.description,
            missing(snapshot, item) ? t('settings.memory.missing') : '',
          ]
            .filter(Boolean)
            .join(' · '),
          wrapSubtitle: true,
          action: true,
          disclosure: true,
          navigates: true,
        })),
      });
      if (snapshot.status === 'ready' && !snapshot.cached)
        sections.push({
          id: 'available',
          header: t('settings.memory.available'),
          footer: snapshot.identities.length
            ? t('settings.memory.importHint')
            : t('settings.memory.noIdentities'),
          rows: snapshot.identities.map((identity) => {
            const linked = snapshot.entries.some(
              (e) =>
                e.providerId === 'nowledge-mem' && e.memoryId === identity.id,
            );
            return {
              id: `import:${identity.id}`,
              title: identity.name || identity.id,
              subtitle: [
                identity.id,
                identity.description,
                linked ? t('settings.memory.imported') : '',
              ]
                .filter(Boolean)
                .join(' · '),
              wrapSubtitle: true,
              action: !linked && !loading && !failed && !uncertain,
            };
          }),
        });
    }
  }
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      loading={state.loading}
      unavailable={unavailable}
      notice={
        failure && !state.unavailable
          ? {
              symbol: 'exclamationmark.triangle',
              text: failure,
              tint: 'warning',
              actionLabel: t('settings.state.refresh'),
              actionSymbol: 'arrow.clockwise',
            }
          : state.notice
      }
      onNoticeAction={() => {
        if (!writing.current) void refresh();
      }}
      onUnavailableAction={() => void refresh()}
      refreshing={loading && !!snapshot}
      onRefresh={() => {
        if (!writing.current) void refresh();
      }}
      placeholder={
        snapshot && !snapshot.machines.length
          ? t('settings.memory.noMachines')
          : ''
      }
      onRowPress={({ nativeEvent: { id } }) => {
        if (!snapshot || loading) return;
        if (id.startsWith('machine:') && id.slice(8) !== snapshot.machineId) {
          generation.current++;
          setSnapshot(undefined);
          setFailure('');
          setUncertain(false);
          setMachine(id.slice(8));
        }
        if (id === 'provider-install')
          void Linking.openURL('https://mem.nowledge.co/en');
        if (id.startsWith('import:'))
          Alert.alert(
            t('settings.memory.import'),
            t('settings.memory.importConfirm'),
            [
              { text: t('common.cancel'), style: 'cancel' },
              {
                text: t('settings.memory.import'),
                onPress: () => void importIdentity(id.slice(7)),
              },
            ],
          );
        const item = snapshot.entries.find((e) => `saved:${entryId(e)}` === id);
        if (item) {
          const current = generation.current;
          void push(MemoryDetailScreen, {
            workspaceId,
            item,
            snapshot: { ...snapshot, cached: snapshot.cached || failed },
            service,
            actorScope,
          }).then((result) => {
            if (result.status === 'completed' && generation.current === current)
              void refresh();
          });
        }
      }}
    />
  );
}
function View() {
  const { account } = useAuth();
  const { selected } = useCatalog();
  if (!account || !selected) return null;
  return (
    <MemorySettingsView
      key={`${account.user.id}:${selected.id}`}
      workspaceId={selected.id}
    />
  );
}
export const MemorySettingsScreen = definePage({
  id: 'memory-settings',
  title: t('settings.memory.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
