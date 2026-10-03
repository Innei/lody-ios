import type { NativeListRow, NativeListSection } from '@lody-ios/kit';
import type { Session } from '../../models/catalog.ts';
import { t, tp } from '../../lib/i18n/index.ts';
import { relativeTime } from '../../ui/time.ts';
import { conversationsOf } from './conversations.ts';
import { sessionNeedsEmphasis } from './sessionViews.ts';
import {
  sessionState,
  stateLabel,
  stateSymbol,
  stateTint,
  type SessionState,
} from './status.ts';

export type SideChatLauncher = 'enabled' | 'disabled' | 'hidden';

export type ConversationSheetOptions = {
  accent: string;
  now?: number;
  create?: { sideChat: SideChatLauncher; offlineReason?: string };
};

const stateOf = (session: Session) =>
  sessionState(
    session.status,
    session.archived,
    session.awaitingUserSince !== undefined,
  );

const tinted = new Set<SessionState>(['live', 'attention', 'failed']);

function rowSymbol(session: Session, state: SessionState) {
  if (tinted.has(state)) return stateSymbol[state];
  if (session.childSessionPlacement === 'side-panel') return 'text.bubble';
  return 'bubble.left';
}

function conversationRow(
  session: Session,
  activeId: string,
  { accent, now }: ConversationSheetOptions,
): NativeListRow {
  const state = stateOf(session);
  const time = session.lastMessageAt
    ? relativeTime(session.lastMessageAt, now)
    : '';
  return {
    id: session.id,
    title: session.title,
    subtitle: [stateLabel(state), time].filter(Boolean).join(' · '),
    image: rowSymbol(session, state),
    imageTint: tinted.has(state) ? stateTint(state, accent) : 'secondary',
    unread: sessionNeedsEmphasis(session),
    selected: session.id === activeId,
    action: true,
  };
}

const deleteAction = () => ({
  id: 'delete',
  title: t('conversations.deleteSideChat'),
  symbol: 'trash',
  destructive: true,
});

export function conversationSections(
  sessions: Session[],
  rootId: string,
  activeId: string,
  options: ConversationSheetOptions,
): NativeListSection[] {
  const { root, tabs, sideChats, archived } = conversationsOf(rootId, sessions);
  const create = options.create;
  const rowOf = (session: Session) =>
    conversationRow(session, activeId, options);
  const tabRows: NativeListRow[] = [
    ...(root ? [{ ...rowOf(root), badge: t('conversations.main') }] : []),
    ...tabs.map(rowOf),
  ];
  if (create) {
    tabRows.push({
      id: 'new-tab',
      title: t('conversations.newTab'),
      subtitle: t('conversations.sameWorkspace'),
      image: 'plus',
      imageTint: options.accent,
      action: true,
    });
  }
  const sideRows: NativeListRow[] = sideChats.map((session) => ({
    ...rowOf(session),
    ...(create ? { actions: [deleteAction()] } : {}),
  }));
  if (create && create.sideChat !== 'hidden') {
    const enabled = create.sideChat === 'enabled';
    sideRows.push({
      id: 'new-side-chat',
      title: t('conversations.newSideChat'),
      subtitle: enabled
        ? t('conversations.fromLatestReply')
        : (create.offlineReason ?? t('conversations.unavailable')),
      image: 'plus',
      imageTint: enabled ? options.accent : 'tertiary',
      action: enabled,
    });
  }
  const sections: NativeListSection[] = [
    { id: 'tabs', header: t('conversations.tabs'), rows: tabRows },
  ];
  if (sideRows.length)
    sections.push({
      id: 'sideChats',
      header: t('conversations.sideChats'),
      rows: sideRows,
    });
  if (archived.length)
    sections.push({
      id: 'archived',
      header: t('conversations.archived'),
      rows: archived.map(rowOf),
    });
  return sections;
}

export function conversationBadge(
  sessions: Session[],
  rootId: string,
  activeId: string,
) {
  const { root, tabs, sideChats } = conversationsOf(rootId, sessions);
  return [root, ...tabs, ...sideChats].filter(
    (session) =>
      session && session.id !== activeId && stateOf(session) === 'attention',
  ).length;
}

export function conversationTitle(
  sessions: Session[],
  rootId: string,
  activeId: string,
) {
  const { root, tabs, sideChats } = conversationsOf(rootId, sessions);
  if (!root || !(tabs.length + sideChats.length)) return;
  const active = [root, ...tabs, ...sideChats].find((s) => s.id === activeId);
  if (!active) return;
  if (active.id === root.id) {
    const count = 1 + tabs.length + sideChats.length;
    return {
      title: root.title,
      subtitle: [
        t('conversations.main'),
        tp('conversations.count', count, { count }),
      ].join(' · '),
    };
  }
  return {
    title: active.title,
    subtitle: t('conversations.inParent', { title: root.title }),
  };
}
