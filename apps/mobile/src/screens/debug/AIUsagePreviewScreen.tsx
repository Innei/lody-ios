import { useMemo, useState } from 'react';
import { View as RNView } from 'react-native';
import { AppText } from '@/ui/AppText';
import { definePage } from '@/lib/presentation';
import type { UsageService, UsageSnapshot } from '@/features/settings/ai-usage';
import { AIUsageView } from '../AIUsageScreen';
function Preview() {
  const [late, setLate] = useState(false);
  const [pending, setPending] = useState(false);
  const service = useMemo<UsageService>(() => {
    let first = true,
      dayReads = 0;
    let releaseWeek: (() => void) | undefined;
    return async (request) => {
      if (request.range === 'day' && ++dayReads === 3)
        throw new Error('fixture-offline');
      if (first) {
        first = false;
        throw new Error('fixture-load');
      }
      const tokens = { day: 12500, week: 17, month: 400000, total: 0 }[
        request.range
      ];
      let cost: number | null = 1.25;
      if (request.range === 'day') cost = null;
      if (request.range === 'total') cost = 0;
      const startMs = Date.UTC(2026, 9, 16),
        endMs = startMs + 86400000;
      const result: UsageSnapshot = {
        workspaceId: request.workspaceId,
        range: request.range,
        retrievedAt: endMs - 1000,
        summary:
          request.range === 'day'
            ? null
            : { totals: { tokens: 999, costUSD: 99 } },
        timeline: {
          totals: { tokens, costUSD: cost },
          startMs,
          endMs,
          bucketSizeMs: 86400000,
          buckets: [{ bucketStartMs: startMs, tokens, costUSD: cost }],
        },
        errors: request.range === 'day' ? ['summary'] : [],
      };
      if (request.range === 'week') {
        setPending(true);
        await new Promise<void>((resolve) => {
          releaseWeek = () => {
            resolve();
            setPending(false);
            setLate(true);
          };
        });
      }
      if (request.range === 'month') releaseWeek?.();
      return result;
    };
  }, []);
  return (
    <RNView style={{ flex: 1 }}>
      <AIUsageView workspaceId="usage-fixture" service={service} />
      {pending && (
        <AppText testID="usage-week-pending">Week response pending</AppText>
      )}
      {late && (
        <AppText testID="usage-late-settled">
          Late week response delivered
        </AppText>
      )}
    </RNView>
  );
}
export const AIUsagePreviewScreen = definePage({
  id: 'ai-usage-preview',
  title: 'AI Usage',
  Component: Preview,
  presentation: { headerVariant: 'transparent' },
});
