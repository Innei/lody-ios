import { definePage } from '@/lib/presentation';
import { t } from '../../lib/i18n/index.ts';

export const DirectoryPreviewScreen = definePage({
  id: 'directory-preview',
  title: t('directory.title'),
  native: true,
  presentation: { headerVariant: 'transparent' },
});
