import type { Catalog, Session } from '../../models/catalog.ts';

export type SessionViews = Readonly<Record<string, number>>;
type ViewedSession = Session & { lastViewedMessageAt?: number };

export const sessionIsUnread = (session: Session) =>
  session.lastMessageAt !== undefined &&
  (session.lastReadAt === undefined ||
    session.lastMessageAt > session.lastReadAt);

export const sessionNeedsEmphasis = (session: ViewedSession) =>
  sessionIsUnread(session) &&
  (session.lastViewedMessageAt === undefined ||
    session.lastMessageAt! > session.lastViewedMessageAt);

// This projection is local UI state, never part of a cloud catalog write.
export function withSessionViews(catalog: Catalog, views: SessionViews) {
  return {
    ...catalog,
    sessions: catalog.sessions.map((session): ViewedSession => ({
      ...session,
      lastViewedMessageAt: views[session.id],
    })),
  };
}
