import { definePage } from '@/lib/presentation';
import { t } from '../../lib/i18n/index.ts';

export const ActivityPreviewScreen = definePage<{ scenario?: string }>({
  id: 'activity-preview',
  title: t('inbox.settings.view.activity'),
  native: true,
  presentation: { headerVariant: 'transparent' },
});
