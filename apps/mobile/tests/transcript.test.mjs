import test from 'node:test';
import assert from 'node:assert/strict';
import { aggregate } from '../src/features/sessions/transcript/aggregate.ts';
import { setLocale } from '../src/i18n/index.ts';

setLocale('zh-Hans');

const tool = (id, kind, extra = {}) => ({
  itemId: id,
  rev: 1,
  type: 'tool_call',
  kind,
  title: '',
  status: 'completed',
  hasDetail: true,
  ...extra,
});

test('连续同类工具合成一行，被正文打断则起新行', () => {
  const rows = aggregate([
    { itemId: 't1', rev: 1, type: 'text', text: '开始' },
    tool('a', 'read'),
    tool('b', 'search'),
    { itemId: 't2', rev: 1, type: 'text', text: '继续' },
    tool('c', 'read'),
  ]);
  assert.deepEqual(
    rows.map((r) => r.kind),
    ['prose', 'activity', 'prose', 'activity'],
  );
  assert.deepEqual(rows[1].members, ['a', 'b']);
  assert.equal(rows[1].label, '读取了文件');
  assert.deepEqual(rows[3].members, ['c']);
});

test('单个 edit 带 path 与增删行数，多个合并只给类别', () => {
  const one = aggregate([
    tool('a', 'edit', { path: 'src/auth.ts', added: 12, removed: 3 }),
  ]);
  assert.equal(one[0].label, '编辑了 src/auth.ts +12 −3');

  const many = aggregate([
    tool('a', 'edit', { path: 'src/auth.ts', added: 12, removed: 3 }),
    tool('b', 'write', { path: 'src/x.ts', added: 1, removed: 0 }),
  ]);
  assert.equal(many[0].label, '编辑了文件');
});

test('混合 kind 最多列三类，超出用「等」', () => {
  const rows = aggregate([
    tool('a', 'read'),
    tool('b', 'execute'),
    tool('c', 'fetch'),
    tool('d', 'mcp'),
  ]);
  assert.equal(rows[0].label, '读取了文件、执行了命令、访问了网络等');
  assert.equal(rows[0].symbol, 'wrench.and.screwdriver');
});

test('运行中与失败各自标记，待授权透出 requestId', () => {
  const rows = aggregate([
    tool('a', 'execute', { status: 'in_progress' }),
    { itemId: 'x', rev: 1, type: 'text', text: '—' },
    tool('b', 'execute', { status: 'failed' }),
    { itemId: 'y', rev: 1, type: 'text', text: '—' },
    tool('c', 'execute', {
      status: 'pending',
      permission: { requestId: 'r1', pending: true },
    }),
  ]);
  assert.equal(rows[0].running, true);
  assert.equal(rows[2].failed, true);
  assert.equal(rows[2].label, '失败：执行了命令');
  assert.equal(rows[4].pendingPermission, 'r1');
});

test('plan 与 subagent_task 不参与聚合', () => {
  const rows = aggregate([
    tool('a', 'read'),
    { itemId: 'p', rev: 1, type: 'plan', entries: [] },
    tool('b', 'read'),
  ]);
  assert.deepEqual(
    rows.map((r) => r.kind),
    ['activity', 'plan', 'activity'],
  );
});

test('未知类型渲染成中性活动行，不带占位文案', () => {
  const rows = aggregate([{ itemId: 'z', rev: 1, type: 'worktree_script' }]);
  assert.equal(rows[0].kind, 'activity');
  assert.equal(rows[0].label, '调用了工具');
  assert.equal(rows[0].members.length, 1);
});

test('无详情的组标记 disabled，rev 为组内之和', () => {
  const rows = aggregate([
    tool('a', 'read', { hasDetail: false, rev: 2 }),
    tool('b', 'read', { hasDetail: false, rev: 3 }),
  ]);
  assert.equal(rows[0].hasDetail, false);
  assert.equal(rows[0].rev, 5);
  assert.equal(rows[0].itemId, 'a');
});
