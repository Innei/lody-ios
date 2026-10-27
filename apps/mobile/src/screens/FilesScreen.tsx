import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';
export type FilesParams = {
  workspaceId: string;
  sessionId: string;
  userId: string;
  path: string;
  title: string;
};
export const FilesScreen = definePage<FilesParams>({
  id: 'files',
  title: t('files.title'),
  native: true,
  panel: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
