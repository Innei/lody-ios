import { usageSchema } from '../../src/models/ai-usage.ts';
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  usageSections,
  usageCost,
  usageCompactCost,
  usageCompactNumber,
  usageNumber,
} from '../../src/features/settings/ai-usage.ts';
import { setLocale } from '../../src/lib/i18n/index.ts';
setLocale('en');

const hour = 3600_000;
const snapshot = usageSchema.parse({
  workspaceId: 'w',
  range: 'day',
  retrievedAt: 6 * hour,
  summary: { totals: { tokens: 99, costUSD: 99 } },
  timeline: {
    totals: {
      tokens: 1_284_331,
      costUSD: null,
      breakdown: {
        inputTokens: 300,
        outputTokens: 100,
        cacheReadInputTokens: 600,
        cacheCreationInputTokens: 0,
        reasoningOutputTokens: null,
      },
    },
    startMs: 0,
    endMs: 24 * hour,
    bucketSizeMs: hour,
    buckets: [
      { bucketStartMs: 2 * hour, tokens: 5, costUSD: 0.5 },
      { bucketStartMs: 0, tokens: 12, costUSD: 1 },
      { bucketStartMs: hour, tokens: 70_000, costUSD: null },
    ],
  },
  errors: ['summary'],
});
const visual = (sections, type) =>
  sections.find((section) => section.visual?.type === type)?.visual;

test('unknown costs stay unavailable and true zero stays zero', () => {
  assert.equal(usageCost(null), 'Unavailable');
  assert.equal(usageCost(0), '$0.00');
  assert.equal(usageNumber(undefined), 'Unavailable');
  assert.equal(usageCompactCost(null), '—');
  assert.equal(usageCompactCost(0), '$0.00');
  assert.equal(usageCompactCost(0.004), '<$0.01');
  assert.equal(usageCompactCost(3.4182), '$3.42');
  assert.equal(usageCompactNumber(1_284_331), '1.28M');
  assert.equal(usageCompactNumber(null), '—');
});

test('totals come from the server timeline as stat tiles, never rebuilt from buckets', () => {
  const stats = visual(usageSections(snapshot), 'stats');
  assert.deepEqual(
    stats.items.map((item) => item.value),
    ['1.28M', '—'],
  );
  assert.equal(stats.items[0].accessibilityValue, '1,284,331');
  assert.equal(stats.items[1].accessibilityValue, 'Unavailable');
});

test('buckets become ordered bars whose summary names the peak', () => {
  const bars = visual(usageSections(snapshot), 'bars');
  assert.deepEqual(
    bars.items.map((item) => item.amount),
    [12, 70_000, 5],
  );
  assert.match(bars.summary, /01:00/);
  assert.match(bars.summary, /70K/);
  assert.match(bars.items[1].detail, /—/);
  assert.deepEqual(
    bars.items.filter((item) => item.axisLabel).map((item) => item.axisLabel),
    ['00:00', '01:00', '02:00'],
  );
  assert.ok(bars.items.every((item) => item.accessibilityLabel));
});

test('the token mix keeps a fixed category order and never invents zero for missing values', () => {
  const mix = visual(usageSections(snapshot), 'mix');
  assert.deepEqual(
    mix.items.map((item) => item.label),
    ['Input', 'Output', 'Cache read', 'Cache write', 'Reasoning'],
  );
  assert.equal(mix.items[0].percent, '30%');
  assert.equal(mix.items[3].value, '0');
  assert.equal(mix.items[4].value, '—');
  assert.equal(mix.items[4].fraction, 0);
});

test('summary-only and empty snapshots show tiles without charts', () => {
  const summaryOnly = usageSections({ ...snapshot, timeline: null });
  assert.equal(visual(summaryOnly, 'bars'), undefined);
  assert.deepEqual(
    visual(summaryOnly, 'stats').items.map((item) => item.value),
    ['99', '$99.00'],
  );
  assert.deepEqual(usageSections(undefined), []);
  assert.throws(() =>
    usageSchema.parse({ ...snapshot, retrievedAt: Infinity }),
  );
});

test('compact numbers do not depend on Intl compact notation, which Hermes ignores', () => {
  const NumberFormat = Intl.NumberFormat;
  Intl.NumberFormat = function (locale, options = {}) {
    const { notation: _notation, ...rest } = options;
    return new NumberFormat(locale, rest);
  };
  try {
    assert.equal(usageCompactNumber(6000), '6K');
    assert.equal(usageCompactNumber(1_284_331), '1.28M');
    assert.equal(usageCompactNumber(950), '950');
    assert.equal(usageCompactNumber(2_500_000_000), '2.5B');
  } finally {
    Intl.NumberFormat = NumberFormat;
  }
});

test('cost becomes a second chart metric only when buckets report it, and missing cost is never a zero bar', () => {
  const bars = visual(usageSections(snapshot), 'bars');
  assert.deepEqual(bars.metrics, ['Tokens', 'Cost']);
  assert.deepEqual(
    bars.items.map((item) => item.cost),
    [1, undefined, 0.5],
  );
  assert.match(bars.costSummary, /00:00/);
  const tokensOnly = visual(
    usageSections({
      ...snapshot,
      timeline: {
        ...snapshot.timeline,
        buckets: snapshot.timeline.buckets.map((bucket) => ({
          ...bucket,
          costUSD: null,
        })),
      },
    }),
    'bars',
  );
  assert.equal(tokensOnly.metrics, undefined);
});

test('long ranges merge adjacent buckets so the chart still spans the whole range', () => {
  const buckets = Array.from({ length: 168 }, (_, index) => ({
    bucketStartMs: index * hour,
    tokens: index === 0 ? 1000 : 1,
    costUSD: index === 1 ? null : 0.01,
  }));
  const bars = visual(
    usageSections({
      ...snapshot,
      range: 'week',
      timeline: { ...snapshot.timeline, endMs: 168 * hour, buckets },
    }),
    'bars',
  );
  assert.ok(bars.items.length <= 90);
  assert.equal(
    bars.items.reduce((sum, item) => sum + item.amount, 0),
    1000 + 167,
  );
  assert.equal(bars.items[0].cost, undefined);
  assert.equal(bars.items.at(-1).id.startsWith('bucket:'), true);
  assert.match(bars.items.find((item) => item.axisLabel).axisLabel, /Jan/);
});
