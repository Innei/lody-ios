import { t } from '../../lib/i18n/index.ts';

export function quotaError(
  reason: string | undefined,
  fallback: string,
): string {
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
