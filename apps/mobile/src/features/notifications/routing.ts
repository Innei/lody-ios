import { t } from '../../lib/i18n/index.ts';
import type { Session } from '../../models/catalog';

export type NotificationClick = { id: string; route: string; userId: string };
export function parseNotificationRoute(
  route: string,
): { workspaceSlug: string; sessionId: string } | null {
  if (route.length > 2048) return null;
  const match = /^\/([^/?#]+)\/sessions\/([^/?#]+)$/.exec(route);
  if (!match) return null;
  try {
    const workspaceSlug = decodeURIComponent(match[1]!);
    const sessionId = decodeURIComponent(match[2]!);
    if (
      [workspaceSlug, sessionId].some(
        (s) => !s || s === '.' || s === '..' || /[\/\\\x00-\x1f\x7f]/.test(s),
      )
    )
      return null;
    return { workspaceSlug, sessionId };
  } catch {
    return null;
  }
}

export function routeFromDeepLink(url: string): string | null {
  const match = /^lody:\/\/(\/?[^?#]*)/i.exec(url);
  if (!match) return null;
  const path = match[1]!;
  return path.startsWith('/') ? path : `/${path}`;
}

export type PushDestination =
  | { kind: 'wait' }
  | { kind: 'discard'; reason: string }
  | { kind: 'workspace'; id: string }
  | { kind: 'session'; session: Session };

/** Resolve only against the current account's catalog; never fabricate a Session from a URL. */
export function resolveNotificationClick(
  click: NotificationClick,
  context: {
    ready: boolean;
    userId?: string;
    workspaces: Array<{ id: string; slug: string | null }>;
    selectedId?: string;
    loading: boolean;
    connected: boolean;
    sessions: Session[];
  },
): PushDestination {
  if (!context.ready) return { kind: 'wait' };
  if (!context.userId || click.userId !== context.userId)
    return { kind: 'discard', reason: t('notifications.route.wrongAccount') };
  const route = parseNotificationRoute(click.route);
  if (!route)
    return { kind: 'discard', reason: t('notifications.route.unknown') };
  const workspace = context.workspaces.find(
    (w) => w.slug === route.workspaceSlug || w.id === route.workspaceSlug,
  );
  if (!workspace)
    return { kind: 'discard', reason: t('notifications.route.noWorkspace') };
  if (workspace.id !== context.selectedId)
    return { kind: 'workspace', id: workspace.id };
  const session = context.sessions.find((s) => s.id === route.sessionId);
  if (session) return { kind: 'session', session };
  if (context.loading || !context.connected) return { kind: 'wait' };
  return { kind: 'discard', reason: t('notifications.route.gone') };
}
