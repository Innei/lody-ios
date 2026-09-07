import type { EntrySummary, ItemSummary } from './types.ts';

export type ChangedFile = {
  path: string;
  add: number;
  del: number;
  status: 'M' | 'A' | 'D';
};

const READ_KINDS = new Set(['read', 'search']);
const KIND_STATUS: Record<string, ChangedFile['status']> = {
  delete: 'D',
  write: 'A',
};
type Tool = Extract<ItemSummary, { type: 'tool_call' }>;

export function changedFiles(entry: EntrySummary): ChangedFile[] {
  const files = new Map<string, ChangedFile>();
  const recorded = new Set((entry.fileDiffs ?? []).map((file) => file.path));
  for (const diff of entry.fileDiffs ?? [])
    files.set(diff.path, {
      path: diff.path,
      add: diff.add,
      del: diff.del,
      status: 'M',
    });
  for (const item of entry.items) {
    if (item.type !== 'tool_call') continue;
    const tool = item as Tool;
    if (!tool.path || READ_KINDS.has(tool.kind)) continue;
    if (recorded.has(tool.path)) continue;
    const status = KIND_STATUS[tool.kind] ?? 'M';
    const existing = files.get(tool.path);
    if (existing) {
      existing.add += tool.added ?? 0;
      existing.del += tool.removed ?? 0;
      if (status === 'D') existing.status = 'D';
    } else {
      files.set(tool.path, {
        path: tool.path,
        add: tool.added ?? 0,
        del: tool.removed ?? 0,
        status,
      });
    }
  }
  return [...files.values()];
}
