import type { Session } from '../../models/catalog.ts';
import { sessionNeedsEmphasis } from './sessionViews.ts';
import { sessionState } from './status.ts';

type Viewed = Session & { lastViewedMessageAt?: number };

const byCreation = (a: Session, b: Session) =>
  Date.parse(a.createdAt) - Date.parse(b.createdAt);

const stateOf = (session: Session) =>
  sessionState(
    session.status,
    session.archived,
    session.awaitingUserSince !== undefined,
  );

export function conversationRootOf(id: string, sessions: Session[]) {
  return rootIn(id, new Map(sessions.map((session) => [session.id, session])));
}

function rootIn(id: string, byId: Map<string, Session>) {
  let current = byId.get(id);
  const seen = new Set<string>();
  while (current?.parentSessionId && !seen.has(current.id)) {
    seen.add(current.id);
    const parent = byId.get(current.parentSessionId);
    if (!parent) break;
    current = parent;
  }
  return current?.id ?? id;
}

export function conversationsOf(rootId: string, sessions: Session[]) {
  const byId = new Map(sessions.map((session) => [session.id, session]));
  const children = sessions
    .filter(
      (session) => session.id !== rootId && rootIn(session.id, byId) === rootId,
    )
    .sort(byCreation);
  return {
    root: byId.get(rootId),
    tabs: children.filter(
      (s) => !s.archived && s.childSessionPlacement !== 'side-panel',
    ),
    sideChats: children.filter(
      (s) => !s.archived && s.childSessionPlacement === 'side-panel',
    ),
    archived: children.filter((s) => s.archived),
  };
}

const urgency = ['attention', 'failed', 'live'] as const;

function rolledRoot(root: Viewed, children: Viewed[]): Session {
  const members = [root, ...children];
  const urgent = urgency
    .map((state) => members.find((member) => stateOf(member) === state))
    .find(Boolean);
  const lastMessageAt = Math.max(
    ...members.map((member) => member.lastMessageAt ?? 0),
  );
  const unread = members.find(sessionNeedsEmphasis);
  const waiting = children.find((child) => stateOf(child) === 'attention');
  return {
    ...root,
    status: urgent?.status ?? root.status,
    awaitingUserSince: urgent
      ? urgent.awaitingUserSince
      : root.awaitingUserSince,
    lastMessageAt: lastMessageAt || root.lastMessageAt,
    lastReadAt: unread ? unread.lastReadAt : lastMessageAt || root.lastReadAt,
    lastViewedMessageAt: unread?.lastViewedMessageAt,
    conversationRollup: {
      count: children.length,
      waitingTitle: waiting?.title,
    },
  } as Session;
}

export function rollupConversations(sessions: Session[]): Session[] {
  const byId = new Map(sessions.map((session) => [session.id, session]));
  const roots = new Map(
    sessions.map((session) => [session.id, rootIn(session.id, byId)]),
  );
  const children = new Map<string, Session[]>();
  for (const session of sessions) {
    const root = roots.get(session.id)!;
    if (root === session.id || session.archived) continue;
    children.set(root, [...(children.get(root) ?? []), session]);
  }
  return sessions
    .filter((session) => roots.get(session.id) === session.id)
    .map((session) => {
      const members = children.get(session.id);
      return members?.length ? rolledRoot(session, members) : session;
    });
}
