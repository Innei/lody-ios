import { useLayoutEffect, useMemo, useRef } from 'react';
import { present } from '@/lib/presentation';
import type { HeaderItems } from '@/lib/presentation/SheetStack';
import { t } from '@/lib/i18n/index.ts';
import {
  conversationRootOf,
  conversationsOf,
} from '@/features/sessions/conversations';
import {
  conversationBadge,
  conversationTitle,
  type SideChatLauncher,
} from '@/features/sessions/conversationSheet';
import type { Session } from '@/models/catalog';
import { ConversationsScreen } from '@/screens/ConversationsScreen';
import { createProcessSource } from '@/screens/ProcessScreen';

export type ConversationService = {
  sideChat: SideChatLauncher;
  offlineReason?: string;
  newTab: (rootId: string) => void;
  newSideChat: (rootId: string) => void;
  deleteSideChat: (id: string) => Promise<void>;
};

export function useSessionConversations({
  sessions,
  activeId,
  onSwitch,
  onOpenSideChat,
  service,
}: {
  sessions: Session[];
  activeId: string;
  onSwitch: (id: string) => void;
  onOpenSideChat: (id: string) => void;
  service?: ConversationService;
}) {
  const rootId = conversationRootOf(activeId, sessions);
  const json = JSON.stringify(sessions);
  const source = useMemo(() => createProcessSource(json), []);
  useLayoutEffect(() => source.update(json), [json, source]);
  const { tabs, sideChats } = conversationsOf(rootId, sessions);
  const badge = conversationBadge(sessions, rootId, activeId);
  const title = conversationTitle(sessions, rootId, activeId);
  const open = async () => {
    const result = await present(ConversationsScreen, {
      rootId,
      activeId,
      source,
      create: service && {
        sideChat: service.sideChat,
        offlineReason: service.offlineReason,
      },
      onDelete: service?.deleteSideChat,
    });
    if (result.status !== 'completed') return;
    const choice = result.value;
    if (choice.type === 'newTab') service?.newTab(rootId);
    else if (choice.type === 'newSideChat') service?.newSideChat(rootId);
    else if (sideChats.some((s) => s.id === choice.id))
      onOpenSideChat(choice.id);
    else if (choice.id !== activeId) onSwitch(choice.id);
  };
  const openRef = useRef(open);
  openRef.current = open;
  const visible = tabs.length + sideChats.length > 0 || !!service;
  const headerItem = useMemo<NonNullable<HeaderItems>[number] | undefined>(
    () =>
      visible
        ? {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'square.on.square' },
            accessibilityLabel: t('conversations.title'),
            badge: badge ? { value: String(badge) } : undefined,
            onPress: () => void openRef.current(),
          }
        : undefined,
    [visible, badge],
  );
  return { rootId, title, headerItem, open };
}
