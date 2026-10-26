import { definePage } from '@/lib/presentation';
import { t } from '../lib/i18n/index.ts';

export const ProjectHistoryScreen = definePage({
  id: 'project-history',
  title: t('settings.history.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
