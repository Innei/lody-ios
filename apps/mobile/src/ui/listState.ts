import { t } from '../i18n/index.ts';

export type ListStateInput = {
  loading?: boolean;
  filtered?: boolean;
  connected?: boolean;
};

/** One placeholder for loading, empty search, offline and first run. */
export function listPlaceholder({
  loading = false,
  filtered = false,
  connected = true,
}: ListStateInput) {
  if (loading) return t('sessions.placeholder.loading');
  if (filtered) return t('sessions.placeholder.noMatch');
  if (!connected) return t('sessions.placeholder.offline');
  return t('sessions.placeholder.empty');
}

export function searchPlaceholder({
  signedIn,
  query,
  loading,
  connected,
}: {
  signedIn: boolean;
  query: string;
  loading: boolean;
  connected: boolean;
}) {
  if (!signedIn) return t('search.placeholder.signedOut');
  if (!query.trim()) return t('search.placeholder.idle');
  if (loading) return t('search.placeholder.loading');
  if (!connected) return t('search.placeholder.offline');
  return t('search.placeholder.noMatch');
}
