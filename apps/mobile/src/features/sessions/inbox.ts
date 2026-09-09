import type { NativeListRow, NativeListSection } from '@lody-ios/kit';
import type { Catalog, Project, Session } from '../../models/catalog.ts';
import type { SessionState } from './status.ts';
import { agentName, sessionState, stateTint } from './status.ts';
import { activityBucket, relativeTime } from '../../ui/time.ts';
import {
  t,
  tp,
  type PluralKey,
  type TranslationKey,
} from '../../lib/i18n/index.ts';

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
export function projectIdOfRow(id: string) {
  if (id.startsWith('toggle:')) return id.slice(7);
  if (id.startsWith('project:')) return id.slice(8);
}
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
        pinned: session.pinned,
        badge: badgeOf(state),
        imageTint:
          state === 'live' || badges[state]
            ? stateTint(state, accent)
            : undefined,
        action: true,
        navigates: true,
        actions: [archiveAction(session.archived)],
        leadingActions: [pinAction(session.pinned)],
        ...sessionMenu(session),
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
const newSessionAction = () => ({
  id: 'newSession',
  title: t('session.action.newSession'),
  symbol: 'square.and.pencil',
});
const sessionMenu = (session: Session) => ({
  menuActions: [
    newSessionAction(),
    pinAction(session.pinned),
    archiveAction(session.archived),
  ],
  preview: 'session' as const,
});
const projectMenu = (project: Project) => {
  const actions: NativeListRow['menuActions'] = [
    { id: 'open', title: t('project.action.open'), symbol: 'folder' },
  ];
  if (!project.id.endsWith(':unassigned')) {
    actions.unshift(newSessionAction());
  }
  if (project.rootPath) {
    actions.push({
      id: 'copyPath',
      title: t('project.action.copyPath'),
      symbol: 'doc.on.doc',
    });
  }
  return { menuActions: actions };
};

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
    pinned: session.pinned,
    badge: badgeOf(state),
    imageTint: ['live', 'attention', 'failed'].includes(state)
      ? stateTint(state, accent)
      : undefined,
    action: true,
    navigates: true,
    actions: [archiveAction(session.archived)],
    leadingActions: [pinAction(session.pinned)],
    ...sessionMenu(session),
  };
}

const countKeys = {
  failed: 'inbox.project.failed',
  attention: 'inbox.project.attention',
  live: 'inbox.project.live',
} satisfies Partial<Record<SessionState, PluralKey>>;

function projectTrailing(
  sessions: Session[],
  open: boolean,
  accent: string,
): Partial<NativeListRow> {
  if (!sessions.length) {
    return {
      badge: '0',
      disclosure: true,
      navigates: true,
    };
  }
  if (!open) return { badge: String(sessions.length) };
  const states = sessions.map(stateOf);
  for (const state of ['failed', 'attention', 'live'] as const) {
    const count = states.filter((s) => s === state).length;
    if (count) {
      return {
        value: tp(countKeys[state], count, { count }),
        imageTint: stateTint(state, accent),
      };
    }
  }
  return {};
}

const homePath = (path = '') => path.replace(/^\/(Users|home)\/[^/]+/, '~');

function projectRow(
  project: Project,
  sessions: Session[],
  open: boolean,
  accent: string,
): NativeListRow {
  return {
    id: sessions.length ? `toggle:${project.id}` : `project:${project.id}`,
    parent: true,
    monogram: project.name.slice(0, 1),
    title: project.name,
    subtitle: homePath(project.rootPath),
    subtitleMono: true,
    action: true,
    ...projectMenu(project),
    ...projectTrailing(sessions, open, accent),
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
    const rows = [
      projectRow(project, sessions, open, accent),
      ...sessions
        .slice(0, 5)
        .map((session) => sessionRow(session, accent, '', now)),
    ];
    const rest = sessions.length - 5;
    if (rest > 0) {
      rows.push({
        id: `project:${project.id}`,
        title: tp('inbox.project.more', rest, { count: rest }),
        action: true,
        disclosure: true,
        navigates: true,
      });
    }
    return { id: project.id, headerExpanded: open, rows };
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
        ...projectMenu(p),
      })),
    },
    {
      id: 'sessions',
      header: t('inbox.section.sessions'),
      rows: sessions.map((s) => sessionRow(s, accent, names.get(s.projectId))),
    },
  ].filter((section) => section.rows.length);
}
