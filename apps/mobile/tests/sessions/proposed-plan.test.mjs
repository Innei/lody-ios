import assert from 'node:assert/strict';
import test from 'node:test';
import {
  latestProposedPlan,
  planExecutionChoice,
  createPlanDecision,
} from '../../src/features/sessions/proposedPlan.ts';
const entry = (overrides = {}) => ({
  id: 'answer',
  role: 'assistant',
  items: [
    {
      type: 'proposed_plan',
      itemId: 'plan',
      turnId: 'turn',
      status: 'completed',
      isLatest: true,
      markdown: '# Plan',
      ...overrides,
    },
  ],
});
const target = latestProposedPlan([entry()]);
test('only the current completed nonempty plan before new user input is actionable', () => {
  assert.deepEqual(target, {
    entryId: 'answer',
    itemId: 'plan',
    turnId: 'turn',
  });
  for (const patch of [
    { status: 'delta' },
    { status: 'cleared' },
    { isLatest: false },
    { markdown: '  ' },
  ])
    assert.equal(latestProposedPlan([entry(), entry(patch)]), undefined);
  assert.equal(
    latestProposedPlan([entry(), { role: 'user', items: [] }]),
    undefined,
  );
});
test('execution exits core and legacy planning while preserving model, effort and permissions', () => {
  const choice = {
    modelId: 'model',
    effort: 'high',
    modeId: 'read-only',
    configOptionValues: {
      plan_mode: true,
      permission_mode: 'read-only',
      fast: true,
    },
  };
  assert.deepEqual(planExecutionChoice(choice), {
    ...choice,
    configOptionValues: { ...choice.configOptionValues, plan_mode: false },
  });
  assert.equal(choice.configOptionValues.plan_mode, true);
  assert.equal(planExecutionChoice({ modeId: 'plan' }).modeId, 'plan');
  const legacy = planExecutionChoice(
    {
      modeId: 'plan',
      configOptionValues: {
        collaboration_mode: 'plan',
        permission_mode: 'ask',
      },
    },
    { legacyModes: [{ id: 'plan' }, { id: 'default' }] },
  );
  assert.equal(legacy.modeId, 'default');
  assert.deepEqual(legacy.configOptionValues, {
    collaboration_mode: 'default',
    permission_mode: 'ask',
  });
  assert.equal(
    planExecutionChoice(
      {},
      {
        configOptions: [
          { id: 'plan_mode', type: 'boolean', currentValue: true },
        ],
      },
    ).configOptionValues.plan_mode,
    false,
  );
  assert.equal(
    planExecutionChoice(
      {},
      {
        configOptions: [
          {
            id: 'custom',
            category: 'collaboration_mode',
            type: 'select',
            currentValue: 'plan',
            options: [{ id: 'default' }],
          },
        ],
      },
    ).configOptionValues.custom,
    'default',
  );
});
test('stale/disabled taps and duplicate pending or accepted execution never send', async () => {
  let enabled = false,
    complete;
  const calls = [];
  const controller = createPlanDecision(
    () => ({ target, enabled }),
    async (id) => {
      calls.push(id);
      return await new Promise((resolve) => {
        complete = resolve;
      });
    },
  );
  await controller.decide('answer', 'plan', 'execute', 'disabled');
  enabled = true;
  await controller.decide('old', 'plan', 'execute', 'stale');
  const pending = controller.decide('answer', 'plan', 'execute', 'one');
  await controller.decide('answer', 'plan', 'execute', 'two');
  assert.deepEqual(calls, ['one']);
  complete('{"state":"accepted"}');
  await pending;
  await controller.decide('answer', 'plan', 'execute', 'three');
  assert.deepEqual(calls, ['one']);
});
test('continue discussing only dismisses; definite failures can retry, unknown delivery cannot', async () => {
  let calls = 0;
  const controller = createPlanDecision(
    () => ({ target, enabled: true }),
    async () => {
      calls++;
      return '{"state":"not_sent"}';
    },
  );
  await controller.decide('answer', 'plan', 'execute', 'one');
  assert.equal(controller.getSnapshot().phase, 'failed');
  await controller.decide('answer', 'plan', 'execute', 'two');
  assert.equal(calls, 2);
  await controller.decide('answer', 'plan', 'discuss', '');
  assert.equal(controller.getSnapshot().phase, 'dismissed');
  await controller.decide('answer', 'plan', 'execute', 'three');
  assert.equal(calls, 2);
  for (const response of [
    async () => {
      throw Error('lost');
    },
    async () => '{"state":"unknown"}',
    async () => '{broken',
  ]) {
    let count = 0;
    const unknown = createPlanDecision(
      () => ({ target, enabled: true }),
      async () => {
        count++;
        return response();
      },
    );
    await unknown.decide('answer', 'plan', 'execute', 'one');
    await unknown.decide('answer', 'plan', 'execute', 'two');
    assert.equal(count, 1);
    assert.equal(unknown.getSnapshot().phase, 'unknown');
  }
});
