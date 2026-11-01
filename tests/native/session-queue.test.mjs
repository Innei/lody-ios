import test from 'node:test';
import assert from 'node:assert/strict';
import { openTestSession } from '../helpers.mjs';

test('queue edits preserve attachments, protect an editing head and reject stale writes', async () => {
  const fixture = await openTestSession();
  try {
    fixture.server
      .getList('history')
      .push({ id: 'running', role: 'assistant', finished: false, items: [] });
    fixture.server.commit();
    await fixture.pushUpdate();
    const sent = await fixture.runtime.sendTurn({
      sessionId: 's1',
      machineId: 'm1',
      userId: 'u1',
      text: 'Inspect this',
      cliType: 'builtin',
      agentType: 'codex',
      attachmentBlocks: [
        {
          type: 'file',
          fileId: 'notes',
          fileName: 'notes.txt',
          mimeType: 'text/plain',
          sizeBytes: 12,
          transport: 'r2',
          sha256: 'fixture-sha',
          textPreview: true,
          uploadedAt: 1,
        },
      ],
    });
    assert.equal(sent.state, 'queued');
    assert.equal(
      typeof fixture.runtime.sessionQueue,
      'function',
      'queue management must reach the owned session runtime',
    );
    const scope = { sessionId: 's1', userId: 'u1' };
    const read = await fixture.runtime.sessionQueue({
      ...scope,
      action: 'list',
    });
    assert.equal(read.items.length, 1);
    assert.equal(read.items[0].text, 'Inspect this');
    assert.deepEqual(read.items[0].attachments, ['notes.txt']);
    const item = read.items[0];
    const editing = await fixture.runtime.sessionQueue({
      ...scope,
      action: 'begin',
      id: item.id,
      revision: item.revision,
      editToken: 'editor-1',
    });
    assert.equal(fixture.server.toJSON().mq[0].isEditing, true);
    assert.equal(editing.state, 'ready');
    const stale = await fixture.runtime.sessionQueue({
      ...scope,
      action: 'remove',
      id: item.id,
      revision: item.revision,
    });
    assert.equal(stale.state, 'stale');
    assert.equal(fixture.server.toJSON().mq.length, 1);
    const saved = await fixture.runtime.sessionQueue({
      ...scope,
      action: 'save',
      id: item.id,
      revision: editing.items[0].revision,
      editToken: 'editor-1',
      text: 'Review it',
    });
    assert.equal(saved.state, 'ready');
    const raw = fixture.server.toJSON().mq[0];
    assert.equal(raw.task, 'Review it');
    assert.equal(raw.isEditing, false);
    assert.equal(raw.acpSessionConfig.inputBlocks[1].fileName, 'notes.txt');
    assert.equal(raw.acpSessionConfig.inputBlocks[0].text, 'Review it');
  } finally {
    fixture.close();
  }
});

test('queue reorder and removal retain IDs; uncertain writes never replay', async () => {
  let fail = false;
  let marks = 0;
  const fixture = await openTestSession({
    failAppend: () => fail,
    markDispatch: async () => {
      marks += 1;
    },
  });
  try {
    fixture.server
      .getList('history')
      .push({ id: 'running', role: 'assistant', finished: false, items: [] });
    fixture.server.commit();
    await fixture.pushUpdate();
    for (const text of ['First', 'Second'])
      await fixture.runtime.sendTurn({
        sessionId: 's1',
        machineId: 'm1',
        userId: 'u1',
        text,
        cliType: 'builtin',
        agentType: 'codex',
      });
    assert.equal(typeof fixture.runtime.sessionQueue, 'function');
    const scope = { sessionId: 's1', userId: 'u1' };
    const { items } = await fixture.runtime.sessionQueue({
      ...scope,
      action: 'list',
    });
    const moved = await fixture.runtime.sessionQueue({
      ...scope,
      action: 'move',
      id: items[1].id,
      revision: items[1].revision,
      overId: items[0].id,
    });
    assert.deepEqual(
      moved.items.map((item) => item.text),
      ['Second', 'First'],
    );
    assert.equal(moved.items[0].messageId, items[1].messageId);
    const removed = await fixture.runtime.sessionQueue({
      ...scope,
      action: 'remove',
      id: items[0].id,
      revision: items[0].revision,
    });
    assert.deepEqual(
      removed.items.map((item) => item.text),
      ['Second'],
    );
    fail = true;
    const before = marks;
    const unknown = await fixture.runtime.sessionQueue({
      ...scope,
      action: 'remove',
      id: items[1].id,
      revision: items[1].revision,
    });
    assert.equal(unknown.state, 'unknown');
    assert.equal(marks, before, 'a failed persistence does not wake dispatch');
    await assert.rejects(
      fixture.runtime.sessionQueue({ ...scope, action: 'list' }),
      /session_not_ready/,
    );
    assert.equal(
      fixture.server.toJSON().mq.length,
      1,
      'unknown delivery is not replayed',
    );
  } finally {
    fixture.close();
  }
});

test('a successful read cannot clear an uncertain queue write; explicit recovery bootstraps server state', async () => {
  let fail = false;
  const fixture = await openTestSession({ failAppend: () => fail });
  try {
    fixture.server
      .getList('history')
      .push({ id: 'running', role: 'assistant', finished: false, items: [] });
    fixture.server.commit();
    await fixture.pushUpdate();
    await fixture.runtime.sendTurn({
      sessionId: 's1',
      machineId: 'm1',
      userId: 'u1',
      text: 'Keep on server',
      cliType: 'builtin',
      agentType: 'codex',
    });
    const scope = { sessionId: 's1', userId: 'u1' };
    const { items } = await fixture.runtime.sessionQueue({
      ...scope,
      action: 'list',
    });
    fail = true;
    const outcome = await fixture.runtime.sessionQueue({
      ...scope,
      action: 'remove',
      id: items[0].id,
      revision: items[0].revision,
    });
    assert.equal(outcome.state, 'unknown');
    // Deliver a real server increment while the local failed mutation still exists.
    fixture.server.getMap('fixture').set('poll', true);
    fixture.server.commit();
    void fixture.pushUpdate();
    await new Promise((resolve) => setTimeout(resolve, 250));
    await assert.rejects(
      fixture.runtime.sessionQueue({ ...scope, action: 'list' }),
      /session_not_ready/,
    );
    assert.notEqual(fixture.events.at(-1).status, 'live');
    fail = false;
    await fixture.runtime.openSession(
      's1',
      'w1',
      async () => ({ token: 'synthetic', gatewayBaseUrl: 'https://x.invalid' }),
      () => {},
      async () => {},
    );
    const deadline = Date.now() + 3000;
    let restored;
    while (Date.now() < deadline) {
      try {
        restored = await fixture.runtime.sessionQueue({
          ...scope,
          action: 'list',
        });
        break;
      } catch {
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
    }
    assert.deepEqual(
      restored?.items.map((item) => item.text),
      ['Keep on server'],
    );
    assert.equal(
      fixture.server.toJSON().mq.length,
      1,
      'no uncertain removal is replayed',
    );
  } finally {
    fixture.close();
  }
});
