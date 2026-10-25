import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';
import type { SettingsScopeParams } from './MemorySettingsScreen';

export const PublishedSharesScreen = definePage<SettingsScopeParams>({
  id: 'published-shares',
  title: t('settings.shares.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
