import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const ActivityScreen = definePage<{
  workspaceId: string;
  userId: string;
}>({
  id: 'activity',
  title: t('inbox.settings.view.activity'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
