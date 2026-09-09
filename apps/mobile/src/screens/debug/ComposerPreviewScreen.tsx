import { PickerScreen } from '../PickerScreen';
import { ComposerSheet } from '@/ui/ComposerSheet';
import { Button } from '@/ui/Button';
import { useRef, useState } from 'react';
import { Text, View as RNView } from 'react-native';
import { NativeChat, NativeComposer } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

type Params = { host: 'chat' | 'sheet'; outcome: 'success' | 'failure' };

// Keep the request pending until the driver completes it: no race against CI speed.
function View() {
  const { params, push } = usePageRuntime<Params>();
  const colors = usePalette();
  const [restoreDraftToken, setRestoreDraftToken] = useState(0);
  const [clearDraftToken, setClearDraftToken] = useState(0);
  const [sending, setSending] = useState(false);
  const [count, setCount] = useState(0);
  const busy = useRef(false);
  const props = {
    composerJSON: JSON.stringify({
      editable: !sending,
      canSend: !sending,
      sending,
      notice: '',
      reconnect: false,
      placeholder: '离线草稿验收',
    }),
    composerOptionsJSON: JSON.stringify({
      modelId: 'gpt-5.6-sol',
      models: [{ id: 'gpt-5.6-sol', title: 'GPT-5.6 Sol' }],
      effort: 'high',
      efforts: [{ id: 'high', title: 'High' }],
    }),
    restoreDraftToken,
    onSend: () => {
      busy.current = true;
      setSending(true);
      setCount((value) => value + 1);
    },
  };
  return (
    <RNView
      style={{
        flex: 1,
        backgroundColor:
          params.host === 'chat' ? colors.background : 'transparent',
      }}
    >
      <RNView
        style={{
          marginTop: params.host === 'chat' ? 104 : 56,
          paddingHorizontal: 16,
        }}
      >
        <Button
          testID="complete-request"
          onPress={() => {
            if (!busy.current) return;
            if (params.outcome === 'failure')
              setRestoreDraftToken((value) => value + 1);
            else setClearDraftToken((value) => value + 1);
            setSending(false);
            busy.current = false;
          }}
        >
          Complete Request
        </Button>
      </RNView>
      <Text
        testID="composer-result"
        style={{ color: colors.label, padding: 16 }}
      >{`Requests: ${count}`}</Text>
      {params.host === 'chat' ? (
        <NativeChat
          {...props}
          style={{ flex: 1 }}
          entriesJSON="[]"
          clearDraftToken={clearDraftToken}
          initialAttachmentsJSON={JSON.stringify([
            {
              id: 'fixture-file',
              name: 'fixture.txt',
              uri: 'file:///tmp/lody-ui-fixture.txt',
              kind: 'file',
            },
          ])}
          emptyText="离线输入框验收"
          onActivityPress={() => {}}
          onReconnect={() => {}}
        />
      ) : (
        <ComposerSheet
          sections={Array.from({ length: 8 }, (_, index) => ({
            id: `group-${index}`,
            rows: [
              {
                id: `option-${index}`,
                title: `Option ${index + 1}`,
                subtitle: 'Session configuration',
                image: 'folder',
                action: true,
                navigates: true,
              },
            ],
          }))}
          onRowPress={() => {
            if (busy.current) return;
            void push(PickerScreen, {
              title: 'Sheet options',
              options: [
                { id: 'sheet-choice-1', title: 'First option' },
                { id: 'sheet-choice-2', title: 'Second option' },
              ],
            });
          }}
        >
          <NativeComposer {...props} scrollEdge />
        </ComposerSheet>
      )}
    </RNView>
  );
}
export const ComposerPreviewScreen = definePage<Params>({
  id: 'composer-preview',
  title: '输入框验收',
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from Debug');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.62, 1],
    sheetGrabberVisible: true,
  },
});
