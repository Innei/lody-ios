import assert from 'node:assert/strict';
import test from 'node:test';
import {
  deliverShare,
  nextShareStep,
  selectionAvailable,
} from '../../src/features/share/shareDrain.ts';

const agent = {
  id: 'cfg',
  name: 'Codex',
  machineId: 'm1',
  machineName: 'Mac',
  cliType: 'builtin',
  agentType: 'codex',
};
const entry = {
  id: 'e1',
  userId: 'u1',
  workspaceId: 'w1',
  projectId: 'p1',
  context: 'project',
  text: 'Summarize https://example.com',
  attachments: [],
  draft: {
    sessionId: 's1',
    userId: 'u1',
    workspaceId: 'w1',
    projectId: 'p1',
    projectName: 'Alpha',
    agent,
    choice: {},
  },
};
const state = {
  userId: 'u1',
  workspaceIds: ['w1', 'w2'],
  selectedId: 'w1',
  loading: false,
};

test('the drain fences accounts, switches workspace and waits for its catalog', () => {
  assert.deepEqual(nextShareStep([], state), { kind: 'idle' });
  assert.deepEqual(nextShareStep([{ ...entry, userId: 'u2' }], state), {
    kind: 'discard',
    id: 'e1',
  });
  assert.deepEqual(nextShareStep([{ ...entry, workspaceId: 'gone' }], state), {
    kind: 'discard',
    id: 'e1',
  });
  assert.deepEqual(nextShareStep([{ ...entry, workspaceId: 'w2' }], state), {
    kind: 'workspace',
    id: 'w2',
  });
  assert.deepEqual(nextShareStep([entry], { ...state, loading: true }), {
    kind: 'wait',
  });
  assert.equal(
    nextShareStep([entry, { ...entry, id: 'e2' }], state).entry.id,
    'e1',
  );
});

function harness(overrides = {}) {
  const calls = [];
  const deps = {
    adopt: () => entry,
    remove: (id) => calls.push(['remove', id]),
    agentAvailable: async () => true,
    put: async (record) => calls.push(['put', record.session.id]),
    openSession: (session) => calls.push(['open', session.id]),
    openForm: async (value) => calls.push(['form', value.text]),
    toast: (key) => calls.push(['toast', key]),
    now: () => 1,
    ...overrides,
  };
  return { calls, deps };
}

test('a ready draft is saved to the outbox before its entry is removed and opened', async () => {
  const { calls, deps } = harness();
  await deliverShare(entry, deps);
  assert.deepEqual(calls, [
    ['put', 's1'],
    ['remove', 'e1'],
    ['open', 's1'],
  ]);
});

test('a failed outbox save keeps the entry for the next drain', async () => {
  const { calls, deps } = harness({
    put: async () => {
      throw new Error('disk');
    },
  });
  await deliverShare(entry, deps);
  assert.deepEqual(calls, [['toast', 'shareInbox.saveFailed']]);
});

test('an unresolved or stale selection opens the pre-filled form', async () => {
  for (const overrides of [
    { adopt: () => ({ ...entry, draft: undefined }) },
    { agentAvailable: async () => false },
  ]) {
    const { calls, deps } = harness(overrides);
    await deliverShare(entry, deps);
    assert.deepEqual(calls, [
      ['remove', 'e1'],
      ['form', entry.text],
    ]);
  }
});

test('an unreadable entry is dropped with a notice', async () => {
  const { calls, deps } = harness({
    adopt: () => {
      throw new Error('missing');
    },
  });
  await deliverShare(entry, deps);
  assert.deepEqual(calls, [
    ['remove', 'e1'],
    ['toast', 'shareInbox.unreadable'],
  ]);
});

test('an entry whose save failed is skipped until the next wake', () => {
  assert.deepEqual(
    nextShareStep([entry, { ...entry, id: 'e2' }], {
      ...state,
      skip: new Set(['e1']),
    }).entry.id,
    'e2',
  );
  assert.deepEqual(
    nextShareStep([entry], { ...state, skip: new Set(['e1']) }),
    { kind: 'idle' },
  );
});

test('a stale agent or model sends the draft to the pre-filled form', () => {
  const options = {
    sessionId: 'x',
    agents: [agent],
    capabilities: [
      {
        machineId: 'm1',
        cliType: 'builtin',
        agentType: 'codex',
        models: [{ id: 'a', name: 'A' }],
        modes: [],
        reasoningEfforts: {},
      },
    ],
  };
  assert.equal(selectionAvailable(entry.draft, options), true);
  assert.equal(
    selectionAvailable({ ...entry.draft, choice: { modelId: 'a' } }, options),
    true,
  );
  assert.equal(
    selectionAvailable(
      { ...entry.draft, choice: { modelId: 'gone' } },
      options,
    ),
    false,
  );
  assert.equal(
    selectionAvailable(entry.draft, { ...options, agents: [] }),
    false,
  );
});

test('deliverShare reports whether the entry was kept', async () => {
  const kept = harness({
    put: async () => {
      throw new Error('disk');
    },
  });
  assert.equal(await deliverShare(entry, kept.deps), 'kept');
  assert.equal(await deliverShare(entry, harness().deps), 'done');
});
