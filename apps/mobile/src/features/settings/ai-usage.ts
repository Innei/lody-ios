import type { NativeListSection } from '@lody-ios/kit';
import { t } from '../../lib/i18n/index.ts';
import {
  type UsageRange,
  type UsageSnapshot,
  type UsageRequest,
  type UsageService,
} from '../../models/ai-usage.ts';
export type {
  UsageRange,
  UsageSnapshot,
  UsageRequest,
  UsageService,
} from '../../models/ai-usage.ts';
export { usageRanges } from '../../models/ai-usage.ts';
export const usageNumber = (value: number | null | undefined) =>
  value == null
    ? t('settings.aiUsage.unavailable')
    : new Intl.NumberFormat('en-US').format(value);
export function usageCost(value: number | null | undefined) {
  if (value == null) return t('settings.aiUsage.unavailable');
  if (value > 0 && value < 0.000001) return '<$0.000001';
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  }).format(value);
}
const utc = (value: number) =>
  new Date(value).toISOString().replace('T', ' ').slice(0, 19) + ' UTC';
export function usageSections(
  value: UsageSnapshot | undefined,
): NativeListSection[] {
  const timeline = value?.timeline;
  const aggregate = timeline?.totals ?? value?.summary?.totals;
  let source = t('settings.aiUsage.noData');
  if (timeline) source = t('settings.aiUsage.timelineSource');
  else if (aggregate) source = t('settings.aiUsage.summarySource');
  const sections: NativeListSection[] = [
    {
      id: 'overview',
      header: t('settings.aiUsage.workspaceTotals'),
      footer: [
        source,
        t('settings.aiUsage.estimateHint'),
        value
          ? t('settings.aiUsage.retrievedAt', { time: utc(value.retrievedAt) })
          : '',
      ]
        .filter(Boolean)
        .join('\n'),
      rows: [
        {
          id: 'usage-tokens',
          title: t('settings.aiUsage.tokens'),
          value: usageNumber(aggregate?.tokens),
          accessibilityValue: usageNumber(aggregate?.tokens),
        },
        {
          id: 'usage-cost',
          title: t('settings.aiUsage.cost'),
          value: usageCost(aggregate?.costUSD),
          accessibilityValue: usageCost(aggregate?.costUSD),
        },
      ],
    },
  ];
  if (aggregate?.breakdown)
    sections.push({
      id: 'breakdown',
      header: t('settings.aiUsage.breakdown'),
      rows: (
        Object.keys(aggregate.breakdown) as (keyof typeof aggregate.breakdown)[]
      ).map((key) => ({
        id: `breakdown:${key}`,
        title: t(`settings.aiUsage.${key}`),
        value: usageNumber(aggregate.breakdown![key]),
        accessibilityValue: usageNumber(aggregate.breakdown![key]),
      })),
    });
  if (timeline) {
    const buckets = [...timeline.buckets]
      .sort((a, b) => a.bucketStartMs - b.bucketStartMs)
      .slice(-30);
    sections.push({
      id: 'timeline',
      header: t('settings.aiUsage.trend'),
      footer: [
        t('settings.aiUsage.rangeBoundary', {
          start: utc(timeline.startMs),
          end: utc(timeline.endMs),
        }),
        t('settings.aiUsage.trendHint'),
      ].join('\n'),
      rows: buckets.map((bucket) => ({
        id: `bucket:${bucket.bucketStartMs}`,
        title: utc(bucket.bucketStartMs),
        subtitle: t('settings.aiUsage.bucketTokens', {
          tokens: usageNumber(bucket.tokens),
        }),
        value: usageCost(bucket.costUSD),
        accessibilityValue: usageCost(bucket.costUSD),
      })),
    });
  }
  return sections;
}
