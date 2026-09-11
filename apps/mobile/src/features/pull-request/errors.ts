import { t } from '@/lib/i18n';

export function pullRequestError(code: string) {
  if (/comment_unknown/.test(code)) return t('pr.error.commentUnknown');
  if (/unauthorized|authorization_required/.test(code))
    return t('pr.error.authorization');
  if (/forbidden/.test(code)) return t('pr.error.forbidden');
  if (/not_found/.test(code)) return t('pr.error.notFound');
  if (/rate_limited/.test(code)) return t('pr.error.rateLimit');
  return t('pr.error.unavailable');
}
