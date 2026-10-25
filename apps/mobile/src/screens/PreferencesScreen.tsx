import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';

export const PreferencesScreen = definePage({
  id: 'preferences',
  title: t('settings.preferences.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
