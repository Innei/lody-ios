import { t } from '../../i18n/index.ts';

const MAX = 24;

/** The session title comes from the first message, so nobody has to name it up front. */
export function draftTitle(draft: string) {
  const line = draft.trim().split('\n').find(Boolean)?.trim() ?? '';
  if (!line) return t('session.newTitle');
  const clipped = [...line].slice(0, MAX).join('');
  return clipped.length < [...line].length ? `${clipped}…` : clipped;
}
