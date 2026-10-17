import { useCallback, useEffect, useRef, useState } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import type { MachinePresence } from '@lody/cloud-runtime/models/machines';
import type { Catalog } from '@lody/cloud-runtime/models/catalog';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { useMachinePresence } from '@/cloud/catalog/machines';
import { requestVisibility } from '@/cloud/workspace-settings';
import {
  visibilityId,
  visibilitySections,
  type VisibilityService,
  type VisibilitySnapshot,
} from '@/features/settings/project-visibility';
import { listState } from '@/features/settings/list-state';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
export function ProjectVisibilityView({
  workspaceId,
  catalog,
  service = requestVisibility,
  onChanged,
  presence,
  connected = true,
}: {
  workspaceId: string;
  catalog: Catalog;
  service?: VisibilityService;
  onChanged?: () => void;
  presence?: MachinePresence;
  connected?: boolean;
}) {
  const [snapshot, setSnapshot] = useState<VisibilitySnapshot>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState(false);
  const [unconfirmed, setUnconfirmed] = useState(false);
  const [pulled, setPulled] = useState(false);
  const [loadedAt, setLoadedAt] = useState<number>();
  const version = useRef(0),
    mutating = useRef(false);
  const colors = usePalette();
  const read = useCallback(async () => {
    if (mutating.current) return;
    const id = ++version.current;
    setBusy(true);
    setError(false);
    try {
      const next = await service({
        page: 'projects',
        workspaceId,
        action: 'list',
      });
      if (version.current === id) {
        setSnapshot(next);
        setUnconfirmed(false);
        setLoadedAt(Date.now());
      }
    } catch {
      if (version.current === id) setError(true);
    } finally {
      if (version.current === id) {
        setBusy(false);
        setPulled(false);
      }
    }
  }, [workspaceId, service]);
  useEffect(() => {
    void read();
    return () => {
      version.current++;
    };
  }, [read]);
  const hasData = !!snapshot?.rows.length || catalog.projects.length > 0;
  const state = listState({
    title: t('settings.unavailable.projects'),
    hasData: !!snapshot,
    loading: busy,
    failed: error,
    offline: !connected,
    unconfirmed,
    syncedAt: loadedAt,
  });
  const reload = () => void read();
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      refreshing={pulled && busy}
      onRefresh={() => {
        setPulled(true);
        reload();
      }}
      loading={state.loading}
      notice={state.notice}
      unavailable={state.unavailable}
      onNoticeAction={reload}
      onUnavailableAction={reload}
      placeholder={
        snapshot && !busy && !hasData ? t('settings.projects.empty') : ''
      }
      sections={
        snapshot && hasData
          ? [
              {
                id: 'scope',
                footer: t('settings.projects.hintShort'),
                rows: [],
              },
              ...visibilitySections(
                snapshot,
                catalog,
                !busy && !error && !unconfirmed,
                connected ? presence : undefined,
              ),
              { id: 'footer', footer: t('settings.projects.footer'), rows: [] },
            ]
          : []
      }
      onRowPress={() => {}}
      onRowAction={({ nativeEvent: { id, actionId } }) => {
        const row = snapshot?.rows.find((item) => visibilityId(item) === id);
        if (
          !row ||
          busy ||
          error ||
          unconfirmed ||
          mutating.current ||
          row.ownerUserId !== snapshot?.userId ||
          !['shared', 'private'].includes(actionId)
        )
          return;
        const shared = actionId === 'shared';
        if (shared === row.sharedWithTeam) return;
        mutating.current = true;
        setBusy(true);
        const request = ++version.current;
        void service({
          page: 'projects',
          workspaceId,
          action: 'set',
          machineId: row.machineId,
          localProjectId: row.localProjectId,
          sharedWithTeam: shared,
        })
          .then((next) => {
            if (version.current === request) {
              setSnapshot(next);
              setError(false);
              onChanged?.();
            }
          })
          .catch(() => {
            if (version.current === request) setUnconfirmed(true);
          })
          .finally(() => {
            mutating.current = false;
            if (version.current === request) setBusy(false);
          });
      }}
    />
  );
}
function View() {
  const { account } = useAuth();
  const { selected, catalog, connected, refresh } = useCatalog();
  const presence = useMachinePresence(selected?.id);
  if (!account || !selected) return null;
  return (
    <ProjectVisibilityView
      key={`${account.user.id}:${selected.id}`}
      workspaceId={selected.id}
      catalog={catalog}
      onChanged={refresh}
      presence={presence}
      connected={connected}
    />
  );
}
export const ProjectVisibilityScreen = definePage({
  id: 'project-visibility',
  title: t('settings.projects.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
