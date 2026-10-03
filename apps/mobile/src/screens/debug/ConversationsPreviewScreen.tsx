import { useEffect, useState, useSyncExternalStore } from 'react';
import { Alert, View as RNView } from 'react-native';
import { NativeChat, NativeNavigationHeader, showToast } from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';
import { t } from '@/lib/i18n/index.ts';
import {
  useSessionConversations,
  type ConversationService,
} from '@/hooks/screens/useSessionConversations';
import { conversationFixture } from './conversationFixture';
import { SideChatPreviewScreen } from './SideChatPreviewScreen';

const delay = (ms: number) => new Promise((done) => setTimeout(done, ms));
const offlineReason = 'MacBook Pro is offline';
const suggestions = [
  'conversations.draft.review',
  'conversations.draft.summarize',
  'conversations.draft.simplify',
] as const;

export function useConversationFixture() {
  return useSyncExternalStore(
    conversationFixture.subscribe,
    conversationFixture.get,
  );
}

function View() {
  const colors = usePalette();
  const fixture = useConversationFixture();
  const [activeId, setActiveId] = useState('main');
  const [clearDraftToken, setClearDraftToken] = useState(0);
  useEffect(() => conversationFixture.reset(), []);
  const openSideChat = (id: string) =>
    void present(
      SideChatPreviewScreen,
      { id },
      { style: 'pageSheet', headerVariant: 'glass' },
    );
  const rootId = 'main';
  const fork = async (target: string, entryId = '') => {
    if (fixture.failNextFork) {
      conversationFixture.update((s) => ({ ...s, failNextFork: false }));
      await delay(800);
      Alert.alert(t('conversations.fork.failed'), offlineReason, [
        { text: t('common.cancel'), style: 'cancel' },
        {
          text: t('conversations.fork.retry'),
          onPress: () => void fork(target, entryId),
        },
      ]);
      return;
    }
    if (target === 'worktree') {
      Alert.alert(
        t('conversations.fork.dirtyTitle'),
        t('conversations.fork.dirtyMessage'),
        [
          { text: t('common.cancel'), style: 'cancel' },
          {
            text: t('conversations.fork.anyway'),
            onPress: () =>
              showToast(t('conversations.fork.worktreeDone'), 'info'),
          },
        ],
      );
      return;
    }
    const sideChat = target === 'sideChat';
    showToast(
      t(
        sideChat
          ? 'conversations.fork.creating'
          : 'conversations.fork.creatingTab',
      ),
      'info',
    );
    await delay(1200);
    const source = fixture.entries[activeId] ?? [];
    const cut = entryId
      ? source.slice(0, source.findIndex((e) => e.id === entryId) + 1)
      : source;
    const id = `${target}-${Date.now()}`;
    conversationFixture.addSession(
      {
        id,
        title: sideChat ? t('conversations.sideChat') : `${active?.title} ↗`,
        parentSessionId: rootId,
        childSessionPlacement: sideChat ? 'side-panel' : undefined,
      },
      cut,
    );
    if (sideChat) openSideChat(id);
    else setActiveId(id);
  };
  const service: ConversationService = {
    sideChat: fixture.offline ? 'disabled' : 'enabled',
    offlineReason: fixture.offline ? offlineReason : undefined,
    newTab: (root) => {
      const id = `draft-${Date.now()}`;
      conversationFixture.addSession(
        {
          id,
          title: t('conversations.newTab'),
          parentSessionId: root,
          status: 'idle',
          lastModel: null,
        },
        [],
      );
      setActiveId(id);
    },
    newSideChat: () => void fork('sideChat'),
    deleteSideChat: async (id) => {
      await delay(600);
      conversationFixture.remove(id);
    },
  };
  const conversations = useSessionConversations({
    sessions: fixture.sessions,
    activeId,
    onSwitch: setActiveId,
    onOpenSideChat: openSideChat,
    service,
  });
  const active = fixture.sessions.find((s) => s.id === activeId);
  const entries = fixture.entries[activeId] ?? [];
  const draft = entries.length === 0;
  const entriesJSON = JSON.stringify(entries);
  const openProcess = useProcessSheet(entriesJSON, () => {});
  const toggle = (key: 'offline' | 'failNextFork') =>
    conversationFixture.update((s) => ({ ...s, [key]: !s[key] }));
  return (
    <RNView style={{ flex: 1, backgroundColor: colors.reading }}>
      <NativeNavigationHeader
        items={[
          ...(conversations.headerItem ? [conversations.headerItem] : []),
          {
            type: 'menu',
            icon: { type: 'sfSymbol', name: 'ladybug' },
            accessibilityLabel: 'Fixture controls',
            menu: {
              items: [
                {
                  type: 'action',
                  title: 'Mac offline',
                  state: fixture.offline ? 'on' : 'off',
                  onPress: () => toggle('offline'),
                },
                {
                  type: 'action',
                  title: 'Fail next fork',
                  state: fixture.failNextFork ? 'on' : 'off',
                  onPress: () => toggle('failNextFork'),
                },
                {
                  type: 'action',
                  title: 'Reset',
                  onPress: () => {
                    conversationFixture.reset();
                    setActiveId('main');
                  },
                },
              ],
            },
          },
        ]}
      />
      <NativeChat
        key={activeId}
        style={{ flex: 1 }}
        navigationTitle={conversations.title?.title ?? active?.title ?? ''}
        navigationSubtitle={conversations.title?.subtitle ?? 'Lody iOS'}
        entriesJSON={entriesJSON}
        forkMenuJSON={JSON.stringify({
          state: fixture.offline ? 'disabled' : 'enabled',
          reason: fixture.offline ? offlineReason : '',
        })}
        onFork={({ nativeEvent }) =>
          void fork(nativeEvent.destination, nativeEvent.entryId)
        }
        composerJSON={JSON.stringify({
          editable: true,
          canSend: true,
          sending: false,
          running: false,
          notice: '',
          reconnect: false,
          connection: '',
          quickReplies: draft
            ? suggestions.map((key) => ({
                id: key,
                label: t(key),
                message: t(key),
              }))
            : [],
          placeholder: draft
            ? t('conversations.draft.placeholder')
            : t('chat.composer.placeholder'),
        })}
        clearDraftToken={clearDraftToken}
        emptyText={draft ? t('conversations.draft.empty') : ''}
        onSend={({ nativeEvent }) => {
          conversationFixture.send(activeId, nativeEvent.text);
          setClearDraftToken((n) => n + 1);
        }}
        onActivityPress={({ nativeEvent }) =>
          openProcess(nativeEvent.entryId, nativeEvent.processStartId)
        }
        onReconnect={() => {}}
      />
      <RNView
        accessible
        testID="conversation-probe"
        accessibilityLabel="Conversation state"
        accessibilityValue={{
          text: JSON.stringify({
            active: activeId,
            sessions: fixture.sessions.map((s) => s.id),
          }),
        }}
        pointerEvents="none"
        style={{ position: 'absolute', bottom: 0, width: 1, height: 1 }}
      />
    </RNView>
  );
}

export const ConversationsPreviewScreen = definePage({
  id: 'conversations-preview',
  title: 'Conversations',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
