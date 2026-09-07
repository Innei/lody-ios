import assert from 'node:assert/strict';
import { test } from 'node:test';
import { changedFiles } from '../../src/features/sessions/transcript/changes.ts';

const tool = (kind, path, added, removed) => ({
  itemId: `${kind}:${path}`,
  rev: 1,
  type: 'tool_call',
  kind,
  title: '',
  status: 'completed',
  path,
  added,
  removed,
  hasDetail: true,
});

test('changed files merge per path, ignore reads, and keep deletes', () => {
  const entry = {
    id: 'e1',
    rev: 1,
    role: 'assistant',
    status: 'completed',
    finished: true,
    items: [
      tool('read', 'a.ts'),
      tool('edit', 'a.ts', 3, 1),
      tool('edit', 'a.ts', 2, 0),
      tool('write', 'b.ts', 10, 0),
      tool('delete', 'c.ts', 0, 4),
      tool('other', 'd.ts', 1, 1),
      { itemId: 't', rev: 1, type: 'text', text: 'done' },
      {
        itemId: 'x',
        rev: 1,
        type: 'tool_call',
        kind: 'bash',
        title: 'ls',
        status: 'completed',
        hasDetail: false,
      },
    ],
  };
  assert.deepEqual(changedFiles(entry), [
    { path: 'a.ts', add: 5, del: 1, status: 'M' },
    { path: 'b.ts', add: 10, del: 0, status: 'A' },
    { path: 'c.ts', add: 0, del: 4, status: 'D' },
    { path: 'd.ts', add: 1, del: 1, status: 'M' },
  ]);
  assert.deepEqual(
    changedFiles({ ...entry, items: [tool('read', 'a.ts')] }),
    [],
  );
});

test('machine-recorded counts override tool diffs for the same file', () => {
  const entry = {
    id: 'e2',
    rev: 1,
    role: 'assistant',
    status: 'completed',
    finished: true,
    items: [tool('edit', 'b.ts', 1, 0), tool('edit', 'fallback.ts', 2, 1)],
    fileDiffs: [
      { path: 'x.ts', add: 4, del: 2 },
      { path: 'b.ts', add: 9, del: 9 },
    ],
  };
  assert.deepEqual(changedFiles(entry), [
    { path: 'x.ts', add: 4, del: 2, status: 'M' },
    { path: 'b.ts', add: 9, del: 9, status: 'M' },
    { path: 'fallback.ts', add: 2, del: 1, status: 'M' },
  ]);
});
