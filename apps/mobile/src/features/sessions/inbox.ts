import type { NativeListSection } from '@lody-ios/kit';
import type { Catalog, Session } from '../../models/catalog.ts';
import type { SessionState } from './status.ts';
import { agentName, sessionState, stateTint } from './status.ts';
import { activityBucket, relativeTime } from '../../ui/time.ts';
import { t, type TranslationKey } from '../../i18n/index.ts';

const groups = [
  { id: 'attention', header: 'inbox.section.attention' },
  { id: 'live', header: 'inbox.section.live' },
  { id: 'unread', header: 'inbox.section.unread' },
  { id: 'today', header: 'inbox.section.today' },
  { id: 'yesterday', header: 'inbox.section.yesterday' },
  { id: 'week', header: 'inbox.section.week' },
  { id: 'month', header: 'inbox.section.month' },
  { id: 'older', header: 'inbox.section.older' },
] as const;

export const activityAt = (session: Session) =>
  session.lastMessageAt ?? Date.parse(session.createdAt);
export const byActivity = (a: Session, b: Session) =>
  Number(b.pinned) - Number(a.pinned) || activityAt(b) - activityAt(a);
const badges: Partial<Record<SessionState, TranslationKey>> = {
  attention: 'inbox.badge.attention',
  failed: 'inbox.badge.failed',
  archived: 'inbox.badge.archived',
};
const badgeOf = (state: SessionState) => {
  const key = badges[state];
  return key && t(key);
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
        badge: badgeOf(state),
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
    return rows.length ? [{ id: group.id, header: t(group.header), rows }] : [];
  });
}

export const archiveAction = (archived: boolean) => ({
  id: 'archive',
  title: t(archived ? 'session.action.unarchive' : 'session.action.archive'),
  symbol: archived ? 'tray.and.arrow.up' : 'archivebox',
});
export const pinAction = (pinned: boolean) => ({
  id: 'pin',
  title: t(pinned ? 'session.action.unpin' : 'session.action.pin'),
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
    badge: badgeOf(state),
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
        title: t('common.more'),
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
      header: t('inbox.section.projects'),
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
      header: t('inbox.section.sessions'),
      rows: sessions.map((s) => sessionRow(s, accent, names.get(s.projectId))),
    },
  ].filter((section) => section.rows.length);
}
