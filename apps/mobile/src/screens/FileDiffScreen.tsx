import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';
export type FileDiffParams = {
  sessionId: string;
  entryId?: string;
  path: string;
};
export const FileDiffScreen = definePage<FileDiffParams>({
  id: 'file-diff',
  title: t('diff.title'),
  native: true,
  panel: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
