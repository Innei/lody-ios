import test from 'node:test';
import assert from 'node:assert/strict';
import { openTestSession } from '../helpers.mjs';

const send = {
  sessionId: 's1',
  machineId: 'm1',
  userId: 'u1',
  text: 'First',
  cliType: 'builtin',
  agentType: 'codex',
};
const command = (id, action, fields = {}) => ({
  sessionId: 's1',
  id,
  action,
  ...fields,
});
const now = async () => 1_800_000_000_000;
async function running(fixture) {
  fixture.server
    .getList('history')
    .push({ id: 'active', role: 'assistant', finished: false, items: [] });
  fixture.server.commit();
  await fixture.pushUpdate();
}

test('queue edit preserves stable identity, attachment blocks and run settings; moves only change order', async () => {
  const watermarks = [];
  const fixture = await openTestSession({
    markDispatch: async (...args) => watermarks.push(args),
  });
  try {
    await running(fixture);
    const first = await fixture.runtime.sendTurn({
      ...send,
      attachmentBlocks: [
        {
          type: 'file',
          fileId: 'file1',
          fileName: 'draft.txt',
          mimeType: 'text/plain',
          sizeBytes: 12,
          transport: 'r2',
          sha256: 'sha',
          textPreview: true,
          uploadedAt: 1,
        },
      ],
    });
    const second = await fixture.runtime.sendTurn({ ...send, text: 'Second' });
    const before = fixture.server.toJSON().mq;
    const cid = fixture.server.getMovableList('mq').get(0).id;
    const lease = await fixture.runtime.queueMessage(
      command(first.id, 'begin-edit'),
      now,
    );
    assert.equal(lease.state, 'applied');
    assert.equal(lease.text, 'First');
    assert.equal(fixture.server.toJSON().mq[0].isEditing, true);
    const saved = await fixture.runtime.queueMessage(
      command(first.id, 'save-edit', {
        text: 'Changed',
        baseText: 'First',
        editingStartedAt: lease.editingStartedAt,
      }),
      now,
    );
    assert.equal(saved.state, 'applied');
    const after = fixture.server.toJSON().mq;
    assert.equal(fixture.server.getMovableList('mq').get(0).id, cid);
    assert.equal(after[0].userTurnId, first.id);
    assert.equal(after[0].operationId, `queue:${first.id}`);
    assert.equal(after[0].task, 'Changed');
    assert.equal(after[0].acpSessionConfig.prompt, 'Changed');
    assert.deepEqual(after[0].acpSessionConfig.inputBlocks, [
      { type: 'text', text: 'Changed' },
      before[0].acpSessionConfig.inputBlocks[1],
    ]);
    assert.equal(
      after[0].acpSessionConfig.agentType,
      before[0].acpSessionConfig.agentType,
    );
    assert.equal(after[0].isEditing, false);
    assert.deepEqual(after[1], before[1]);
    assert.equal(
      (await fixture.runtime.queueMessage(command(second.id, 'move-up'), now))
        .state,
      'applied',
    );
    assert.deepEqual(
      fixture.server.toJSON().mq.map((row) => row.userTurnId),
      [second.id, first.id],
    );
    assert.equal(
      (await fixture.runtime.queueMessage(command(second.id, 'move-down'), now))
        .state,
      'applied',
    );
    assert.deepEqual(
      fixture.server.toJSON().mq.map((row) => row.userTurnId),
      [first.id, second.id],
    );
    assert.ok(watermarks.slice(2).every((args) => args[2] === true));
  } finally {
    fixture.close();
  }
});

test('fresh peer lease blocks editing/deleting/reordering; expired lease can be acquired and stale editor cannot save', async () => {
  const fixture = await openTestSession();
  try {
    await running(fixture);
    const first = await fixture.runtime.sendTurn(send);
    await fixture.runtime.sendTurn({ ...send, text: 'Second' });
    const row = fixture.server.getMovableList('mq').get(0);
    row.set('isEditing', true);
    row.set('editingStartedAt', await now());
    fixture.server.commit();
    const appends = fixture.appends.length;
    for (const action of ['begin-edit', 'delete', 'move-down']) {
      const result = await fixture.runtime.queueMessage(
        command(first.id, action),
        now,
      );
      assert.equal(result.state, 'rejected');
      assert.equal(result.reason, 'queue_edit_conflict');
    }
    assert.equal(fixture.appends.length, appends);
    const clock = async () => (await now()) + 300_001;
    const lease = await fixture.runtime.queueMessage(
      command(first.id, 'begin-edit'),
      clock,
    );
    assert.equal(lease.state, 'applied');
    const expired = await fixture.runtime.queueMessage(
      command(first.id, 'save-edit', {
        text: 'Stale edit',
        editingStartedAt: lease.editingStartedAt,
      }),
      async () => (await clock()) + 300_001,
    );
    assert.equal(expired.state, 'rejected');
    assert.equal(expired.reason, 'queue_edit_expired');
    assert.equal(fixture.server.toJSON().mq[0].task, 'First');
    const activeLease = await fixture.runtime.queueMessage(
      command(first.id, 'begin-edit'),
      async () => (await clock()) + 300_002,
    );
    assert.equal(activeLease.state, 'applied');
    const cancelled = await fixture.runtime.queueMessage(
      command(first.id, 'cancel-edit', {
        editingStartedAt: activeLease.editingStartedAt,
      }),
      async () => (await clock()) + 300_003,
    );
    assert.equal(cancelled.state, 'applied');
    assert.equal(fixture.server.toJSON().mq[0].isEditing, false);
  } finally {
    fixture.close();
  }
});

test('delete changes only the target queue container and cannot claim that machine execution was cancelled', async () => {
  const fixture = await openTestSession({
    onRpc: () => {
      throw new Error('Queue delete must never cancel the machine');
    },
  });
  try {
    await running(fixture);
    const first = await fixture.runtime.sendTurn(send);
    const second = await fixture.runtime.sendTurn({ ...send, text: 'Second' });
    const third = await fixture.runtime.sendTurn({ ...send, text: 'Third' });
    const before = fixture.server.toJSON().mq;
    const removed = await fixture.runtime.queueMessage(
      command(second.id, 'delete'),
      now,
    );
    assert.equal(removed.state, 'unknown');
    assert.equal(removed.reason, 'queue_execution_unconfirmed');
    assert.deepEqual(fixture.server.toJSON().mq, [before[0], before[2]]);
    const appends = fixture.appends.length;
    assert.equal(
      (await fixture.runtime.queueMessage(command(second.id, 'delete'), now))
        .state,
      'unknown',
    );
    assert.equal(
      fixture.appends.length,
      appends,
      'Unconfirmed delete cannot repeat its write',
    );
    fixture.server
      .getList('history')
      .push({ id: second.id, role: 'user', status: 'processing', items: [] });
    fixture.server.commit();
    const checked = await fixture.runtime.queueMessage(
      command(second.id, 'check', { receipt: removed.receipt }),
      now,
    );
    assert.equal(checked.state, 'rejected');
    assert.equal(checked.reason, 'queue_item_started');
    assert.deepEqual(
      fixture.server.toJSON().mq.map((row) => row.userTurnId),
      [first.id, third.id],
    );
    assert.equal(fixture.server.toJSON().history[0].finished, false);
  } finally {
    fixture.close();
  }
});

test('an authoritative promotion before delete rejects without touching any queue row', async () => {
  const fixture = await openTestSession();
  try {
    await running(fixture);
    const first = await fixture.runtime.sendTurn(send);
    fixture.server.getMovableList('mq').delete(0, 1);
    fixture.server
      .getList('history')
      .push({ id: first.id, role: 'user', status: 'pending', items: [] });
    fixture.server.commit();
    const appends = fixture.appends.length;
    const result = await fixture.runtime.queueMessage(
      command(first.id, 'delete'),
      now,
    );
    assert.deepEqual(result, {
      state: 'rejected',
      reason: 'queue_item_started',
    });
    assert.equal(fixture.appends.length, appends);
  } finally {
    fixture.close();
  }
});

test('read-only send checks ignore unacknowledged local rows and never publish pointers or RPC', async () => {
  let fails = true;
  let marks = 0;
  const fixture = await openTestSession({
    failAppend: () => fails,
    markDispatch: async () => marks++,
  });
  try {
    const result = await fixture.runtime.sendTurn(send);
    assert.equal(result.state, 'unknown');
    assert.equal(fixture.runtime.docSnapshot().history[0].id, result.id);
    assert.equal(fixture.server.toJSON().history?.length ?? 0, 0);
    const appends = fixture.appends.length;
    assert.deepEqual(
      await fixture.runtime.checkSend({ sessionId: 's1', id: result.id }),
      { state: 'unknown', reason: 'turn_not_observed' },
    );
    assert.equal(fixture.appends.length, appends);
    assert.equal(marks, 0);
    fails = false;
    fixture.server
      .getList('history')
      .push({ id: result.id, role: 'user', status: 'pending', items: [] });
    fixture.server.commit();
    assert.equal(
      (await fixture.runtime.checkSend({ sessionId: 's1', id: result.id }))
        .state,
      'uploaded',
    );
    fixture.server.getList('history').push({
      id: 'reply',
      userTurnId: result.id,
      role: 'assistant',
      finished: true,
      items: [],
    });
    fixture.server.commit();
    assert.equal(
      (await fixture.runtime.checkSend({ sessionId: 's1', id: result.id }))
        .state,
      'accepted',
    );
    assert.equal(fixture.appends.length, appends);
  } finally {
    fixture.close();
  }
});

test('runtime replacement while queue time calibration is pending prevents the append', async () => {
  const fixture = await openTestSession();
  try {
    await running(fixture);
    const first = await fixture.runtime.sendTurn(send);
    const appends = fixture.appends.length;
    const result = await fixture.runtime.queueMessage(
      command(first.id, 'delete'),
      async () => {
        fixture.runtime.stopSessions();
        return now();
      },
    );
    assert.equal(result.state, 'rejected');
    assert.equal(fixture.appends.length, appends);
    assert.equal(fixture.server.toJSON().mq.length, 1);
  } finally {
    fixture.close();
  }
});

test('maximum-length Unicode and escaped queue edits survive JSON transport without truncation', async () => {
  for (const character of ['中', '\u0000']) {
    const fixture = await openTestSession();
    try {
      await running(fixture);
      const original = character.repeat(32000);
      const first = await fixture.runtime.sendTurn({ ...send, text: original });
      assert.equal(first.state, 'queued');
      const lease = await fixture.runtime.queueMessage(
        command(first.id, 'begin-edit'),
        now,
      );
      assert.equal(lease.text, original);
      const changed = `${character.repeat(31999)}改`;
      const payload = JSON.stringify(
        command(first.id, 'save-edit', {
          text: changed,
          baseText: original,
          editingStartedAt: lease.editingStartedAt,
        }),
      );
      assert.ok(
        Buffer.byteLength(payload) > 128 * 1024,
        'A legal edit exceeds the former bridge envelope limit',
      );
      const appends = fixture.appends.length;
      const result = await fixture.runtime.queueMessage(
        JSON.parse(payload),
        now,
      );
      assert.equal(result.state, 'applied');
      assert.equal(fixture.appends.length, appends + 1);
      const row = fixture.server.toJSON().mq[0];
      assert.equal(row.task, changed);
      assert.equal(row.acpSessionConfig.prompt, changed);
      assert.deepEqual(row.acpSessionConfig.inputBlocks, [
        { type: 'text', text: changed },
      ]);
    } finally {
      fixture.close();
    }
  }
});

test('a full legal reorder receipt is checked without truncating IDs or repeating a write', async () => {
  const fixture = await openTestSession();
  try {
    const ids = Array.from({ length: 10000 }, () => crypto.randomUUID());
    const queue = fixture.server.getMovableList('mq');
    for (const id of ids) queue.push({ userTurnId: id });
    fixture.server.commit();
    const receipt = { action: 'move-up', id: ids[0], order: [...ids] };
    [receipt.order[0], receipt.order[1]] = [receipt.order[1], receipt.order[0]];
    const payload = JSON.stringify(command(ids[0], 'check', { receipt }));
    assert.ok(Buffer.byteLength(payload) > 128 * 1024);
    const appends = fixture.appends.length;
    const unknown = await fixture.runtime.queueMessage(
      JSON.parse(payload),
      now,
    );
    assert.equal(unknown.state, 'unknown');
    assert.equal(unknown.receipt.order.length, ids.length);
    assert.deepEqual(unknown.receipt.order, receipt.order);
    const confirmed = await fixture.runtime.queueMessage(
      JSON.parse(
        JSON.stringify(
          command(ids[0], 'check', { receipt: { ...receipt, order: ids } }),
        ),
      ),
      now,
    );
    assert.equal(confirmed.state, 'applied');
    assert.equal(fixture.appends.length, appends);
    assert.deepEqual(
      fixture.server.toJSON().mq.map((row) => row.userTurnId),
      ids,
    );
  } finally {
    fixture.close();
  }
});
