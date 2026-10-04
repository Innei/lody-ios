import assert from 'node:assert/strict';
import test from 'node:test';
import { projectRows } from '../../src/cloud/catalog/model.ts';
import {
  byActivity,
  projectSections,
  sessionRow,
  sessionTreeRows,
  inboxSections,
  searchSections,
  matchCatalog,
} from '../../src/features/sessions/inbox.ts';
import { sessionTree } from '../../src/features/sessions/sessionTree.ts';
import { setLocale } from '../../src/lib/i18n/index.ts';

setLocale('en');
const now = Date.parse('2026-09-19T12:00:00Z');
const session = (id, extra = {}) => ({
  id,
  title: id,
  machineId: 'm',
  projectId: 'p',
  status: 'completed',
  archived: false,
  pinned: false,
  createdAt: new Date(now).toISOString(),
  lastMessageAt: now - 1000,
  lastReadAt: now,
  ...extra,
});
const catalog = (sessions) => ({
  sessions,
  projects: [
    { id: 'p', name: 'Project', rootPath: '/tmp/project', machineId: 'm' },
  ],
  machineIds: ['m'],
});
const shape = (groups) =>
  groups.map(({ session, children }) => [
    session.id,
    children.map((s) => s.id),
  ]);

test('cloud provenance reaches tree rows, caps depth and ranks a stale opener by fresh work', () => {
  const values = [
    session('root', { lastMessageAt: now - 100_000 }),
    session('other', { lastMessageAt: now - 20_000 }),
    session('child', { openedBySessionId: 'root' }),
    session('grandchild', { openedBySessionId: 'child' }),
  ];
  const rows = values.flatMap((s) => [
    { key: ['e', `session-${s.id}`], value: true },
    {
      key: ['m', `session-${s.id}`],
      value: { ...s, project: { kind: 'local', localProjectId: 'p' } },
    },
  ]);
  const projected = projectRows(rows, 'meta');
  const tree = sessionTree(
    [...projected.sessions].sort(byActivity),
    projected.sessions,
  );
  assert.deepEqual(shape(tree), [
    ['root', ['child', 'grandchild']],
    ['other', []],
  ]);
  for (const sections of [
    projectSections(projected, 'blue', {}, now),
    inboxSections(projected, { accent: 'blue', now }),
    searchSections(
      projected,
      {
        projectIds: [],
        sessions: values.map(({ id }) => ({ id, snippet: null })),
      },
      'blue',
    ),
  ]) {
    const rows = sections.flatMap((s) => s.rows);
    assert.equal(rows.find((s) => s.id === 'child').parentId, 'root');
    assert.equal(rows.find((s) => s.id === 'grandchild').parentId, 'root');
  }
});

test('absent, cross-project, cross-archive and cyclic openers never swallow sessions', () => {
  const cases = [
    [session('child', { openedBySessionId: 'absent' })],
    [
      session('root'),
      session('child', { openedBySessionId: 'root', projectId: 'another' }),
    ],
    [
      session('root'),
      session('child', { openedBySessionId: 'root', archived: true }),
    ],
    [
      session('a', { openedBySessionId: 'b' }),
      session('b', { openedBySessionId: 'a' }),
      session('c', { openedBySessionId: 'a' }),
    ],
    [session('self', { openedBySessionId: 'self' })],
  ];
  for (const sessions of cases) {
    assert.deepEqual(
      shape(sessionTree(sessions, sessions)),
      sessions.map((s) => [s.id, []]),
    );
  }
  const data = catalog([
    session('root'),
    session('child', { openedBySessionId: 'root' }),
  ]);
  const hits = searchSections(data, matchCatalog(data, 'child'), 'blue');
  assert.equal(hits[0].rows[0].id, 'child');
  assert.equal(hits[0].rows[0].parentId, undefined);
});

test('a Tab opener resolves to its containing root without nesting the Tab twice', () => {
  const root = session('root');
  const tab = session('tab', {
    parentSessionId: 'root',
    openedBySessionId: 'root',
  });
  const child = session('child', { openedBySessionId: 'tab' });
  assert.deepEqual(shape(sessionTree([root, child], [root, tab, child])), [
    ['root', ['child']],
  ]);
  assert.deepEqual(shape(sessionTree([root, tab, child], [root, tab, child])), [
    ['root', ['child']],
    ['tab', []],
  ]);
  const nested = session('nested', { parentSessionId: 'tab' });
  assert.deepEqual(
    shape(
      sessionTree(
        [root, { ...child, openedBySessionId: 'nested' }],
        [root, tab, nested],
      ),
    ),
    [['root', ['child']]],
  );
});

test('project preview caps roots, keeps their children and summarizes hidden attention', () => {
  const children = Array.from({ length: 7 }, (_, i) =>
    session(`child-${i}`, {
      openedBySessionId: 'root',
      status: i === 0 ? 'waiting' : 'completed',
    }),
  );
  const sessions = [
    session('root'),
    ...children,
    ...Array.from({ length: 6 }, (_, i) => session(`other-${i}`)),
  ];
  const rows = projectSections(catalog(sessions), 'blue', {}, now)[0].rows;
  for (const child of children)
    assert.ok(rows.some((row) => row.id === child.id));
  assert.ok(rows.some((row) => row.id === 'other-3'));
  assert.ok(!rows.some((row) => row.id === 'other-4'));
  const root = rows.find((row) => row.id === 'root');
  assert.equal(root.collapsedValue, '7 sessions');
  assert.equal(root.collapsedBadge, sessionRow(children[0], 'blue').badge);
  const filtered = sessionTreeRows([sessions[0]], sessions, (s) =>
    sessionRow(s, 'blue'),
  );
  assert.equal(filtered[0].collapsedValue, undefined);
});

test('pinned and activity section boundaries remain separate', () => {
  const sessions = [
    session('root'),
    session('child', { openedBySessionId: 'root', pinned: true }),
    session('running', { openedBySessionId: 'root', status: 'running' }),
  ];
  const data = catalog(sessions);
  const projects = projectSections(data, 'blue', {}, now).flatMap(
    (s) => s.rows,
  );
  assert.equal(projects.find((s) => s.id === 'child').parentId, undefined);
  const activity = inboxSections(data, { accent: 'blue', now }).flatMap(
    (s) => s.rows,
  );
  assert.equal(activity.find((s) => s.id === 'running').parentId, undefined);
});
