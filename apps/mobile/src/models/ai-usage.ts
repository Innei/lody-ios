import { z } from 'zod';
const count = z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
const date = count.max(8640000000000000);
const fee = z.number().finite().nonnegative().nullable();
const breakdown = z.object({
  inputTokens: count.nullable(),
  outputTokens: count.nullable(),
  cacheReadInputTokens: count.nullable(),
  cacheCreationInputTokens: count.nullable(),
  reasoningOutputTokens: count.nullable(),
});
const totals = z.object({
  tokens: count,
  costUSD: fee,
  breakdown: breakdown.optional(),
});
export const usageRanges = ['day', 'week', 'month', 'total'] as const;
export type UsageRange = (typeof usageRanges)[number];
export const usageSchema = z.object({
  workspaceId: z.string().min(1),
  range: z.enum(usageRanges),
  retrievedAt: date,
  summary: z.object({ totals }).nullable(),
  timeline: z
    .object({
      totals,
      startMs: date,
      endMs: date,
      bucketSizeMs: count,
      buckets: z
        .array(z.object({ bucketStartMs: date, tokens: count, costUSD: fee }))
        .max(10000),
    })
    .nullable(),
  errors: z.array(z.enum(['summary', 'timeline'])),
});
export type UsageSnapshot = z.infer<typeof usageSchema>;
export type UsageRequest = {
  page: 'usage';
  action: 'list';
  workspaceId: string;
  range: UsageRange;
};
export type UsageService = (request: UsageRequest) => Promise<UsageSnapshot>;
