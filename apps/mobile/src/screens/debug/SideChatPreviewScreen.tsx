import { useState, useSyncExternalStore } from 'react';
import { Alert, View as RNView } from 'react-native';
import { NativeChat, NativeNavigationHeader } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';
import { t } from '@/lib/i18n/index.ts';
import { conversationFixture } from './conversationFixture';

function View() {
  const { params, cancel } = usePageRuntime<{ id: string }>();
  const colors = usePalette();
  const fixture = useSyncExternalStore(
    conversationFixture.subscribe,
    conversationFixture.get,
  );
  const [clearDraftToken, setClearDraftToken] = useState(0);
  const root = fixture.sessions.find((s) => s.id === 'main');
  const entriesJSON = JSON.stringify(fixture.entries[params.id] ?? []);
  const openProcess = useProcessSheet(entriesJSON, () => {});
  const remove = () =>
    Alert.alert(t('conversations.deleteTitle'), '', [
      { text: t('common.cancel'), style: 'cancel' },
      {
        text: t('conversations.deleteSideChat'),
        style: 'destructive',
        onPress: () => {
          conversationFixture.remove(params.id);
          cancel();
        },
      },
    ]);
  return (
    <RNView style={{ flex: 1, backgroundColor: colors.reading }}>
      <NativeNavigationHeader
        items={[
          {
            type: 'menu',
            icon: { type: 'sfSymbol', name: 'ellipsis' },
            accessibilityLabel: t('common.more'),
            menu: {
              items: [
                {
                  type: 'action',
                  title: t('conversations.deleteSideChat'),
                  icon: { type: 'sfSymbol', name: 'trash' },
                  destructive: true,
                  onPress: remove,
                },
              ],
            },
          },
        ]}
      />
      <NativeChat
        style={{ flex: 1 }}
        navigationTitle={t('conversations.sideChat')}
        navigationSubtitle={root?.title ?? ''}
        entriesJSON={entriesJSON}
        composerJSON={JSON.stringify({
          editable: true,
          canSend: true,
          sending: false,
          notice: '',
          reconnect: false,
          connection: '',
          placeholder: t('conversations.sideChatPlaceholder'),
        })}
        clearDraftToken={clearDraftToken}
        emptyText=""
        onSend={({ nativeEvent }) => {
          conversationFixture.send(params.id, nativeEvent.text);
          setClearDraftToken((n) => n + 1);
        }}
        onActivityPress={({ nativeEvent }) =>
          openProcess(nativeEvent.entryId, nativeEvent.processStartId)
        }
        onReconnect={() => {}}
      />
    </RNView>
  );
}

export const SideChatPreviewScreen = definePage<{ id: string }>({
  id: 'side-chat-preview',
  title: 'Side Chat',
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from the conversations preview');
  },
  presentation: { style: 'pageSheet', headerVariant: 'glass' },
});
