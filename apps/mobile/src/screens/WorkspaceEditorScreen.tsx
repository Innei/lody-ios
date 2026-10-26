import { definePage } from '@/lib/presentation';
import { t } from '@/lib/i18n';

export const workspaceEditActionId = 'workspace:edit';

type Params = {
  workspaceId: string;
  name: string;
  image?: string;
  color: string;
};

export const WorkspaceEditorScreen = definePage<Params>({
  id: 'workspace-editor',
  title: t('workspace.edit.title'),
  native: true,
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.5],
  },
});
