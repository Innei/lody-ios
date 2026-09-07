import assert from 'node:assert/strict';
import test from 'node:test';
import { inboxSections } from '../../src/features/sessions/inbox.ts';
import { listPlaceholder, searchPlaceholder } from '../../src/ui/listState.ts';
import { draftTitle } from '../../src/features/sessions/draftTitle.ts';
import { setLocale } from '../../src/i18n/index.ts';

setLocale('zh-Hans');

const ACCENT = '#3B4FD9';
const now = Date.parse('2026-09-06T15:00:00+08:00');

const session = (id, status, extra = {}) => ({
  id,
  machineId: 'm1',
  title: id,
  status,
  archived: false,
  projectId: 'p1',
  createdAt: '2026-09-06T14:00:00+08:00',
  ...extra,
});

const catalog = (sessions, projects = [{ id: 'p1', name: 'lody-ios' }]) => ({
  projects,
  sessions,
  machineIds: ['m1'],
});

const build = (data, options = {}) =>
  inboxSections(data, { accent: ACCENT, now, ...options });

test('groups run attention, live, unread completed, then dated history', () => {
  const sections = build(
    catalog([
      session('done-1', 'completed', {
        lastMessageAt: now - 60_000,
        lastReadAt: now,
      }),
      session('live-1', 'running'),
      session('wait-1', 'waiting'),
    ]),
  );
  assert.deepEqual(
    sections.map((s) => s.id),
    ['attention', 'live', 'today'],
  );
  assert.deepEqual(
    sections.map((s) => s.header),
    ['需要你确认', '进行中', '今天'],
  );
});

test('empty groups are not rendered at all', () => {
  const sections = build(catalog([session('live-1', 'running')]));
  assert.deepEqual(
    sections.map((s) => s.id),
    ['live'],
  );
});

test('errors join waiting under 需要你确认', () => {
  const [first] = build(
    catalog([session('err', 'error'), session('wait', 'waiting')]),
  );
  assert.equal(first.id, 'attention');
  assert.equal(first.header, '需要你确认');
  assert.equal(first.rows.length, 2);
});

test('archived sessions stay out of the inbox until searched', () => {
  const data = catalog([session('old', 'completed', { archived: true })]);
  assert.deepEqual(build(data), []);
  assert.equal(build(data, { keyword: 'old' })[0].rows[0].id, 'old');
});

test('search matches the project name, not only the title', () => {
  const data = catalog([session('s1', 'running')]);
  assert.equal(build(data, { keyword: 'LODY-IOS' })[0].rows.length, 1);
  assert.deepEqual(build(data, { keyword: 'yohaku' }), []);
});

test('subtitle is the project; time and status sit in trailing slots', () => {
  const [group] = build(catalog([session('s1', 'waiting')]));
  assert.equal(group.rows[0].subtitle, 'lody-ios');
  assert.equal(group.rows[0].value, '1 小时前');
  assert.equal(group.rows[0].badge, '等你确认');
  assert.equal(group.rows[0].disclosure, undefined);
  assert.equal(group.rows[0].image, undefined);
});

test('only live rows carry the accent tint', () => {
  const sections = build(
    catalog([session('live', 'running'), session('wait', 'waiting')]),
  );
  const rows = Object.fromEntries(
    sections.flatMap((s) => s.rows.map((row) => [row.id, row])),
  );
  assert.equal(rows.live.imageTint, ACCENT);
  assert.equal(rows.live.badge, undefined);
  assert.equal(rows.wait.imageTint, 'warning');
  assert.equal(rows.wait.badge, '等你确认');
});

test('unread completed sits in 待查看 and is not also dated', () => {
  const sections = build(
    catalog([
      session('fresh', 'completed', { lastMessageAt: now - 60_000 }),
      session('seen', 'completed', {
        lastMessageAt: now - 60_000,
        lastReadAt: now,
      }),
    ]),
  );
  assert.deepEqual(
    sections.map((s) => [s.id, s.header, s.rows.map((r) => r.id)]),
    [
      ['unread', '已完成 · 待查看', ['fresh']],
      ['today', '今天', ['seen']],
    ],
  );
  assert.equal(sections[0].rows[0].unread, true);
  assert.equal(sections[1].rows[0].unread, false);
});

test('awaiting user beats unread completed', () => {
  const [group] = build(
    catalog([
      session('review', 'completed', {
        lastMessageAt: now - 60_000,
        awaitingUserSince: now - 60_000,
      }),
    ]),
  );
  assert.equal(group.id, 'attention');
  assert.equal(group.rows[0].id, 'review');
});

test('read history splits across today, yesterday, week, month and older', () => {
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  const today = start.getTime();
  const day = 24 * 60 * 60 * 1000;
  const read = (id, at) =>
    session(id, 'completed', { lastMessageAt: at, lastReadAt: at + 1 });
  const sections = build(
    catalog([
      read('today', today + 12 * 60 * 60 * 1000),
      read('yesterday', today - day + 12 * 60 * 60 * 1000),
      read('week', today - 4 * day),
      read('month', today - 18 * day),
      read('older', today - 40 * day),
    ]),
  );
  assert.deepEqual(
    sections.map((s) => [s.id, s.header, s.rows.map((r) => r.id)]),
    [
      ['today', '今天', ['today']],
      ['yesterday', '昨天', ['yesterday']],
      ['week', '一周内', ['week']],
      ['month', '上个月', ['month']],
      ['older', '更早', ['older']],
    ],
  );
});

test('attention, unread completed and dated history are not capped', () => {
  const many = (status, n, extra = {}) =>
    Array.from({ length: n }, (_, i) =>
      session(`${status}-${i}`, status, extra),
    );
  const sections = build(
    catalog([
      ...many('completed', 30, {
        lastMessageAt: now - 60_000,
        lastReadAt: now,
      }),
      ...many('completed', 12, { lastMessageAt: now - 30_000 }),
      ...many('waiting', 30),
    ]),
  );
  const byId = Object.fromEntries(sections.map((s) => [s.id, s.rows.length]));
  assert.equal(byId.attention, 30);
  assert.equal(byId.unread, 12);
  assert.equal(byId.today, 30);
});

test('newest sessions come first inside a group', () => {
  const [group] = build(
    catalog([
      session('older', 'running', { createdAt: '2026-09-01T10:00:00+08:00' }),
      session('newer', 'running', { createdAt: '2026-09-06T10:00:00+08:00' }),
    ]),
  );
  assert.deepEqual(
    group.rows.map((r) => r.id),
    ['newer', 'older'],
  );
});

test('placeholder covers loading, empty search, offline and first run', () => {
  assert.match(listPlaceholder({ loading: true }), /载入/);
  assert.match(listPlaceholder({ filtered: true }), /没有匹配/);
  assert.match(listPlaceholder({ connected: false }), /连接已中断/);
  assert.match(listPlaceholder({}), /连接电脑/);
  assert.match(
    searchPlaceholder({
      signedIn: false,
      query: '',
      loading: false,
      connected: true,
    }),
    /登录后/,
  );
  assert.match(
    searchPlaceholder({
      signedIn: true,
      query: '',
      loading: false,
      connected: true,
    }),
    /包括已归档/,
  );
  assert.match(
    searchPlaceholder({
      signedIn: true,
      query: 'x',
      loading: true,
      connected: true,
    }),
    /载入/,
  );
  assert.match(
    searchPlaceholder({
      signedIn: true,
      query: 'x',
      loading: false,
      connected: false,
    }),
    /连接已中断/,
  );
  assert.match(
    searchPlaceholder({
      signedIn: true,
      query: 'x',
      loading: false,
      connected: true,
    }),
    /没有匹配/,
  );
});

test('the session title comes from the first line of the first message', () => {
  assert.equal(draftTitle('  修复看门狗重启  \n更多细节'), '修复看门狗重启');
  assert.equal(draftTitle(''), '新会话');
  assert.equal(draftTitle('a'.repeat(40)), `${'a'.repeat(24)}…`);
  assert.equal(draftTitle('\n\n真正的第一行'), '真正的第一行');
});

test('projects default to expanded, honor saved collapse, and show More only beyond five sessions', async () => {
  const { projectSections } =
    await import('../../src/features/sessions/inbox.ts');
  for (const count of [0, 5, 6]) {
    const data = catalog([
      ...Array.from({ length: count }, (_, i) =>
        session(`s${i}`, 'completed', {
          createdAt: `2026-09-0${i + 1}T10:00:00Z`,
        }),
      ),
      session('archived', 'completed', { archived: true }),
    ]);
    assert.equal(projectSections(data, ACCENT)[0].headerExpanded, true);
    assert.equal(
      projectSections(data, ACCENT)[0].rows.length,
      Math.min(count, 5) + (count > 5 ? 1 : 0),
    );
    const [group] = projectSections(data, ACCENT, { p1: true });
    assert.equal(group.headerExpanded, true);
    assert.equal(group.headerActionId, 'toggle:p1');
    assert.equal(
      group.rows.some((row) => row.title === '更多'),
      count > 5,
    );
    assert.deepEqual(
      group.rows.filter((row) => row.id !== 'project:p1').map((row) => row.id),
      Array.from({ length: Math.min(count, 5) }, (_, i) => `s${count - i - 1}`),
    );
    if (count > 5) assert.equal(group.rows.at(-1).id, 'project:p1');
    assert.equal(group.footer, undefined);
    assert.equal(group.headerValue, undefined);
    const [collapsed] = projectSections(data, ACCENT, { p1: false });
    assert.equal(collapsed.rows.length, 0);
    assert.equal(collapsed.headerValue, String(count));
  }
});

test('project rows carry branch or agent, diff, activity time, unread and a badge', async () => {
  const { projectSections, sessionRow } =
    await import('../../src/features/sessions/inbox.ts');
  const at = (iso) => Date.parse(iso);
  const data = catalog([
    session('quiet', 'idle', {
      agentType: 'claude',
      lastMessageAt: at('2026-09-06T14:30:00+08:00'),
      lastReadAt: at('2026-09-06T14:30:00+08:00'),
    }),
    session('busy', 'idle', {
      branchName: 'feat/map',
      diff: { add: 42, del: 7 },
      awaitingUserSince: at('2026-09-06T14:50:00+08:00'),
      lastMessageAt: at('2026-09-06T14:50:00+08:00'),
      lastReadAt: at('2026-09-06T14:00:00+08:00'),
    }),
  ]);
  const [group] = projectSections(data, ACCENT, {}, now);
  assert.deepEqual(
    group.rows.map((r) => r.id),
    ['busy', 'quiet'],
  );
  const [busy, quiet] = group.rows;
  assert.equal(busy.subtitle, 'feat/map');
  assert.equal(busy.subtitleMono, true);
  assert.deepEqual(busy.diff, { add: 42, del: 7 });
  assert.equal(busy.value, '10 分钟前');
  assert.equal(busy.unread, true);
  assert.equal(busy.badge, '等你确认');
  assert.equal(busy.image, undefined);
  assert.equal(busy.imageTint, 'warning');
  assert.equal(busy.disclosure, undefined);
  assert.equal(quiet.subtitle, 'Claude Code');
  assert.equal(quiet.subtitleMono, false);
  assert.equal(quiet.unread, false);
  assert.equal(quiet.badge, undefined);
  assert.equal(quiet.image, undefined);
  assert.equal(
    sessionRow(data.sessions[0], ACCENT, 'lody-ios', now).subtitle,
    'lody-ios · Claude Code',
  );
});

test('search finds empty projects and archived sessions without the inbox limit', async () => {
  const { searchSections } =
    await import('../../src/features/sessions/inbox.ts');
  const data = catalog(
    Array.from({ length: 25 }, (_, i) =>
      session(`work-${i}`, 'completed', { archived: true }),
    ),
    [
      { id: 'p1', name: 'Lody' },
      { id: 'p2', name: 'Lody empty' },
    ],
  );
  assert.deepEqual(searchSections(data, ' ', ACCENT), []);
  const found = searchSections(data, ' LODY ', ACCENT);
  assert.equal(found[0].rows.length, 2);
  assert.equal(found[1].rows.length, 25);
  assert.equal(found[1].rows[0].badge, '已归档');
});
