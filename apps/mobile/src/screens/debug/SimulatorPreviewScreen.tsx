import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { useSessionPreview } from '@/hooks/screens/useSessionPreview';

const service = {
  sessionPreview: async () => ({ url: 'lody-simulator-fixture://stream' }),
  previewSimulators: async () => [
    { udid: 'ui-verify-simulator', name: 'iPhone Simulator' },
    { udid: 'ui-verify-simulator-two', name: 'Second Simulator' },
  ],
};

function View() {
  const preview = useSessionPreview(
    'ui-verify-simulator-session',
    { label: 'Simulator', active: true },
    service,
  );
  return (
    <NativeChat
      style={{ flex: 1 }}
      navigationTitle="Simulator preview"
      entriesJSON={JSON.stringify([
        {
          id: 'simulator-question',
          role: 'user',
          status: 'completed',
          finished: true,
          items: [
            {
              itemId: 'text',
              type: 'text',
              text: 'Keep the preview running while we chat.',
            },
          ],
        },
        {
          id: 'simulator-answer',
          role: 'assistant',
          status: 'completed',
          finished: true,
          items: [
            {
              itemId: 'text',
              type: 'text',
              text: 'Open the Simulator, then return to this conversation.\n\nWe can keep discussing the screen while the preview runs. Drag it to either side and continue typing here.\n\nThe conversation stays underneath the floating preview, so we can compare the layout and its live changes together.',
            },
          ],
        },
      ])}
      simulatorPreviewJSON={preview.simulatorPreviewJSON}
      composerJSON={JSON.stringify({
        editable: true,
        canSend: true,
        sending: false,
        notice: '',
        reconnect: false,
        placeholder: 'Message',
        preview: preview.chip,
      })}
      clearDraftToken={0}
      emptyText=""
      onPreview={({ nativeEvent }) => preview.onPreview(nativeEvent.action)}
      onSend={() => {}}
      onReconnect={() => {}}
      onActivityPress={() => {}}
    />
  );
}

export const SimulatorPreviewScreen = definePage({
  id: 'simulator-preview',
  title: 'Simulator preview',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
