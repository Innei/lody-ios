import type { NativeGroupedListProps } from '@lody-ios/kit';
import { t } from '../../lib/i18n/index.ts';
import { relativeTime } from '../../ui/time.ts';

export type ListState = {
  loading: boolean;
  notice?: NativeGroupedListProps['notice'];
  unavailable?: NativeGroupedListProps['unavailable'];
};

export function listState({
  title,
  hasData,
  loading = false,
  failed = false,
  offline = false,
  unconfirmed = false,
  partial,
  syncedAt,
  now = Date.now(),
}: {
  title: string;
  hasData: boolean;
  loading?: boolean;
  failed?: boolean;
  offline?: boolean;
  unconfirmed?: boolean;
  partial?: string;
  syncedAt?: number;
  now?: number;
}): ListState {
  const retry = {
    actionSymbol: 'arrow.clockwise',
    actionLabel: t('settings.state.refresh'),
  };
  if (unconfirmed)
    return {
      loading: false,
      notice: {
        symbol: 'exclamationmark.triangle',
        text: t('settings.state.unconfirmed'),
        tint: 'warning',
        ...retry,
      },
    };
  if (failed && !hasData)
    return {
      loading: false,
      unavailable: {
        symbol: 'wifi.exclamationmark',
        title,
        message: t('settings.state.unavailableMessage'),
        actionTitle: t('settings.state.tryAgain'),
      },
    };
  if (failed) {
    let text = t('settings.state.stale');
    if (syncedAt !== undefined)
      text = t('settings.state.staleAt', {
        time: relativeTime(syncedAt, now),
      });
    return {
      loading: false,
      notice: {
        symbol: 'exclamationmark.icloud',
        text,
        tint: 'warning',
        ...retry,
      },
    };
  }
  if (partial)
    return {
      loading: false,
      notice: {
        symbol: 'exclamationmark.triangle',
        text: partial,
        tint: 'warning',
        ...retry,
      },
    };
  if (offline && hasData)
    return {
      loading: false,
      notice: { symbol: 'icloud.slash', text: t('settings.state.offline') },
    };
  return { loading: loading && !hasData };
}
