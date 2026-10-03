import assert from 'node:assert/strict';
import test from 'node:test';
import {
  conversationSections,
  conversationBadge,
  conversationTitle,
} from '../../src/features/sessions/conversationSheet.ts';
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
const sessions = [
  session('root', { title: 'Fix login redirect loop' }),
  session('tests', {
    title: 'Refactor tests',
    parentSessionId: 'root',
    status: 'requestPermission',
    awaitingUserSince: now - 5000,
    createdAt: new Date(now - 50_000).toISOString(),
  }),
  session('explore', {
    title: 'Explore auth flow',
    parentSessionId: 'root',
    lastMessageAt: now - 1000,
    lastReadAt: now - 2000,
    createdAt: new Date(now - 40_000).toISOString(),
  }),
  session('side', {
    title: 'Why does the cookie expire?',
    parentSessionId: 'root',
    childSessionPlacement: 'side-panel',
    status: 'running',
  }),
  session('old', { title: 'Old tab', parentSessionId: 'root', archived: true }),
];
const ids = (section) => section.rows.map((row) => row.id);

test('tabs list Main first and mark the active conversation', () => {
  const sections = conversationSections(sessions, 'root', 'tests', {
    accent: 'blue',
    now,
  });
  assert.deepEqual(
    sections.map((s) => s.id),
    ['tabs', 'sideChats', 'archived'],
  );
  const [tabs, side, archived] = sections;
  assert.deepEqual(ids(tabs), ['root', 'tests', 'explore']);
  assert.equal(tabs.rows[0].badge, 'Main');
  assert.equal(tabs.rows[1].selected, true);
  assert.equal(tabs.rows[0].selected, false);
  assert.match(tabs.rows[1].subtitle, /^Needs approval · /);
  assert.equal(tabs.rows[2].unread, true);
  assert.deepEqual(ids(side), ['side']);
  assert.match(side.rows[0].subtitle, /^Running · /);
  assert.deepEqual(ids(archived), ['old']);
  assert.equal(side.rows[0].actions, undefined);
});

test('creation rows and side chat deletion appear only with a service', () => {
  const sections = conversationSections(sessions, 'root', 'root', {
    accent: 'blue',
    now,
    create: { sideChat: 'enabled' },
  });
  const [tabs, side] = sections;
  assert.equal(tabs.rows.at(-1).id, 'new-tab');
  assert.equal(side.rows.at(-1).id, 'new-side-chat');
  assert.equal(side.rows.at(-1).action, true);
  assert.equal(side.rows[0].actions[0].id, 'delete');

  const offline = conversationSections(sessions, 'root', 'root', {
    accent: 'blue',
    now,
    create: { sideChat: 'disabled', offlineReason: 'MacBook Pro is offline' },
  })[1].rows.at(-1);
  assert.equal(offline.action, false);
  assert.equal(offline.subtitle, 'MacBook Pro is offline');

  const hidden = conversationSections(sessions, 'root', 'root', {
    accent: 'blue',
    now,
    create: { sideChat: 'hidden' },
  });
  assert.ok(!hidden.flatMap(ids).includes('new-side-chat'));
});

test('a lone session gets a side chat section only when it can create one', () => {
  const lone = [session('solo')];
  assert.deepEqual(
    conversationSections(lone, 'solo', 'solo', { accent: 'blue', now }).map(
      (s) => s.id,
    ),
    ['tabs'],
  );
  assert.deepEqual(
    conversationSections(lone, 'solo', 'solo', {
      accent: 'blue',
      now,
      create: { sideChat: 'enabled' },
    }).map((s) => s.id),
    ['tabs', 'sideChats'],
  );
});

test('the header badge counts other conversations that need the user', () => {
  assert.equal(conversationBadge(sessions, 'root', 'root'), 1);
  assert.equal(conversationBadge(sessions, 'root', 'tests'), 0);
});

test('the title names the active conversation and its parent', () => {
  assert.deepEqual(conversationTitle(sessions, 'root', 'root'), {
    title: 'Fix login redirect loop',
    subtitle: 'Main · 4 conversations',
  });
  assert.deepEqual(conversationTitle(sessions, 'root', 'tests'), {
    title: 'Refactor tests',
    subtitle: 'in Fix login redirect loop',
  });
  assert.equal(conversationTitle([session('solo')], 'solo', 'solo'), undefined);
});
