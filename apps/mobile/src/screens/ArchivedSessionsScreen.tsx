import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const ArchivedSessionsScreen = definePage({
  id: 'archived-sessions',
  title: t('settings.archived.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
