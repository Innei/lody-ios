import assert from 'node:assert/strict';
import test from 'node:test';
import { pendingSessionFromDraft } from '../../src/features/sessions/createDraft.ts';

const agent = {
  id: 'cfg',
  name: 'Codex',
  machineId: 'm1',
  machineName: 'Mac',
  cliType: 'builtin',
  agentType: 'codex',
};
const payload = {
  id: 'send-1',
  text: '\n  Fix the login bug\nwith details',
  startedAt: 5,
  attachments: [],
};

test('a native project draft becomes the outbox record the RN page wrote', () => {
  const { record, created } = pendingSessionFromDraft(
    {
      sessionId: 's1',
      userId: 'u',
      workspaceId: 'w',
      projectId: 'github:o/r',
      projectName: 'o/r',
      branch: 'main',
      agent,
      choice: { modelId: 'a', effort: 'high' },
      reasoningEffortConfigId: 'effort',
    },
    payload,
    '2026-09-26T00:00:00.000Z',
  );
  assert.deepEqual(record.session, {
    id: 's1',
    projectId: 'github:o/r',
    machineId: 'm1',
    cliType: 'builtin',
    agentType: 'codex',
    title: 'Fix the login bug',
    status: 'idle',
    archived: false,
    pinned: false,
    createdAt: '2026-09-26T00:00:00.000Z',
  });
  assert.equal(record.send.phase, 'waiting');
  assert.deepEqual(record.send.choice, {
    modelId: 'a',
    effort: 'high',
    reasoningEffortConfigId: 'effort',
  });
  assert.deepEqual(JSON.parse(record.send.creation), {
    workspaceId: 'w',
    sessionId: 's1',
    machineId: 'm1',
    agentConfigId: 'cfg',
    userId: 'u',
    title: 'Fix the login bug',
    projectId: 'github:o/r',
    branch: 'main',
  });
  assert.equal(created.composerRelayId, 'send-1');
  assert.equal(created.projectName, 'o/r');
});

test('a chat draft targets the machine chat bucket without project or branch', () => {
  const { record } = pendingSessionFromDraft(
    {
      sessionId: 's2',
      userId: 'u',
      workspaceId: 'w',
      projectName: '',
      agent,
      choice: {},
    },
    payload,
  );
  assert.equal(record.session.projectId, 'm1:unassigned');
  const creation = JSON.parse(record.send.creation);
  assert.equal(creation.projectId, undefined);
  assert.equal(creation.branch, undefined);
});
