import {
  FREE_SESSION_TURN_LIMIT,
  FREE_SESSION_TURN_WARNING_REMAINING,
} from '../../models/billing';
import { t, tp } from '../../lib/i18n/index.ts';

export function freeTurnNotice(
  count: number | undefined,
  tier: string | undefined,
) {
  if (
    tier !== 'free' ||
    count === undefined ||
    !Number.isInteger(count) ||
    count < FREE_SESSION_TURN_LIMIT - FREE_SESSION_TURN_WARNING_REMAINING
  )
    return '';
  const remaining = FREE_SESSION_TURN_LIMIT - count;
  if (remaining <= 0) return t('chat.composer.freeTurnLimit');
  return tp('chat.composer.freeTurnsRemaining', remaining, { remaining });
}
