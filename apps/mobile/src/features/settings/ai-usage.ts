import type { NativeListSection, NativeListVisual } from '@lody-ios/kit';
import { currentLocale, t } from '../../lib/i18n/index.ts';
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
const missing = '—';

const compactUnits = [
  [1e9, 'B'],
  [1e6, 'M'],
  [1e3, 'K'],
] as const;

// Hermes ignores Intl's compact notation, so the suffixes are applied here.
export function usageCompactNumber(value: number | null | undefined) {
  if (value == null) return missing;
  const unit = compactUnits.find(([size]) => Math.abs(value) >= size);
  const format = new Intl.NumberFormat(currentLocale(), {
    maximumFractionDigits: 2,
  });
  if (!unit) return format.format(value);
  return `${format.format(value / unit[0])}${unit[1]}`;
}

export function usageCompactCost(value: number | null | undefined) {
  if (value == null) return missing;
  if (value > 0 && value < 0.01) return '<$0.01';
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

const DAY = 86_400_000;
const CHART_LIMIT = 90;

type Bucket = NonNullable<UsageSnapshot['timeline']>['buckets'][number];

function bucketTime(value: number, bucketSizeMs: number, spanMs: number) {
  let options: Intl.DateTimeFormatOptions = { month: 'short', day: 'numeric' };
  if (bucketSizeMs < DAY && spanMs <= DAY)
    options = { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' };
  else if (bucketSizeMs < DAY)
    options = {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      hourCycle: 'h23',
    };
  return new Intl.DateTimeFormat(currentLocale(), {
    ...options,
    timeZone: 'UTC',
  }).format(value);
}

function merged(buckets: Bucket[]): Bucket[] {
  const size = Math.ceil(buckets.length / CHART_LIMIT);
  if (size <= 1) return buckets;
  const result: Bucket[] = [];
  for (let start = 0; start < buckets.length; start += size) {
    const group = buckets.slice(start, start + size);
    const costs = group.map((bucket) => bucket.costUSD);
    result.push({
      bucketStartMs: group[0]!.bucketStartMs,
      tokens: group.reduce((sum, bucket) => sum + bucket.tokens, 0),
      costUSD: costs.some((cost) => cost == null)
        ? null
        : costs.reduce<number>((sum, cost) => sum + (cost ?? 0), 0),
    });
  }
  return result;
}

const mixKeys = [
  'inputTokens',
  'outputTokens',
  'cacheReadInputTokens',
  'cacheCreationInputTokens',
  'reasoningOutputTokens',
] as const;

function barsVisual(
  timeline: NonNullable<UsageSnapshot['timeline']>,
): NativeListVisual | undefined {
  const sorted = [...timeline.buckets].sort(
    (a, b) => a.bucketStartMs - b.bucketStartMs,
  );
  if (!sorted.length) return undefined;
  const buckets = merged(sorted);
  const span = sorted.at(-1)!.bucketStartMs - sorted[0]!.bucketStartMs;
  const time = (bucket: Bucket) =>
    bucketTime(bucket.bucketStartMs, timeline.bucketSizeMs, span);
  const step = Math.max(1, Math.ceil(buckets.length / 4));
  const items = buckets.map((bucket, index) => {
    const detail = t('settings.aiUsage.bucketDetail', {
      time: time(bucket),
      tokens: usageCompactNumber(bucket.tokens),
      cost: usageCompactCost(bucket.costUSD),
    });
    return {
      id: `bucket:${bucket.bucketStartMs}`,
      amount: bucket.tokens,
      ...(bucket.costUSD == null ? {} : { cost: bucket.costUSD }),
      ...(index % step === 0 ? { axisLabel: time(bucket) } : {}),
      detail,
      accessibilityLabel: detail,
    };
  });
  const peak = buckets.reduce((top, bucket) =>
    bucket.tokens > top.tokens ? bucket : top,
  );
  const priced = buckets.filter((bucket) => bucket.costUSD != null);
  const costPeak = priced.length
    ? priced.reduce((top, bucket) =>
        (bucket.costUSD ?? 0) > (top.costUSD ?? 0) ? bucket : top,
      )
    : undefined;
  return {
    type: 'bars',
    title: t('settings.aiUsage.chartTitle'),
    summary: t('settings.aiUsage.peak', {
      time: time(peak),
      tokens: usageCompactNumber(peak.tokens),
    }),
    items,
    ...(costPeak
      ? {
          metrics: [
            t('settings.aiUsage.tokens'),
            t('settings.aiUsage.costMetric'),
          ],
          costTitle: t('settings.aiUsage.costChartTitle'),
          costSummary: t('settings.aiUsage.peak', {
            time: time(costPeak),
            tokens: usageCompactCost(costPeak.costUSD),
          }),
        }
      : {}),
  };
}

function mixVisual(
  breakdown: NonNullable<
    NonNullable<UsageSnapshot['summary']>['totals']['breakdown']
  >,
): NativeListVisual {
  const total = mixKeys.reduce((sum, key) => sum + (breakdown[key] ?? 0), 0);
  return {
    type: 'mix',
    items: mixKeys.map((key) => {
      const value = breakdown[key];
      const fraction = value != null && total ? value / total : 0;
      const percent =
        value == null || !total ? missing : `${Math.round(fraction * 100)}%`;
      return {
        label: t(`settings.aiUsage.${key}`),
        value: value == null ? missing : usageNumber(value),
        percent,
        fraction,
        accessibilityValue:
          value == null
            ? t('settings.aiUsage.unavailable')
            : `${usageNumber(value)}, ${percent}`,
      };
    }),
  };
}

export function usageSections(
  value: UsageSnapshot | undefined,
): NativeListSection[] {
  if (!value) return [];
  const timeline = value.timeline;
  const aggregate = timeline?.totals ?? value.summary?.totals;
  const sections: NativeListSection[] = [
    {
      id: 'overview',
      rows: [],
      visual: {
        type: 'stats',
        items: [
          {
            label: t('settings.aiUsage.tokens'),
            value: usageCompactNumber(aggregate?.tokens),
            accessibilityValue: usageNumber(aggregate?.tokens),
          },
          {
            label: t('settings.aiUsage.costShort'),
            value: usageCompactCost(aggregate?.costUSD),
            accessibilityValue: usageCost(aggregate?.costUSD),
          },
        ],
      },
    },
  ];
  const bars = timeline ? barsVisual(timeline) : undefined;
  if (bars) sections.push({ id: 'timeline', rows: [], visual: bars });
  if (aggregate?.breakdown)
    sections.push({
      id: 'mix',
      header: t('settings.aiUsage.mix'),
      rows: [],
      visual: mixVisual(aggregate.breakdown),
    });
  sections[sections.length - 1]!.footer = t('settings.aiUsage.footer', {
    time: new Intl.DateTimeFormat(currentLocale(), {
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
      timeZone: 'UTC',
    }).format(value.retrievedAt),
  });
  return sections;
}
