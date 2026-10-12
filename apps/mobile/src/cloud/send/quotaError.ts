import { t, type TranslationKey } from '../../lib/i18n/index.ts';

const shortcutErrors: Partial<Record<string, TranslationKey>> = {
  shortcut_permission_denied: 'settings.promptShortcuts.permission_denied',
  shortcut_project_mismatch: 'settings.promptShortcuts.project_mismatch',
  shortcut_machine_mismatch: 'settings.promptShortcuts.machine_mismatch',
  shortcut_provider_mismatch: 'settings.promptShortcuts.provider_mismatch',
  shortcut_machine_offline: 'settings.promptShortcuts.machine_offline',
  shortcut_missing_scope: 'settings.promptShortcuts.missing_scope',
  shortcut_scope_mismatch: 'settings.promptShortcuts.scope_mismatch',
  shortcut_dependency_missing: 'settings.promptShortcuts.dependency_missing',
  shortcut_dependencies_unverified:
    'settings.promptShortcuts.dependencies_unverified',
  shortcut_invalid_template: 'settings.promptShortcuts.invalid_template',
  shortcut_invalid_ranges: 'settings.promptShortcuts.invalid_ranges',
  shortcut_size_limit: 'settings.promptShortcuts.size_limit',
  shortcut_conflict: 'settings.promptShortcuts.conflict',
  shortcut_revision_pending: 'settings.promptShortcuts.revision_pending',
  shortcut_not_found: 'settings.promptShortcuts.not_found',
  shortcut_offline: 'settings.promptShortcuts.offline',
  shortcut_write_unknown: 'settings.promptShortcuts.write_unknown',
  shortcut_unavailable: 'settings.promptShortcuts.unavailable',
};

export function quotaError(
  reason: string | undefined,
  fallback: string,
): string {
  const shortcut = shortcutErrors[reason ?? ''];
  if (shortcut) return t(shortcut);
  if (
    [
      'invalid_config_options',
      'invalid_mcp_selection',
      'mcp_selection_unavailable',
      'invalid_role_selection',
      'role_unavailable',
      'role_revision_changed',
      'role_binding_changed',
      'role_config_changed',
      'worktree_unavailable',
    ].includes(reason ?? '')
  )
    return t('runOptions.selectionChanged');
  if (reason === 'workspace_payment_required')
    return t('send.error.workspacePaymentRequired');
  if (reason === 'free_session_limit_reached')
    return t('send.error.freeSessionLimit');
  if (reason === 'free_session_turn_limit_reached')
    return t('send.error.freeTurnLimit');
  return reason || fallback;
}
