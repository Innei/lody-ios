import { usageSchema } from '../../src/models/ai-usage.ts';
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  usageSections,
  usageCost,
  usageNumber,
} from '../../src/features/settings/ai-usage.ts';
import { setLocale } from '../../src/lib/i18n/index.ts';
setLocale('en');
test('unknown costs stay unavailable, true zero stays zero and server timeline totals are not reconstructed from buckets', () => {
  assert.equal(usageCost(null), 'Unavailable');
  assert.equal(usageCost(0), '$0.00');
  assert.equal(usageCost(0.00000001), '<$0.000001');
  assert.equal(usageNumber(undefined), 'Unavailable');
  const snapshot = usageSchema.parse({
    workspaceId: 'w',
    range: 'day',
    retrievedAt: 1000,
    summary: { totals: { tokens: 99, costUSD: 99 } },
    timeline: {
      totals: { tokens: 12500, costUSD: null },
      startMs: 0,
      endMs: 1000,
      bucketSizeMs: 1000,
      buckets: [{ bucketStartMs: 0, tokens: 12, costUSD: 1 }],
    },
    errors: ['summary'],
  });
  const rows = usageSections(snapshot).flatMap((section) => section.rows);
  assert.equal(rows.find((row) => row.id === 'usage-tokens').value, '12,500');
  assert.equal(
    rows.find((row) => row.id === 'usage-cost').value,
    'Unavailable',
  );
  assert.equal(rows.find((row) => row.id === 'bucket:0').value, '$1.00');
  assert.throws(() =>
    usageSchema.parse({ ...snapshot, retrievedAt: Infinity }),
  );
  const missing = usageSections(undefined).flatMap((section) => section.rows);
  assert.ok(missing.every((row) => row.value === 'Unavailable'));
});
