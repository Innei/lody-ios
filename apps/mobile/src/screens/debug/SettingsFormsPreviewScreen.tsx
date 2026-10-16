import { NativeGroupedList } from '@lody-ios/kit';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import { QuickReplyEditorScreen } from '../QuickReplyEditorScreen';
import { RemoteSettingEditorScreen } from '../RemoteSettingEditorScreen';
import { WorkspaceEditorScreen } from '../WorkspaceEditorScreen';

function Preview() {
  const { present } = usePageRuntime();
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      sections={[
        {
          id: 'forms',
          rows: ['machine', 'agent', 'mcp', 'workspace', 'quick-reply'].map(
            (kind) => ({ id: `form-${kind}`, title: kind, action: true }),
          ),
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        const kind = id.slice('form-'.length);
        if (kind === 'workspace') {
          void present(WorkspaceEditorScreen, {
            workspaceId: 'settings-forms-preview',
            name: 'Studio Workspace',
            color: '#2155CC',
          });
        }
        if (kind === 'quick-reply') {
          void present(QuickReplyEditorScreen, {
            item: {
              id: 'preview',
              label: 'Review',
              message: 'Review the changes.',
            },
          });
        }
        if (kind === 'machine' || kind === 'agent' || kind === 'mcp') {
          void present(
            RemoteSettingEditorScreen,
            {
              workspaceId: 'settings-forms-preview',
              item: {
                kind,
                id: 'preview',
                name: 'Studio',
                prompt: 'Keep changes focused.',
                enabledByDefault: true,
              },
              service: async () => [],
            },
            {
              sheetAllowedDetents: kind === 'agent' ? [1] : [0.5, 1],
              sheetGrabberVisible: kind !== 'agent',
            },
          );
        }
      }}
    />
  );
}

export const SettingsFormsPreviewScreen = definePage({
  id: 'settings-forms-preview',
  title: 'Settings form backgrounds',
  Component: Preview,
  presentation: { headerVariant: 'transparent' },
});
