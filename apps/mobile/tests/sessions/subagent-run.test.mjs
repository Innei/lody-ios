import assert from 'node:assert/strict';
import test from 'node:test';
import {
  runEntries,
  runMeta,
  liveTask,
} from '../../src/features/sessions/subagentRun.ts';
import { setLocale } from '../../src/lib/i18n/index.ts';

setLocale('en');
const task = (run, extra = {}) => ({
  itemId: 'task-1',
  rev: 1,
  type: 'subagent_task',
  taskId: 't1',
  status: 'in_progress',
  actor: 'Explore',
  run,
  ...extra,
});
const items = [
  { itemId: 'run-0', rev: 1, type: 'thought', text: 'Trace it.' },
  {
    itemId: 'grep',
    rev: 1,
    type: 'tool_call',
    kind: 'search',
    status: 'completed',
    title: 'Grep verifyToken',
  },
  { itemId: 'run-2', rev: 1, type: 'text', text: 'Six callers.' },
];

test('a run becomes one assistant turn the chat folds like any other', () => {
  const [entry] = runEntries(task({ state: 'running', items }));
  assert.equal(entry.role, 'assistant');
  assert.equal(entry.finished, false);
  assert.equal(entry.status, 'running');
  assert.deepEqual(
    entry.items.map((i) => i.itemId),
    ['run-0', 'grep', 'run-2'],
  );
  const [done] = runEntries(task({ state: 'completed', items }));
  assert.equal(done.finished, true);
  assert.equal(done.status, 'completed');
  assert.deepEqual(runEntries(task(undefined)), []);
});

test('run metadata lists only what the provider reported', () => {
  assert.equal(
    runMeta(
      task({
        state: 'running',
        modelId: 'gpt-5-codex',
        totalTokens: 3100,
        toolCallCount: 7,
        contextUsagePercent: 18,
        items,
      }),
    ),
    'gpt-5-codex · 3.1k tokens · 7 tools · context 18%',
  );
  assert.equal(
    runMeta(task({ state: 'running', totalTokens: 640, items: [] })),
    '640 tokens',
  );
});

test('the open detail follows the live task by item id', () => {
  const entries = [
    {
      id: 'e1',
      items: [task({ state: 'completed', items }, { status: 'completed' })],
    },
  ];
  assert.equal(
    liveTask(
      task({ state: 'running', items: [] }),
      'e1',
      JSON.stringify(entries),
    ).run.state,
    'completed',
  );
  assert.equal(
    liveTask(
      task({ state: 'running', items: [] }),
      'gone',
      JSON.stringify(entries),
    ).run.state,
    'running',
  );
});
