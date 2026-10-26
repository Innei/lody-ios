import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const MachineSettingsPreviewScreen = definePage({
  id: 'machine-settings-preview',
  title: t('settings.remote.machine'),
  native: true,
  presentation: { headerVariant: 'transparent' },
});
