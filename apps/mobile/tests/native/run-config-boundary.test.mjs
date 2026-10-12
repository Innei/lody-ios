import test from 'node:test';
import assert from 'node:assert/strict';
import { openTestSession } from '../helpers.mjs';

test('a combined Role and independent configuration preserves all 128 options; 129 cannot write', async () => {
  const roleOptions = Object.fromEntries(
    Array.from({ length: 64 }, (_, index) => [
      `role-option-${index}`,
      `Role ${index} ${'界'.repeat(500)}`,
    ]),
  );
  const independentOptions = Object.fromEntries(
    Array.from({ length: 64 }, (_, index) => [
      `independent-option-${index}`,
      index % 2 === 0 ? false : `Option ${index}`,
    ]),
  );
  const combined = { ...roleOptions, ...independentOptions };
  const requests = [];
  const fixture = await openTestSession({
    onRpc: (request) => {
      requests.push(request);
      const persisted = fixture.server
        .toJSON()
        .history.find((entry) => entry.id === request.params.userTurnId);
      assert.deepEqual(persisted.inputConfig.configOptionValues, combined);
      assert.deepEqual(request.params.inputConfig.configOptionValues, combined);
      return { result: { accepted: true } };
    },
  });
  const send = {
    sessionId: 's1',
    machineId: 'm1',
    userId: 'u1',
    cliType: 'builtin',
    agentType: 'codex',
    text: 'Review with the complete configuration',
    configOptionValues: combined,
  };
  try {
    const rejected = await fixture.runtime.sendTurn({
      ...send,
      configOptionValues: { ...combined, additional: 'one too many' },
    });
    assert.deepEqual(rejected, {
      state: 'not_sent',
      reason: 'invalid_config_options',
    });
    assert.equal(fixture.appends.length, 0);
    assert.equal(requests.length, 0);
    assert.equal(fixture.server.toJSON().history?.length ?? 0, 0);

    const delivered = await fixture.runtime.sendTurn(
      JSON.parse(JSON.stringify(send)),
    );
    assert.equal(delivered.state, 'accepted');
    assert.equal(requests.length, 1);
    assert.deepEqual(
      fixture.server.toJSON().history[0].inputConfig.configOptionValues,
      combined,
    );
    const queued = await fixture.runtime.sendTurn({ ...send, queue: true });
    assert.equal(queued.state, 'queued');
    assert.equal(requests.length, 1);
    assert.deepEqual(
      fixture.server.toJSON().mq[0].acpSessionConfig.configOptionValues,
      combined,
    );
    const appends = fixture.appends.length;
    const overflow = await fixture.runtime.sendTurn({
      ...send,
      configOptionValues: { additional: 'inherited map overflows' },
    });
    assert.equal(overflow.state, 'not_sent');
    assert.equal(overflow.reason, 'invalid_config_options');
    assert.equal(fixture.appends.length, appends);
    assert.equal(requests.length, 1);
    const configured = await fixture.runtime.sendTurn(
      send,
      async (text) => text,
      async (_, input) => ({
        ...input,
        configOptionValues: { ...combined, extraRolePin: true },
      }),
    );
    assert.equal(configured.state, 'not_sent');
    assert.equal(configured.reason, 'invalid_config_options');
    assert.equal(fixture.appends.length, appends);
    assert.equal(requests.length, 1);
  } finally {
    fixture.close();
  }
});

test('a lifted 512-character reasoning option reaches history and dispatch; 513 cannot write', async () => {
  const effort = '界'.repeat(512);
  const optionId = 'effort-option';
  const requests = [];
  const fixture = await openTestSession({
    onRpc: (request) => {
      requests.push(request);
      const persisted = fixture.server
        .toJSON()
        .history.find((entry) => entry.id === request.params.userTurnId);
      assert.equal(persisted.inputConfig.configOptionValues[optionId], effort);
      assert.equal(
        request.params.inputConfig.configOptionValues[optionId],
        effort,
      );
      return { result: { accepted: true } };
    },
  });
  const send = {
    sessionId: 's1',
    machineId: 'm1',
    userId: 'u1',
    cliType: 'builtin',
    agentType: 'codex',
    text: 'Use the complete Role option value',
    reasoningEffortConfigId: optionId,
  };
  try {
    const rejected = await fixture.runtime.sendTurn({
      ...send,
      reasoningEffort: `${effort}多`,
    });
    assert.equal(rejected.state, 'not_sent');
    assert.equal(fixture.appends.length, 0);
    assert.equal(requests.length, 0);
    const invalidId = await fixture.runtime.sendTurn({
      ...send,
      reasoningEffort: effort,
      reasoningEffortConfigId: 'x'.repeat(129),
    });
    assert.equal(invalidId.state, 'not_sent');
    assert.equal(fixture.appends.length, 0);
    const accepted = await fixture.runtime.sendTurn({
      ...send,
      reasoningEffort: effort,
    });
    assert.equal(accepted.state, 'accepted');
    assert.equal(requests.length, 1);
    assert.equal(
      fixture.server.toJSON().history[0].inputConfig.configOptionValues[
        optionId
      ],
      effort,
    );
  } finally {
    fixture.close();
  }
});
