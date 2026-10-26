import { definePage } from '@/lib/presentation';
import { t } from '../../lib/i18n/index.ts';

export const FileDiffPreviewScreen = definePage({
  id: 'file-diff-preview',
  title: 'Native Diff Fixture',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

export const WorkspaceChangesPreviewScreen = definePage({
  id: 'workspace-changes-preview',
  title: t('workspaceChanges.title'),
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

export const FileContentPreviewScreen = definePage({
  id: 'file-content-preview',
  title: 'Native File Fixture',
  native: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
