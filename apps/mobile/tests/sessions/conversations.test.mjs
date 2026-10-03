import assert from 'node:assert/strict';
import test from 'node:test';
import { projectRows } from '../../src/cloud/catalog/model.ts';
import {
  conversationsOf,
  conversationRootOf,
} from '../../src/features/sessions/conversations.ts';
import {
  inboxSections,
  projectSections,
  searchSections,
  matchCatalog,
} from '../../src/features/sessions/inbox.ts';
import { setLocale } from '../../src/lib/i18n/index.ts';

setLocale('en');
const now = Date.parse('2026-10-03T12:00:00Z');
const session = (id, extra = {}) => ({
  id,
  title: id,
  machineId: 'm',
  projectId: 'p',
  status: 'completed',
  archived: false,
  pinned: false,
  createdAt: new Date(now - 60_000).toISOString(),
  lastMessageAt: now - 60_000,
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
const family = () => [
  session('root', { title: 'Fix login redirect loop' }),
  session('tests', {
    title: 'Refactor tests',
    parentSessionId: 'root',
    createdAt: new Date(now - 50_000).toISOString(),
    status: 'requestPermission',
    awaitingUserSince: now - 5000,
    lastMessageAt: now - 5000,
  }),
  session('explore', {
    title: 'Explore auth flow',
    parentSessionId: 'root',
    createdAt: new Date(now - 40_000).toISOString(),
  }),
  session('side', {
    title: 'Why does the cookie expire?',
    parentSessionId: 'root',
    childSessionPlacement: 'side-panel',
  }),
  session('old', {
    title: 'Old tab',
    parentSessionId: 'root',
    archived: true,
  }),
];

test('a root lists its tabs, side chats and archived children apart', () => {
  const groups = conversationsOf('root', family());
  assert.equal(groups.root.id, 'root');
  assert.deepEqual(
    groups.tabs.map((s) => s.id),
    ['tests', 'explore'],
  );
  assert.deepEqual(
    groups.sideChats.map((s) => s.id),
    ['side'],
  );
  assert.deepEqual(
    groups.archived.map((s) => s.id),
    ['old'],
  );
  assert.equal(conversationRootOf('side', family()), 'root');
  assert.equal(conversationRootOf('root', family()), 'root');
  assert.equal(
    conversationRootOf('lost', [session('lost', { parentSessionId: 'gone' })]),
    'lost',
  );
});

test('catalog projection keeps the side-panel placement', () => {
  const rows = [
    { key: ['e', 'session-side'], value: true },
    {
      key: ['m', 'session-side'],
      value: {
        ...session('side', { parentSessionId: 'root' }),
        childSessionPlacement: 'side-panel',
        project: { kind: 'local', localProjectId: 'p' },
      },
    },
  ];
  assert.equal(
    projectRows(rows, 'meta').sessions[0].childSessionPlacement,
    'side-panel',
  );
});

test('contained conversations roll up into the parent row everywhere', () => {
  const data = catalog(family());
  for (const sections of [
    inboxSections(data, { accent: 'blue', now }),
    projectSections(data, 'blue', {}, now),
    searchSections(data, matchCatalog(data, 'cookie'), 'blue'),
  ]) {
    const rows = sections.flatMap((s) => s.rows);
    const ids = rows.map((row) => row.id);
    for (const hidden of ['tests', 'explore', 'side', 'old'])
      assert.ok(!ids.includes(hidden), `${hidden} has no row of its own`);
    const root = rows.find((row) => row.id === 'root');
    assert.ok(root, 'the parent row stays');
    assert.equal(root.subtitle, 'Needs you in “Refactor tests”');
    assert.match(root.value, /^3 chats · /);
    assert.equal(root.badge, 'Needs you');
  }
  const attention = inboxSections(data, { accent: 'blue', now }).find(
    (section) => section.id === 'attention',
  );
  assert.deepEqual(
    attention.rows.map((row) => row.id),
    ['root'],
  );
});

test('an unread child makes the parent unread; an orphan keeps its own row', () => {
  const sessions = [
    session('root'),
    session('tab', {
      parentSessionId: 'root',
      lastMessageAt: now - 1000,
      lastReadAt: now - 2000,
    }),
    session('orphan', { parentSessionId: 'missing' }),
  ];
  const rows = inboxSections(catalog(sessions), {
    accent: 'blue',
    now,
  }).flatMap((s) => s.rows);
  assert.equal(rows.find((row) => row.id === 'root').unread, true);
  assert.ok(rows.some((row) => row.id === 'orphan'));
});
