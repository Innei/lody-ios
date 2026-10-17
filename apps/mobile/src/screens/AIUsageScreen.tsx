import { useCallback, useEffect, useRef, useState } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { requestUsage } from '@/cloud/workspace-settings';
import {
  usageRanges,
  usageSections,
  type UsageRange,
  type UsageSnapshot,
  type UsageService,
} from '@/features/settings/ai-usage';
import { listState } from '@/features/settings/list-state';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
export function AIUsageView({
  workspaceId,
  service = requestUsage,
}: {
  workspaceId: string;
  service?: UsageService;
}) {
  const [range, setRange] = useState<UsageRange>('day');
  const [data, setData] = useState<UsageSnapshot>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState(false);
  const [pulled, setPulled] = useState(false);
  const version = useRef(0);
  const colors = usePalette();
  const read = useCallback(async () => {
    const id = ++version.current;
    setBusy(true);
    setError(false);
    try {
      const next = await service({
        page: 'usage',
        action: 'list',
        workspaceId,
        range,
      });
      if (!next.summary && !next.timeline) throw new Error('usage_unavailable');
      if (next.workspaceId !== workspaceId || next.range !== range)
        throw new Error('scope_changed');
      if (version.current === id) setData(next);
    } catch {
      if (version.current === id) setError(true);
    } finally {
      if (version.current === id) {
        setBusy(false);
        setPulled(false);
      }
    }
  }, [workspaceId, range, service]);
  useEffect(() => {
    void read();
    return () => {
      version.current++;
    };
  }, [read]);
  const value =
    data?.range === range && data.workspaceId === workspaceId
      ? data
      : undefined;
  const state = listState({
    title: t('settings.unavailable.usage'),
    hasData: !!value,
    loading: busy,
    failed: error,
    partial: value?.errors.length
      ? t('settings.aiUsage.partialShort')
      : undefined,
    syncedAt: value?.retrievedAt,
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
      segments={usageRanges.map((item) => t(`settings.aiUsage.${item}`))}
      selectedSegment={usageRanges.indexOf(range)}
      onSegmentChange={({ nativeEvent: { index } }) => {
        const next = usageRanges[index];
        if (next) setRange(next);
      }}
      sections={usageSections(value)}
      onRowPress={() => {}}
    />
  );
}
function View() {
  const { account } = useAuth();
  const { selected } = useCatalog();
  if (!account || !selected) return null;
  return (
    <AIUsageView
      key={`${account.user.id}:${selected.id}`}
      workspaceId={selected.id}
    />
  );
}
export const AIUsageScreen = definePage({
  id: 'ai-usage',
  title: t('settings.aiUsage.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
