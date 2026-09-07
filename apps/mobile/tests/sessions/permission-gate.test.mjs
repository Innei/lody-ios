import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createPermissionGate,
  firstPermissionTarget,
} from '../../src/features/sessions/permissionTarget.ts';

const tool = (id, extra = {}) => ({
  itemId: id,
  rev: 1,
  type: 'tool_call',
  kind: 'execute',
  title: 'rm -rf build',
  status: 'pending',
  hasDetail: true,
  ...extra,
});
const entry = (id, items) => ({
  id,
  rev: 1,
  role: 'assistant',
  status: 'running',
  finished: false,
  items,
});
const pending = (requestId) => ({ requestId, pending: true });

test('取首个待批准的工具调用，答复过的和非工具项都跳过', () => {
  const target = firstPermissionTarget([
    entry('e1', [
      { itemId: 't', rev: 1, type: 'text', text: '开始' },
      tool('a', { permission: { requestId: 'r0', pending: false } }),
    ]),
    entry('e2', [
      tool('b', {
        permission: pending('r1'),
        path: 'build',
        kind: 'delete',
        title: '删除 build',
      }),
      tool('c', { permission: pending('r2') }),
    ]),
  ]);
  assert.deepEqual(target, {
    entryId: 'e2',
    itemId: 'b',
    requestId: 'r1',
    kind: 'delete',
    title: '删除 build',
    path: 'build',
  });
});

test('没有待批准项时返回 undefined', () => {
  assert.equal(firstPermissionTarget([]), undefined);
  assert.equal(
    firstPermissionTarget([
      entry('e1', [
        tool('a', { permission: { requestId: 'r', pending: false } }),
      ]),
    ]),
    undefined,
  );
});

test('同一请求在弹出期间不重复弹，作答后也不再弹', () => {
  const gate = createPermissionGate();
  const target = { requestId: 'r1' };
  assert.equal(gate.shouldOpen(target), true);
  gate.opened();
  assert.equal(gate.shouldOpen(target), false, '弹出期间不重复');
  gate.settled({ status: 'completed', value: { requestId: 'r1' } });
  assert.equal(gate.shouldOpen(target), false, '已作答不再弹');
  assert.equal(gate.shouldOpen({ requestId: 'r2' }), true, '新请求照弹');
});

test('主动关闭后本次挂载内不再自动弹，包括后来的新请求', () => {
  const gate = createPermissionGate();
  gate.opened();
  gate.settled({ status: 'cancelled' });
  assert.equal(gate.shouldOpen({ requestId: 'r1' }), false);
  assert.equal(gate.shouldOpen({ requestId: 'r2' }), false);
});

test('探测模式空手而归不算关闭，后续请求仍会自动弹', () => {
  const gate = createPermissionGate();
  gate.opened();
  gate.settled({ status: 'completed', value: undefined });
  assert.equal(gate.shouldOpen({ requestId: 'r1' }), true);
});
