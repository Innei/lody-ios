import type { HeaderBarButtonItemMenuAction } from 'react-native-screens';
import { t } from '../../lib/i18n/index.ts';

export function runOptionsFailureNotice(error?: string) {
  return error ? t('runOptions.chatUnavailable') : '';
}

export function runOptionsRecoveryAction({
  error,
  loading,
  refresh,
}: {
  error?: string;
  loading: boolean;
  refresh: () => void;
}): HeaderBarButtonItemMenuAction | undefined {
  if (!error) return;
  return {
    type: 'action',
    title: t('runOptions.retry'),
    icon: { type: 'sfSymbol', name: 'arrow.clockwise' },
    disabled: loading,
    onPress: refresh,
  };
}
