import { useEffect, useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { NativeChat, type SessionPreviewReply } from '@lody-ios/kit';
import { useSessionPreview } from '@/hooks/screens/useSessionPreview';
import { composerContext } from '@/hooks/screens/composerContext';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { Button } from '@/ui/Button';

const url = 'https://fixture.trycloudflare.com/?__lody_preview_token=fixture';
const simulatorChip = {
  label: 'iPhone 17',
  symbol: 'iphone',
  state: 'ready',
  accessibilityLabel: 'Open Simulator preview',
  actions: [],
};

function Fixture({ onReset }: { onReset: () => void }) {
  const colors = usePalette();
  const [summary, setSummary] = useState({
    label: 'localhost:52920',
    active: true,
  });
  const [combined, setCombined] = useState(false);
  const [calls, setCalls] = useState({
    create: 0,
    revoke: 0,
    open: 0,
    copy: 0,
  });
  const pending = useRef<((reply: SessionPreviewReply) => void) | undefined>(
    undefined,
  );
  const services = useRef({
    sessionPreview: async (
      _sessionId: string,
      action: 'create' | 'revoke' = 'create',
    ) => {
      setCalls((old) => ({ ...old, [action]: old[action] + 1 }));
      if (action === 'create') return { url };
      return new Promise<SessionPreviewReply>((resolve) => {
        pending.current = resolve;
      });
    },
    openPreviewBrowser: async (_url: string) => {
      if (_url !== url) throw new Error('Unexpected preview URL');
      setCalls((old) => ({ ...old, open: old.open + 1 }));
    },
    copyText: async (_url: string) => {
      if (_url !== url) throw new Error('Unexpected preview URL');
      setCalls((old) => ({ ...old, copy: old.copy + 1 }));
    },
  }).current;
  const preview = useSessionPreview('preview-close-fixture', summary, services);
  useEffect(
    () => () => {
      pending.current?.({ error: 'cancelled' });
    },
    [],
  );
  const context = composerContext([
    {
      chip: preview.chip,
      onChip: preview.onPreview,
      openTitle: (chip) => chip.accessibilityLabel,
    },
    {
      chip: combined ? simulatorChip : undefined,
      onChip: () => {},
      openTitle: (chip) => chip.accessibilityLabel,
    },
  ]);
  function complete(failed: boolean) {
    if (!pending.current) return;
    if (!failed) setSummary((old) => ({ ...old, active: false }));
    pending.current(
      failed
        ? { error: 'failed', message: 'The machine did not stop sharing.' }
        : {},
    );
    pending.current = undefined;
  }
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <View
        style={{
          paddingTop: 100,
          paddingHorizontal: 16,
          flexDirection: 'row',
          flexWrap: 'wrap',
          gap: 12,
        }}
      >
        <Button testID="preview-reset" onPress={onReset}>
          Reset
        </Button>
        <Button testID="preview-succeed" onPress={() => complete(false)}>
          Succeed
        </Button>
        <Button testID="preview-fail" onPress={() => complete(true)}>
          Fail
        </Button>
        <Button
          testID="preview-candidate"
          onPress={() => setSummary((old) => ({ ...old, active: false }))}
        >
          Candidate only
        </Button>
        <Button
          testID="preview-reactivate"
          onPress={() => setSummary((old) => ({ ...old, active: true }))}
        >
          Share again
        </Button>
        <Button
          testID="preview-target"
          onPress={() =>
            setSummary({ label: 'localhost:52921', active: false })
          }
        >
          New target
        </Button>
        <Button
          testID="preview-combine"
          onPress={() => setCombined((old) => !old)}
        >
          Simulator
        </Button>
      </View>
      <Text
        testID="preview-fixture-status"
        style={{ color: colors.label, padding: 16 }}
      >
        {`Create: ${calls.create} · Revoke: ${calls.revoke} · Open: ${calls.open} · Copy: ${calls.copy}`}
      </Text>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON="[]"
        composerJSON={JSON.stringify({
          preview: context.chip,
          editable: true,
          canSend: false,
          sending: false,
          notice: '',
          reconnect: false,
          placeholder: 'Message',
          quickReplies: [
            { id: 'continue', label: 'Continue', message: 'Continue' },
          ],
        })}
        clearDraftToken={0}
        emptyText="Preview close verification"
        onPreview={({ nativeEvent }) => context.onPreview(nativeEvent.action)}
        onSend={() => {}}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </View>
  );
}

function Content() {
  const [revision, setRevision] = useState(0);
  return (
    <Fixture key={revision} onReset={() => setRevision((old) => old + 1)} />
  );
}

export const PreviewClosePreviewScreen = definePage({
  id: 'preview-close-preview',
  title: 'Preview Close',
  Component: Content,
  parseRouteParams: () => undefined,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
