import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export type SettingsScopeParams = { userId: string; workspaceId: string };

export const MemorySettingsScreen = definePage<SettingsScopeParams>({
  id: 'memory-settings',
  title: t('settings.memory.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
