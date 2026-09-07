import type { NativeListSection } from '@lody-ios/kit';
import type { Catalog, Session } from '@/cloud/model';
import type { SessionState } from '../../ui/status.ts';
// Relative on purpose: this module is imported directly by node --test, which
// does not resolve the `@/` alias. Keep it free of aliased value imports.
import { agentName, sessionState, stateTint } from '../../ui/status.ts';
import { activityBucket, relativeTime } from '../../ui/time.ts';

const groups = [
  { id: 'attention', header: '需要你确认' },
  { id: 'live', header: '进行中' },
  { id: 'unread', header: '已完成 · 待查看' },
  { id: 'today', header: '今天' },
  { id: 'yesterday', header: '昨天' },
  { id: 'week', header: '一周内' },
  { id: 'month', header: '上个月' },
  { id: 'older', header: '更早' },
] as const;

export const activityAt = (session: Session) =>
  session.lastMessageAt ?? Date.parse(session.createdAt);
export const byActivity = (a: Session, b: Session) =>
  Number(b.pinned) - Number(a.pinned) || activityAt(b) - activityAt(a);
const badges: Partial<Record<SessionState, string>> = {
  attention: '等你确认',
  failed: '执行失败',
  archived: '已归档',
};
const unreadOf = (session: Session) =>
  session.lastMessageAt !== undefined &&
  (session.lastReadAt === undefined ||
    session.lastMessageAt > session.lastReadAt);

const stateOf = (session: Session) =>
  sessionState(
    session.status,
    session.archived,
    session.awaitingUserSince !== undefined,
  );

const inboxGroup = (session: Session, now?: number) => {
  const state = stateOf(session);
  if (state === 'attention' || state === 'failed') return 'attention';
  if (state === 'live') return 'live';
  if (unreadOf(session)) return 'unread';
  return activityBucket(activityAt(session), now);
};

export type InboxOptions = {
  keyword?: string;
  accent: string;
  now?: number;
};

export function inboxSections(
  catalog: Catalog,
  { keyword = '', accent, now }: InboxOptions,
): NativeListSection[] {
  const names = new Map(catalog.projects.map((p) => [p.id, p.name]));
  const term = keyword.trim().toLocaleLowerCase();
  const matches = (session: Session) =>
    !term ||
    `${session.title} ${names.get(session.projectId) ?? ''}`
      .toLocaleLowerCase()
      .includes(term);

  const visible = catalog.sessions
    .filter((session) => (session.archived ? term.length > 0 : true))
    .filter(matches)
    .sort(byActivity);

  const buckets = new Map<string, Session[]>();
  for (const session of visible) {
    const id = inboxGroup(session, now);
    const bucket = buckets.get(id);
    if (bucket) bucket.push(session);
    else buckets.set(id, [session]);
  }
  return groups.flatMap((group) => {
    const rows = (buckets.get(group.id) ?? []).map((session) => {
      const state = stateOf(session);
      return {
        id: session.id,
        title: session.title,
        subtitle: names.get(session.projectId) ?? '',
        value: relativeTime(activityAt(session), now),
        unread: unreadOf(session),
        badge: badges[state],
        imageTint:
          state === 'live' || badges[state]
            ? stateTint(state, accent)
            : undefined,
        action: true,
        navigates: true,
        actions: [archiveAction(session.archived)],
        leadingActions: [pinAction(session.pinned)],
      };
    });
    return rows.length ? [{ id: group.id, header: group.header, rows }] : [];
  });
}

export const archiveAction = (archived: boolean) => ({
  id: 'archive',
  title: archived ? '取消归档' : '归档',
  symbol: archived ? 'tray.and.arrow.up' : 'archivebox',
});
export const pinAction = (pinned: boolean) => ({
  id: 'pin',
  title: pinned ? '取消置顶' : '置顶',
  symbol: pinned ? 'pin.slash.fill' : 'pin.fill',
  tint: 'yellow',
});

export function sessionRow(
  session: Session,
  accent: string,
  projectName = '',
  now?: number,
) {
  const state = stateOf(session);
  const lead = session.branchName ?? agentName(session.agentType);
  return {
    id: session.id,
    title: session.title,
    subtitle: [projectName, lead].filter(Boolean).join(' · '),
    subtitleMono: session.branchName !== undefined,
    diff: session.diff,
    value: relativeTime(activityAt(session), now),
    unread: unreadOf(session),
    badge: badges[state],
    imageTint: ['live', 'attention', 'failed'].includes(state)
      ? stateTint(state, accent)
      : undefined,
    action: true,
    navigates: true,
    actions: [archiveAction(session.archived)],
    leadingActions: [pinAction(session.pinned)],
  };
}

export function projectSections(
  catalog: Catalog,
  accent: string,
  expanded: Record<string, boolean> = {},
  now?: number,
): NativeListSection[] {
  return catalog.projects.map((project) => {
    const sessions = catalog.sessions
      .filter((s) => s.projectId === project.id && !s.archived)
      .sort(byActivity);
    const open = expanded[project.id] ?? true;
    const rows: NativeListSection['rows'] = open
      ? sessions
          .slice(0, 5)
          .map((session) => sessionRow(session, accent, '', now))
      : [];
    if (open && sessions.length > 5) {
      rows.push({
        id: `project:${project.id}`,
        title: '更多',
        action: true,
        disclosure: true,
        navigates: true,
      });
    }
    return {
      id: project.id,
      header: project.name,
      headerValue: open ? undefined : String(sessions.length),
      headerActionId: `toggle:${project.id}`,
      headerExpanded: open,
      rows,
    };
  });
}

export function searchSections(
  catalog: Catalog,
  keyword: string,
  accent: string,
): NativeListSection[] {
  const term = keyword.trim().toLocaleLowerCase();
  if (!term) return [];
  const names = new Map(catalog.projects.map((p) => [p.id, p.name]));
  const projects = catalog.projects.filter((p) =>
    p.name.toLocaleLowerCase().includes(term),
  );
  const sessions = catalog.sessions
    .filter((s) =>
      `${s.title} ${names.get(s.projectId) ?? ''}`
        .toLocaleLowerCase()
        .includes(term),
    )
    .sort(byActivity);
  return [
    {
      id: 'projects',
      header: '项目',
      rows: projects.map((p) => ({
        id: `project:${p.id}`,
        title: p.name,
        subtitle: p.rootPath,
        image: 'folder',
        action: true,
        disclosure: true,
        navigates: true,
      })),
    },
    {
      id: 'sessions',
      header: '会话',
      rows: sessions.map((s) => sessionRow(s, accent, names.get(s.projectId))),
    },
  ].filter((section) => section.rows.length);
}
