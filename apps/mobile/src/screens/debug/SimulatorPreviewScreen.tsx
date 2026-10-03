import { useEffect, useState } from 'react';
import { NativeChat, type IosSimulatorDevice } from '@lody-ios/kit';
import {
  setSimulatorControl,
  simulatorControl,
  stopSimulator,
} from '@/features/simulator/operations';
import { definePage } from '@/lib/presentation';
import { useSessionSimulator } from '@/hooks/screens/useSessionSimulator';

const SESSION = 'ui-verify-simulator-session';
const device = (udid: string, name: string): IosSimulatorDevice => ({
  udid,
  name,
  runtime: 'iOS 27.0',
  deviceType: 'iPhone 18 Pro',
  state: 'Booted',
  available: true,
  occupancy: 'available',
});
const devices = [
  device('ui-verify-simulator', 'iPhone Simulator'),
  device('ui-verify-simulator-two', 'Second Simulator'),
];
let starts = 0;
const fixture: typeof simulatorControl = async (
  _workspace,
  _session,
  command,
) => {
  if (command.action === 'list') return { success: true, devices };
  if (command.action !== 'start') return { success: true };
  starts += 1;
  return {
    success: true,
    preview: {
      operationId: `fixture-${starts}`,
      udid: command.udid,
      phase: 'ready',
      transport: 'remote',
      viewerUrl: 'lody-simulator-fixture://stream',
    },
  };
};

function View() {
  const [ready, setReady] = useState(false);
  useEffect(() => {
    setSimulatorControl(fixture);
    void stopSimulator(SESSION).then(() => setReady(true));
    return () => setSimulatorControl();
  }, []);
  const simulator = useSessionSimulator('ui-verify', SESSION, 'available');
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
      titleMenuJSON={JSON.stringify(ready ? [simulator.titleItem] : [])}
      onTitleMenu={() => void simulator.open()}
      simulatorPreviewJSON={simulator.previewJSON}
      composerJSON={JSON.stringify({
        editable: true,
        canSend: true,
        sending: false,
        notice: '',
        reconnect: false,
        placeholder: 'Message',
      })}
      clearDraftToken={0}
      emptyText=""
      onPreview={({ nativeEvent }) => simulator.onPreview(nativeEvent.action)}
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
