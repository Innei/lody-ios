import { definePage } from '@/lib/presentation';
import { t } from '../../lib/i18n/index.ts';

export const ProjectPreviewScreen = definePage<{
  projectId?: string;
  offline?: boolean;
}>({
  id: 'project-preview',
  title: t('project.title'),
  native: true,
  presentation: { headerVariant: 'transparent' },
});
