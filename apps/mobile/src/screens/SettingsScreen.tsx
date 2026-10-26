import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';

export const SettingsScreen = definePage({
  id: 'settings',
  title: t('tabs.settings'),
  native: true,
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
