import test from 'node:test';
import assert from 'node:assert/strict';
import { openTestSession } from '../helpers.mjs';

const send = {
  sessionId: 's1',
  machineId: 'm1',
  userId: 'u1',
  text: 'Next',
  cliType: 'builtin',
  agentType: 'codex',
};
const control = { sessionId: 's1', machineId: 'm1', turnId: 'active-reply' };

test('queue controls preserve identity, attachments and FIFO; stale and uncertain requests never replay', async () => {
  let reply = { applied: false, disposition: 'unsupported' };
  let appendFails = false;
  let rpcFails = false;
  const requests = [];
  const fixture = await openTestSession({
    failAppend: () => appendFails,
    onRpc: async (request) => {
      requests.push(request);
      if (rpcFails) throw new Error('reply_stream_lost');
      if (request.method === 'session/steer') {
        const { userTurnId, inputConfig } = request.params;
        const raw = fixture.server.toJSON();
        assert.equal(
          raw.history.filter((entry) => entry.id === userTurnId).length,
          1,
        );
        assert.equal(
          raw.history.find((entry) => entry.id === userTurnId).status,
          'pending_apply',
        );
        assert.ok(
          !raw.mq.some((item) => item.userTurnId === userTurnId),
          'Queue transfer must be durable before RPC',
        );
        assert.equal(inputConfig.inputBlocks[1].fileName, 'queued.txt');
      }
      return { result: reply };
    },
  });
  try {
    fixture.server.getList('history').push({
      id: 'active-reply',
      role: 'assistant',
      finished: false,
      items: [],
    });
    fixture.server.commit();
    await fixture.pushUpdate();
    const first = await fixture.runtime.sendTurn(send);
    const second = await fixture.runtime.sendTurn({
      ...send,
      text: 'Steer this',
      attachmentBlocks: [
        {
          type: 'file',
          fileId: 'file-1',
          fileName: 'queued.txt',
          mimeType: 'text/plain',
          sizeBytes: 12,
          transport: 'r2',
          sha256: 'fixture-sha',
          textPreview: true,
          uploadedAt: 1,
        },
      ],
    });
    assert.equal(
      (
        await fixture.runtime.controlTurn({
          ...control,
          action: 'steer',
          messageId: second.id,
        })
      ).state,
      'not_applied',
    );
    const waiting = fixture.runtime
      .projectSession(fixture.server, 'live')
      .entries.find((entry) => entry.id === second.id);
    assert.equal(
      waiting.status,
      'queued',
      'Unapplied steer stays outside the transcript',
    );
    assert.equal(
      waiting.canSteer,
      false,
      'Unconfirmed intent cannot be duplicated',
    );
    // The CLI confirms non-delivery by returning this same history turn to pending.
    const requeue = async () => {
      const pending = fixture.server.getList('history').get(1);
      pending.set('status', 'pending');
      fixture.server.commit();
      await fixture.pushUpdate();
    };
    await requeue();
    const requeued = fixture.runtime
      .projectSession(fixture.server, 'live')
      .entries.find((entry) => entry.id === second.id);
    assert.equal(requeued.status, 'queued');
    assert.equal(
      requeued.canSteer,
      false,
      'A requeued steer waits for ordinary dispatch instead of a retry',
    );
    rpcFails = true;
    const lost = await fixture.runtime.controlTurn({
      ...control,
      action: 'steer',
      messageId: second.id,
    });
    assert.equal(
      lost.state,
      'not_applied',
      'A lost reply after the durable write is not an error: the machine owns the turn',
    );
    assert.equal(lost.reason, 'reply_stream_lost');
    rpcFails = false;
    await requeue();
    reply = { applied: true };
    assert.equal(
      (
        await fixture.runtime.controlTurn({
          ...control,
          action: 'steer',
          messageId: second.id,
        })
      ).state,
      'applied',
    );
    assert.equal(requests.length, 3);
    assert.equal(requests[0].method, 'session/steer');
    assert.equal(requests[0].params.expectedTurnId, 'active-reply');
    assert.equal(requests[0].params.userTurnId, second.id);
    requests.splice(1, 1);
    let projection = fixture.runtime.projectSession(fixture.server, 'live');
    assert.equal(
      projection.entries.find((entry) => entry.id === second.id).status,
      'processing',
    );
    assert.deepEqual(
      fixture.server.toJSON().mq.map((item) => item.userTurnId),
      [first.id],
    );
    await assert.rejects(
      fixture.runtime.controlTurn({
        ...control,
        action: 'steer',
        messageId: second.id,
      }),
      /message_not_queued/,
    );
    reply = { success: true };
    assert.equal(
      (await fixture.runtime.controlTurn({ ...control, action: 'stop' })).state,
      'stopped',
    );
    assert.deepEqual(requests[2].params, {
      sessionId: 's1',
      turnId: 'active-reply',
    });
    assert.deepEqual(
      fixture.server.toJSON().mq.map((item) => item.userTurnId),
      [first.id],
      'Stop must leave the queue available for the machine to consume',
    );
    await assert.rejects(
      fixture.runtime.controlTurn({
        ...control,
        turnId: 'old-reply',
        action: 'stop',
      }),
      /stale_turn/,
    );
    appendFails = true;
    await assert.rejects(
      fixture.runtime.controlTurn({
        ...control,
        action: 'steer',
        messageId: first.id,
      }),
      /steer_unconfirmed/,
    );
    assert.equal(
      requests.length,
      3,
      'Unconfirmed durable write must not reach RPC',
    );
    const appends = fixture.appends.length;
    appendFails = false;
    await assert.rejects(
      fixture.runtime.controlTurn({
        ...control,
        action: 'steer',
        messageId: first.id,
      }),
      /message_not_queued/,
    );
    assert.equal(
      fixture.appends.length,
      appends,
      'Uncertain steer must not replay on retry',
    );
    projection = fixture.runtime.projectSession(fixture.server, 'live');
    assert.equal(
      projection.entries.find((entry) => entry.id === first.id).status,
      'queued',
    );
  } finally {
    fixture.close();
  }
});
