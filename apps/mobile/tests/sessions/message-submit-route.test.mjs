import assert from 'node:assert/strict';
import test from 'node:test';
import { resolveSessionMessageSubmitRoute } from '../../src/features/sessions/messageSubmitRoute.ts';

const resolve = (overrides = {}) =>
  resolveSessionMessageSubmitRoute({
    forceDirect: false,
    forceQueue: false,
    isPromptBusy: false,
    hasUnfinishedAssistantTurn: false,
    queuedMessageBehavior: 'queue',
    ...overrides,
  });

test('direct-dispatches only when both live and transcript activity are idle', () => {
  assert.deepEqual(resolve(), { type: 'direct_dispatch' });
});

test('queues across the history-before-presence ordering window', () => {
  assert.deepEqual(resolve({ hasUnfinishedAssistantTurn: true }), {
    type: 'queue',
    reason: 'unfinished_assistant_turn',
  });
});

test('does not steer without positive live prompt activity', () => {
  assert.deepEqual(
    resolve({
      hasUnfinishedAssistantTurn: true,
      queuedMessageBehavior: 'guide',
    }),
    { type: 'queue', reason: 'unfinished_assistant_turn' },
  );
});

test('steers only a live prompt with a known unfinished assistant turn', () => {
  assert.deepEqual(
    resolve({
      isPromptBusy: true,
      hasUnfinishedAssistantTurn: true,
      queuedMessageBehavior: 'guide',
    }),
    { type: 'guide' },
  );
});

test('queues a live prompt when the preference is queue', () => {
  assert.deepEqual(
    resolve({
      isPromptBusy: true,
      hasUnfinishedAssistantTurn: true,
    }),
    { type: 'queue', reason: 'prompt_busy' },
  );
});

test('honors explicit route overrides with forceDirect taking precedence', () => {
  assert.deepEqual(resolve({ forceQueue: true }), {
    type: 'queue',
    reason: 'forced',
  });
  assert.deepEqual(
    resolve({
      forceDirect: true,
      forceQueue: true,
      isPromptBusy: true,
      hasUnfinishedAssistantTurn: true,
      queuedMessageBehavior: 'guide',
    }),
    { type: 'direct_dispatch' },
  );
});

test('unknown stored values behave as queue', () => {
  assert.deepEqual(
    resolve({
      isPromptBusy: true,
      hasUnfinishedAssistantTurn: true,
      queuedMessageBehavior: 'steer',
    }),
    { type: 'queue', reason: 'prompt_busy' },
  );
});
