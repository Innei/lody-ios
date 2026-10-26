import { definePage } from '@/lib/presentation';
import { t } from '../../lib/i18n/index.ts';

export const ProjectHistoryPreviewScreen = definePage({
  id: 'project-history-preview',
  title: t('settings.history.title'),
  native: true,
  presentation: { headerVariant: 'transparent' },
});
