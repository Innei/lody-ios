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
    return { kind: 'discard', reason: '请使用接收通知的账号打开会话' };
  const route = parseNotificationRoute(click.route);
  if (!route) return { kind: 'discard', reason: '无法识别此通知的会话链接' };
  const workspace = context.workspaces.find(
    (w) => w.slug === route.workspaceSlug,
  );
  if (!workspace)
    return { kind: 'discard', reason: '当前账号无法访问此工作区' };
  if (workspace.id !== context.selectedId)
    return { kind: 'workspace', id: workspace.id };
  const session = context.sessions.find((s) => s.id === route.sessionId);
  if (session) return { kind: 'session', session };
  if (context.loading || !context.connected) return { kind: 'wait' };
  return { kind: 'discard', reason: '此会话已不可用' };
}
