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

export const CHAT_SECTION_ID = 'chat';
export type ProjectSort = 'name' | 'activity' | 'urgency';

export const activityAt = (session: Session) =>
  session.lastMessageAt ?? Date.parse(session.createdAt);
export function isChatProjectId(id: string) {
  return id.endsWith(':unassigned');
}
export function isChatSession(session: Pick<Session, 'projectId'>) {
  return isChatProjectId(session.projectId);
}
export function isChatSectionRow(id: string) {
  return (
    id === CHAT_SECTION_ID ||
    id === `toggle:${CHAT_SECTION_ID}` ||
    id === `view:${CHAT_SECTION_ID}` ||
    id === `project:${CHAT_SECTION_ID}`
  );
}
export function projectIdOfRow(id: string) {
  if (isChatSectionRow(id) || id.startsWith('view:')) return;
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
  chatOnly?: boolean;
};

function sessionPlace(session: Session, names: Map<string, string>) {
  if (isChatSession(session)) return t('inbox.section.chat');
  return names.get(session.projectId) ?? '';
}

export function inboxSections(
  catalog: Catalog,
  { keyword = '', accent, now, chatOnly = false }: InboxOptions,
): NativeListSection[] {
  const names = new Map(catalog.projects.map((p) => [p.id, p.name]));
  const term = keyword.trim().toLocaleLowerCase();
  const matches = (session: Session) =>
    !term ||
    `${session.title} ${sessionPlace(session, names)}`
      .toLocaleLowerCase()
      .includes(term);

  const visible = catalog.sessions
    .filter((session) => (chatOnly ? isChatSession(session) : true))
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
        subtitle: sessionPlace(session, names),
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
const newChatAction = () => ({
  id: 'newChat',
  title: t('session.action.newChat'),
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
  if (!isChatProjectId(project.id)) actions.unshift(newSessionAction());
  if (project.rootPath) {
    actions.push({
      id: 'copyPath',
      title: t('project.action.copyPath'),
      symbol: 'doc.on.doc',
    });
  }
  return { menuActions: actions };
};

const urgencyRank = (sessions: Session[]) => {
  const states = sessions.map(stateOf);
  if (states.some((state) => state === 'attention' || state === 'failed'))
    return 0;
  if (states.some((state) => state === 'live')) return 1;
  return 2;
};

const projectActivity = (sessions: Session[]) =>
  sessions.reduce(
    (latest, session) => Math.max(latest, activityAt(session)),
    0,
  );

export function compareProjects(
  left: { name: string; sessions: Session[] },
  right: { name: string; sessions: Session[] },
  sort: ProjectSort,
) {
  if (sort === 'activity' || sort === 'urgency') {
    if (sort === 'urgency') {
      const rank = urgencyRank(left.sessions) - urgencyRank(right.sessions);
      if (rank) return rank;
    }
    const activity =
      projectActivity(right.sessions) - projectActivity(left.sessions);
    if (activity) return activity;
  }
  return left.name.localeCompare(right.name);
}

export function sortCatalogProjects(
  projects: Project[],
  sessions: Session[],
  sort: ProjectSort,
) {
  const grouped = new Map(
    projects
      .filter((project) => !isChatProjectId(project.id))
      .map((project) => [
        project.id,
        sessions.filter((s) => s.projectId === project.id && !s.archived),
      ]),
  );
  return [...projects]
    .filter((project) => !isChatProjectId(project.id))
    .sort((left, right) =>
      compareProjects(
        { name: left.name, sessions: grouped.get(left.id) ?? [] },
        { name: right.name, sessions: grouped.get(right.id) ?? [] },
        sort,
      ),
    );
}

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

function sessionGroup(
  id: string,
  parent: NativeListRow,
  sessions: Session[],
  accent: string,
  now?: number,
  moreId = `project:${id}`,
): NativeListSection {
  const rows = [
    parent,
    ...sessions
      .slice(0, 5)
      .map((session) => sessionRow(session, accent, '', now)),
  ];
  const rest = sessions.length - 5;
  if (rest > 0) {
    rows.push({
      id: moreId,
      title: tp('inbox.project.more', rest, { count: rest }),
      action: true,
      disclosure: true,
      navigates: true,
    });
  }
  return { id, rows };
}

export function projectSections(
  catalog: Catalog,
  accent: string,
  expanded: Record<string, boolean> = {},
  now?: number,
  sort: ProjectSort = 'name',
): NativeListSection[] {
  const projects = sortCatalogProjects(
    catalog.projects,
    catalog.sessions,
    sort,
  );
  const sections = projects.map((project) => {
    const sessions = catalog.sessions
      .filter((s) => s.projectId === project.id && !s.archived)
      .sort(byActivity);
    const open = expanded[project.id] ?? true;
    const parent = projectRow(project, sessions, open, accent);
    const group = sessionGroup(project.id, parent, sessions, accent, now);
    return { ...group, headerExpanded: open };
  });
  const chats = catalog.sessions
    .filter((session) => isChatSession(session) && !session.archived)
    .sort(byActivity);
  if (!chats.length) return sections;
  const open = expanded[CHAT_SECTION_ID] ?? true;
  const title = t('inbox.section.chat');
  sections.push({
    ...sessionGroup(
      CHAT_SECTION_ID,
      {
        id: `toggle:${CHAT_SECTION_ID}`,
        parent: true,
        image: 'bubble.left',
        title,
        action: true,
        menuActions: [newChatAction()],
        ...projectTrailing(chats, open, accent),
      },
      chats,
      accent,
      now,
      `view:${CHAT_SECTION_ID}`,
    ),
    headerExpanded: open,
  });
  return sections;
}

export function searchSections(
  catalog: Catalog,
  keyword: string,
  accent: string,
): NativeListSection[] {
  const term = keyword.trim().toLocaleLowerCase();
  if (!term) return [];
  const names = new Map(catalog.projects.map((p) => [p.id, p.name]));
  const projects = catalog.projects.filter(
    (p) => !isChatProjectId(p.id) && p.name.toLocaleLowerCase().includes(term),
  );
  const sessions = catalog.sessions
    .filter((s) =>
      `${s.title} ${sessionPlace(s, names)}`.toLocaleLowerCase().includes(term),
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
      rows: sessions.map((s) => sessionRow(s, accent, sessionPlace(s, names))),
    },
  ].filter((section) => section.rows.length);
}
