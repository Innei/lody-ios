import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const ProjectScreen = definePage<{ projectId: string }>({
  id: 'project',
  title: t('project.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
