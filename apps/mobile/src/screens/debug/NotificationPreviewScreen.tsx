import { definePage } from '@/lib/presentation';

export const NotificationPreviewScreen = definePage<Record<string, never>>({
  id: 'notification-preview',
  title: '通知验收',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
