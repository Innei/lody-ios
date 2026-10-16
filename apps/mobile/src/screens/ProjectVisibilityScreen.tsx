import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { NativeGroupedList, NativeSymbolButton } from '@lody-ios/kit';
import type { Catalog } from '@lody/cloud-runtime/models/catalog';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { requestVisibility } from '@/cloud/workspace-settings';
import {
  visibilityId,
  visibilitySections,
  type VisibilityService,
  type VisibilitySnapshot,
} from '@/features/settings/project-visibility';
import { definePage } from '@/lib/presentation';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
export function ProjectVisibilityView({
  workspaceId,
  catalog,
  service = requestVisibility,
  onChanged,
}: {
  workspaceId: string;
  catalog: Catalog;
  service?: VisibilityService;
  onChanged?: () => void;
}) {
  const [snapshot, setSnapshot] = useState<VisibilitySnapshot>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState(false);
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
      if (version.current === id) setSnapshot(next);
    } catch {
      if (version.current === id) setError(true);
    } finally {
      if (version.current === id) setBusy(false);
    }
  }, [workspaceId, service]);
  useEffect(() => {
    void read();
    return () => {
      version.current++;
    };
  }, [read]);
  const refresh = useMemo(
    () => (
      <NativeSymbolButton
        accessibilityName={t('settings.remote.refresh')}
        symbol="arrow.clockwise"
        tint="blue"
        loading={busy}
        style={{ width: 44, height: 44 }}
        onPress={() => void read()}
      />
    ),
    [read, busy],
  );
  useSheetHeader(undefined, undefined, refresh);
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      refreshing={busy}
      onRefresh={() => void read()}
      placeholder={busy && !snapshot ? t('settings.remote.loading') : ''}
      sections={[
        { id: 'scope', footer: t('settings.projects.hint'), rows: [] },
        ...(error
          ? [
              {
                id: 'error',
                footer: t('settings.projects.failed'),
                rows: [
                  { id: 'retry', title: t('common.retry'), action: !busy },
                ],
              },
            ]
          : []),
        ...visibilitySections(snapshot, catalog, !busy && !error),
        ...(!busy &&
        !error &&
        !snapshot?.rows.length &&
        !catalog.projects.length
          ? [{ id: 'empty', footer: t('settings.projects.empty'), rows: [] }]
          : []),
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'retry') void read();
      }}
      onRowAction={({ nativeEvent: { id, actionId } }) => {
        const row = snapshot?.rows.find((item) => visibilityId(item) === id);
        if (
          !row ||
          busy ||
          error ||
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
            if (version.current === request) setError(true);
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
  const { selected, catalog, refresh } = useCatalog();
  if (!account || !selected) return null;
  return (
    <ProjectVisibilityView
      key={`${account.user.id}:${selected.id}`}
      workspaceId={selected.id}
      catalog={catalog}
      onChanged={refresh}
    />
  );
}
export const ProjectVisibilityScreen = definePage({
  id: 'project-visibility',
  title: t('settings.projects.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
