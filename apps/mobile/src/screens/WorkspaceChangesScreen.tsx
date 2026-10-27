import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';
export type WorkspaceChangesParams = { sessionId: string };
export const WorkspaceChangesScreen = definePage<WorkspaceChangesParams>({
  id: 'workspace-changes',
  title: t('workspaceChanges.title'),
  native: true,
  panel: true,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
