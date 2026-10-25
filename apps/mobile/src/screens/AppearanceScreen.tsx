import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const AppearanceScreen = definePage({
  id: 'appearance-settings',
  title: t('settings.appearance.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
