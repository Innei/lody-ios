import { shortcutCommand } from '@lody-ios/kit';
import type { MentionCatalog } from '@lody/cloud-runtime/models/mentions';
import {
  parsePromptShortcut,
  parseShortcutIndex,
  type PromptShortcutRequest,
  type PromptShortcutResult,
} from '@lody/cloud-runtime/models/prompt-shortcuts';
import { t } from '@/lib/i18n';

export type PromptShortcutService = (
  request: PromptShortcutRequest,
) => Promise<PromptShortcutResult>;
const reasons = [
  'permission_denied',
  'project_mismatch',
  'machine_mismatch',
  'provider_mismatch',
  'machine_offline',
  'missing_scope',
  'scope_mismatch',
  'dependency_missing',
  'dependencies_unverified',
  'invalid_template',
  'invalid_ranges',
  'size_limit',
  'conflict',
  'revision_pending',
  'not_found',
  'offline',
  'write_unknown',
  'unavailable',
] as const;
export function shortcutErrorMessage(
  error: unknown,
  fallback: 'loadFailed' | 'saveFailed' = 'loadFailed',
) {
  const reason = reasons.find((reason) =>
    String(error).includes(`shortcut_${reason}`),
  );
  return t(`settings.promptShortcuts.${reason ?? fallback}`);
}
export function localizeShortcutCatalog(
  catalog: MentionCatalog,
): MentionCatalog {
  return {
    ...catalog,
    items: catalog.items.map((item) => ({
      ...item,
      ...(item.disabledReason
        ? { disabledReason: shortcutErrorMessage(item.disabledReason) }
        : {}),
    })),
  };
}
export const requestPromptShortcuts: PromptShortcutService = async (
  request,
) => {
  const value: unknown = JSON.parse(
    await shortcutCommand(JSON.stringify(request)),
  );
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error('shortcut_invalid_template');
  const result = value as Record<string, unknown>;
  if (!Array.isArray(result.entries))
    throw new Error('shortcut_invalid_template');
  return {
    entries: result.entries.map(parseShortcutIndex),
    ...(result.item ? { item: parsePromptShortcut(result.item) } : {}),
  };
};
