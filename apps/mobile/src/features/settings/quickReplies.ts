import type { QuickReply } from '../../models/settings.ts';

export function parseQuickReplies(json: string): QuickReply[] | null {
  try {
    const value: unknown = JSON.parse(json);
    if (!Array.isArray(value)) return null;
    const ids = new Set<string>();
    return value.filter((item): item is QuickReply => {
      if (
        !item ||
        typeof item.id !== 'string' ||
        !item.id ||
        ids.has(item.id) ||
        typeof item.label !== 'string' ||
        !item.label.trim() ||
        item.label.length > 40 ||
        typeof item.message !== 'string' ||
        !item.message.trim() ||
        item.message.length > 32000
      )
        return false;
      ids.add(item.id);
      return true;
    });
  } catch {
    return null;
  }
}

export function reorderQuickReplies(items: QuickReply[], ids: string[]) {
  if (ids.length !== items.length || new Set(ids).size !== items.length)
    return items;
  const byId = new Map(items.map((item) => [item.id, item]));
  if (ids.some((id) => !byId.has(id))) return items;
  return ids.map((id) => byId.get(id)!);
}
