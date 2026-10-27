import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const AppIconScreen = definePage({
  id: 'app-icon',
  title: t('settings.appearance.appIcon'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
