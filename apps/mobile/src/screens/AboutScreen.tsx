import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';

export const AboutScreen = definePage({
  id: 'about',
  title: t('settings.section.about'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
