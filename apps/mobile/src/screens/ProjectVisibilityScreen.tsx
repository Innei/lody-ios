import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const ProjectVisibilityScreen = definePage({
  id: 'project-visibility',
  title: t('settings.projects.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
