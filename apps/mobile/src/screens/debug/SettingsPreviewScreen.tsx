import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const SettingsPreviewScreen = definePage({
  id: 'settings-preview',
  title: t('settings.remote.title'),
  native: true,
  presentation: { headerVariant: 'transparent' },
});
