import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createAgentErrorRetry,
  latestRetryableError,
} from '../../src/features/sessions/agentErrorRetry.ts';

const failure = (reason = 'acp_provider_overloaded', id = 'failure') => ({
  id,
  role: 'system',
  items: [
    {
      itemId: 'error',
      type: 'system_notice',
      name: 'chat_failed',
      meta: { reason },
    },
  ],
});
const target = latestRetryableError([failure()]);

test('only the latest recoverable failure before newer user input can retry', () => {
  assert.equal(
    latestRetryableError([failure(), { id: 'user', role: 'user', items: [] }]),
    undefined,
  );
  assert.equal(
    latestRetryableError([failure(), failure('acp_auth_required', 'auth')]),
    undefined,
  );
  assert.equal(latestRetryableError([failure('future_reason')]), undefined);
  assert.deepEqual(
    latestRetryableError([{ role: 'user', id: 'user', items: [] }, failure()]),
    target,
  );
});

test('a retry is fenced while pending and after ACK; stale targets and disabled sessions do not dispatch', async () => {
  let enabled = false;
  let resolve;
  const calls = [];
  const controller = createAgentErrorRetry(
    () => ({ target, enabled }),
    async (_, id) => {
      calls.push(id);
      return await new Promise((done) => {
        resolve = done;
      });
    },
  );
  await controller.retry('failure', 'error', 'one');
  enabled = true;
  await controller.retry('old', 'error', 'one');
  assert.equal(calls.length, 0);
  const pending = controller.retry('failure', 'error', 'one');
  assert.equal(controller.getSnapshot().phase, 'pending');
  await controller.retry('failure', 'error', 'two');
  assert.deepEqual(calls, ['one']);
  resolve(JSON.stringify({ state: 'accepted' }));
  await pending;
  assert.equal(controller.getSnapshot().phase, 'accepted');
  await controller.retry('failure', 'error', 'three');
  assert.deepEqual(calls, ['one']);
});

test('definite rejection allows an explicit new attempt; ambiguous delivery never repeats', async () => {
  let count = 0;
  const controller = createAgentErrorRetry(
    () => ({ target, enabled: true }),
    async () => {
      count++;
      if (count === 1) return JSON.stringify({ state: 'not_sent' });
      throw new Error('ACK lost');
    },
  );
  await controller.retry('failure', 'error', 'one');
  assert.equal(controller.getSnapshot().phase, 'failed');
  await controller.retry('failure', 'error', 'two');
  assert.equal(controller.getSnapshot().phase, 'unknown');
  await controller.retry('failure', 'error', 'three');
  assert.equal(count, 2);
});
