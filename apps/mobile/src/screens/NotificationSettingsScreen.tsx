import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const NotificationSettingsScreen = definePage<Record<string, never>>({
  id: 'notification-settings',
  title: t('settings.notifications.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
