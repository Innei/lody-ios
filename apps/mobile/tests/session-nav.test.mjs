import assert from 'node:assert/strict';
import test from 'node:test';
import {
  requestOpenSession,
  subscribeSessionNav,
} from '../src/features/sessions/sessionNav.ts';

const session = {
  id: 's1',
  machineId: 'm',
  title: 'T',
  status: 'idle',
  archived: false,
  pinned: false,
  projectId: 'p',
  createdAt: '2026-01-01',
};

test('requestOpenSession waits for the subscriber and preserves order', async () => {
  const seen = [];
  const stop = subscribeSessionNav(async (intent) => {
    seen.push(intent.kind);
  });
  await requestOpenSession(session);
  assert.deepEqual(seen, ['open']);
  stop();
});

test('intents queue until a subscriber attaches', async () => {
  const seen = [];
  const pending = requestOpenSession(session);
  const stop = subscribeSessionNav(async (intent) => {
    seen.push(intent.kind);
  });
  await pending;
  assert.deepEqual(seen, ['open']);
  stop();
});

test('handler throw is swallowed by requestOpenSession', async () => {
  const stop = subscribeSessionNav(async () => {
    throw new Error('boom');
  });
  await requestOpenSession(session);
  stop();
});
