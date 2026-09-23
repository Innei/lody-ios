import { t } from '../../lib/i18n/index.ts';

export function quotaError(
  reason: string | undefined,
  fallback: string,
): string {
  if (reason === 'workspace_payment_required')
    return t('send.error.workspacePaymentRequired');
  if (reason === 'free_session_limit_reached')
    return t('send.error.freeSessionLimit');
  if (reason === 'free_session_turn_limit_reached')
    return t('send.error.freeTurnLimit');
  return reason || fallback;
}
