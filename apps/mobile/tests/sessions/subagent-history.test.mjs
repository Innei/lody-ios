import assert from 'node:assert/strict';
import test from 'node:test';
import {
  findSessionItem,
  subagentEntries,
} from '../../src/features/sessions/subagentHistory.ts';

test('subtask history retains thought, tools and plan order, and appends a missing result once', () => {
  const task = {
    itemId: 'task',
    taskId: 't1',
    rev: 2,
    type: 'subagent_task',
    status: 'completed',
    summary: 'Finished',
    run: {
      sessionId: 'child',
      state: 'completed',
      items: [
        { itemId: 'thought', type: 'thought', text: 'Check callers', rev: 1 },
        { itemId: 'tool', type: 'tool_call', title: 'Read', rev: 1 },
        { itemId: 'plan', type: 'plan', entries: [], rev: 1 },
      ],
    },
  };
  const entries = subagentEntries('reply', task);
  assert.equal(entries[0].finished, true);
  assert.deepEqual(
    entries[0].items.map((item) => item.type),
    ['thought', 'tool_call', 'plan', 'text'],
  );
  assert.equal(
    findSessionItem([{ id: 'reply', items: [task] }], 'reply', 'tool'),
    task.run.items[1],
  );
  assert.equal(
    findSessionItem([{ id: 'reply', items: [task] }], 'other', 'tool'),
    undefined,
  );
  task.run.items.push({
    itemId: 'answer',
    type: 'text',
    text: 'Finished',
    rev: 1,
  });
  assert.equal(subagentEntries('reply', task)[0].items.length, 4);
  assert.equal(task.run.items.length, 4);
  assert.deepEqual(subagentEntries('reply', { ...task, run: undefined }), []);
  const failed = subagentEntries('reply', {
    ...task,
    status: 'failed',
    error: 'Disconnected',
    run: { ...task.run, state: 'failed' },
  });
  assert.equal(failed[0].items.at(-1).text, 'Disconnected');
});
