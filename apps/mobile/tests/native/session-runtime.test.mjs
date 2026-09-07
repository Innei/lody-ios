import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { LoroDoc, LoroMap, LoroList, LoroText } from 'loro-crdt/base64';
import { openTestSession, loadRuntime, frame } from '../helpers.mjs';

test('system notice identity survives projection updates without changing the completed reply', async () => {
  const { projectSession } = await loadRuntime();
  const doc = new LoroDoc();
  doc.getList('history').push({
    id: 'done',
    role: 'assistant',
    finished: true,
    items: [{ type: 'text', text: 'done' }],
  });
  const notice = doc.getList('history').pushContainer(new LoroMap());
  notice.set('id', 'notice');
  notice.set('role', 'system');
  const item = notice
    .setContainer('items', new LoroList())
    .pushContainer(new LoroMap());
  item.set('type', 'system_notice');
  item.set('name', 'agent_warning');
  doc.commit();
  const before = projectSession(doc, 'live');
  assert.equal(before.entries[0].finished, true);
  assert.equal(before.entries[1].items[0].name, 'agent_warning');
  item.set('name', 'chat_failed');
  doc.commit();
  const after = projectSession(doc, 'live');
  assert.equal(after.entries[1].items[0].name, 'chat_failed');
  assert.ok(after.entries[1].rev > before.entries[1].rev);
  assert.equal(after.entries[0].finished, true);
});

test('send persists user before dispatch; duplicate incremental imports preserve one ordered streaming reply', async () => {
  const server = new LoroDoc();
  let sessionRead,
    rpc,
    appends = 0,
    acknowledged = true,
    loseAppendAck = false;
  const frame = (bytes) => {
    const result = new Uint8Array(bytes.length + 4);
    new DataView(result.buffer).setUint32(0, bytes.length, false);
    result.set(bytes, 4);
    return result;
  };
  const ok = (result) => ({ ok: true, result });
  const live = (payload, offset = '2') =>
    ok({ nextOffset: offset, upToDate: true, closed: false, payload });
  globalThis.__sessionClient = class {
    constructor({ url }) {
      this.url = decodeURIComponent(url);
    }
    async bootstrap() {
      return ok({
        snapshotOffset: '1',
        nextOffset: '1',
        upToDate: true,
        snapshot: { body: server.export({ mode: 'snapshot' }) },
        updates: [],
      });
    }
    readOnce() {
      if (this.url.includes(':rpc:res:'))
        return Promise.resolve(
          live({
            body: new TextEncoder().encode(
              JSON.stringify([
                { id: rpc.id, result: { accepted: acknowledged } },
              ]),
            ),
          }),
        );
      return new Promise((resolve) => {
        sessionRead = resolve;
      });
    }
    async create() {
      return ok({});
    }
    async append({ part }) {
      if (this.url.includes(':rpc:req:')) {
        rpc = JSON.parse(part.body);
        assert.equal(server.toJSON().history[0].id, rpc.params.userTurnId);
      } else {
        appends++;
        assert.equal(
          new DataView(part.body.buffer, part.body.byteOffset).getUint32(
            0,
            false,
          ),
          part.body.length - 4,
        );
        server.import(part.body.subarray(4));
      }
      if (loseAppendAck && !this.url.includes(':rpc:req:'))
        return { ok: false, result: { code: 'timeout' } };
      return ok({ nextOffset: '2' });
    }
  };
  const bundle = await build({
    entryPoints: ['apps/mobile/modules/lody-kit/data-runtime/session.ts'],
    bundle: true,
    format: 'esm',
    platform: 'browser',
    write: false,
    plugins: [
      {
        name: 'stream',
        setup(b) {
          b.onResolve({ filter: /^@loro-dev\/streams-client$/ }, () => ({
            path: 'mock',
            namespace: 'test',
          }));
          b.onLoad({ filter: /.*/, namespace: 'test' }, () => ({
            contents: 'export const StreamsClient=globalThis.__sessionClient',
          }));
        },
      },
    ],
  });
  const runtime = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );
  const events = [];
  const background = [];
  let resolveLive;
  const nextLive = () =>
    new Promise((resolve) => {
      resolveLive = resolve;
    });
  const initial = nextLive();
  await runtime.openSession(
    's1',
    'w1',
    async () => ({
      token: 'synthetic',
      gatewayBaseUrl: 'https://example.invalid',
    }),
    (e) => {
      if (e.backgroundWork) background.push(e.backgroundWork);
      if (!e.session) return;
      const value = JSON.parse(e.session);
      events.push(value);
      if (value.status === 'live') resolveLive?.(value);
    },
    async (sessionId, turnId) => {
      assert.equal(sessionId, 's1');
      assert.equal(server.toJSON().history[0].id, turnId);
    },
  );
  await initial;
  const attachments = [
    {
      type: 'image',
      imageId: 'img1',
      mimeType: 'image/png',
      sizeBytes: 12,
      fileName: '照片.png',
    },
    {
      type: 'file',
      fileId: 'file1',
      fileName: 'note.txt',
      mimeType: 'text/plain',
      sizeBytes: 3,
      sha256: 'abc',
      textPreview: true,
      transport: 'r2',
      uploadedAt: 1,
    },
  ];
  const invalid = await runtime.sendTurn({
    sessionId: 's1',
    text: '',
    attachmentBlocks: [{ type: 'image', uri: 'file:///private/test' }],
  });
  assert.equal(invalid.state, 'not_sent');
  assert.equal(appends, 0);
  const turn = {
    id: '2B066292-A94B-4383-B3C5-A0A7522F31CD',
    sessionId: 's1',
    machineId: 'm1',
    userId: 'u1',
    text: 'POC hello',
    backgroundTaskId: 'background-test',
    attachmentBlocks: attachments,
    cliType: 'builtin',
    agentType: 'codex',
    modelId: 'gpt-test',
    reasoningEffort: 'high',
    reasoningEffortConfigId: 'effort',
  };
  assert.equal(
    (await runtime.sendTurn({ ...turn, id: 'not-a-uuid' })).state,
    'not_sent',
  );
  assert.equal(appends, 0);
  const sending = runtime.sendTurn(turn);
  assert.equal(
    (await runtime.sendTurn(turn)).reason,
    'turn_already_exists',
    'an in-flight duplicate must not be treated as safe to retry',
  );
  const result = await sending;
  assert.equal(result.state, 'accepted');
  assert.equal(result.id, turn.id);
  assert.equal(rpc.params.userTurnId, turn.id);
  const firstRPC = rpc;
  const repeatedTurn = await runtime.sendTurn(turn);
  assert.equal(repeatedTurn.state, 'unknown');
  assert.equal(repeatedTurn.reason, 'turn_already_exists');
  assert.equal(rpc, firstRPC, 'duplicate identity must not dispatch again');
  assert.equal(background.at(-1).state, 'sent'); // Machine ACK is not completion.
  assert.equal(background.at(-1).id, 'background-test');
  assert.equal(appends, 1);
  const user = server.toJSON().history[0];
  assert.equal(user.items[0].text, 'POC hello');
  assert.deepEqual(user.items.slice(1), attachments);
  assert.deepEqual(
    rpc.params.inputConfig.inputBlocks,
    user.inputConfig.inputBlocks,
  );
  assert.deepEqual(user.inputConfig.inputBlocks.slice(1), attachments);
  assert.equal(rpc.params.inputConfig.modelId, 'gpt-test');
  assert.deepEqual(rpc.params.inputConfig.configOptionValues, {
    effort: 'high',
  });
  const projection = runtime.projectSession(server, 'live');
  assert.deepEqual(projection.composer, {
    modelId: 'gpt-test',
    effort: 'high',
  });
  const projectedImage = projection.entries[0].items[1];
  assert.equal(projectedImage.type, 'image');
  assert.equal(projectedImage.image.id, 'img1');
  assert.equal(projectedImage.image.fileName, '照片.png');
  assert.equal(projectedImage.text, undefined);
  assert.deepEqual(user.inputConfig.mcpServerIds, []);
  const version = server.version();
  const entry = server.getList('history').pushContainer(new LoroMap());
  entry.set('id', 'reply');
  entry.set('userTurnId', 'another-turn');
  const item = entry
    .setContainer('items', new LoroList())
    .pushContainer(new LoroMap());
  item.set('type', 'text');
  item.setContainer('text', new LoroText()).insert(0, 'stream');
  entry.set('role', 'assistant');
  entry.set('finished', true);
  server.commit();
  const update = server.export({ mode: 'update', from: version });
  const firstReply = nextLive();
  sessionRead(live({ body: frame(update) }));
  assert.equal((await firstReply).entries[1].items[0].text, 'stream');
  assert.equal(background.at(-1).state, 'sent'); // Another turn's completion cannot end this task.
  const correlatedVersion = server.version();
  entry.set('userTurnId', result.id);
  entry.set('finished', false);
  server.commit();
  const correlated = nextLive();
  sessionRead(
    live(
      {
        body: frame(server.export({ mode: 'update', from: correlatedVersion })),
      },
      '2a',
    ),
  );
  await correlated;
  assert.equal(background.at(-1).state, 'receiving');
  const v2 = server.version();
  entry.get('items').get(0).get('text').insert(6, ' complete');
  entry.set('finished', true);
  server.commit();
  const fullUpdate = server.export({ mode: 'update', from: v2 });
  const finalReply = nextLive();
  sessionRead(live({ body: frame(fullUpdate) }, '3'));
  const final = await finalReply;
  assert.equal(background.at(-1).state, 'completed');
  assert.equal(final.entries.length, 2);
  assert.equal(final.entries[1].items[0].text, 'stream complete');
  assert.equal(final.entries[1].finished, true);
  const duplicate = nextLive();
  sessionRead(live({ body: frame(fullUpdate) }, '4'));
  assert.equal((await duplicate).entries.length, 2);
  const misordered = new LoroDoc();
  const assistant = misordered.getList('history').pushContainer(new LoroMap());
  assistant.set('id', 'a');
  assistant.set('role', 'assistant');
  assistant.set('userTurnId', 'u');
  const parent = misordered.getList('history').pushContainer(new LoroMap());
  parent.set('id', 'u');
  parent.set('role', 'user');
  assert.deepEqual(
    runtime.projectSession(misordered, 'live').entries.map((e) => e.id),
    ['u', 'a'],
  );
  const oldRead = sessionRead;
  runtime.stopSessions();
  oldRead(live({ body: frame(update) }, '5'));
  assert.equal(
    (await runtime.sendTurn({ sessionId: 's1', text: 'no' })).state,
    'not_sent',
  );
  assert.equal(appends, 1);
  const reopen = nextLive();
  await runtime.openSession(
    's1',
    'w1',
    async () => ({
      token: 'synthetic',
      gatewayBaseUrl: 'https://example.invalid',
    }),
    (e) => {
      const value = JSON.parse(e.session);
      if (value.status === 'live') resolveLive?.(value);
    },
    async () => {},
  );
  await reopen;
  loseAppendAck = true;
  const uncertain = await runtime.sendTurn({
    sessionId: 's1',
    machineId: 'm1',
    userId: 'u1',
    text: '',
    attachmentBlocks: attachments,
    cliType: 'builtin',
    agentType: 'codex',
  });
  assert.equal(uncertain.state, 'unknown');
  assert.deepEqual(server.toJSON().history.at(-1).items, attachments);
  assert.equal(
    server.toJSON().history.filter((e) => e.id === uncertain.id).length,
    1,
  );
  assert.equal(appends, 2);
  assert.equal(
    (await runtime.sendTurn({ ...turn, id: uncertain.id })).reason,
    'turn_already_exists',
  );
  assert.equal(appends, 2, 'ambiguous append must not be replayed');
  runtime.stopSessions();
  delete globalThis.__sessionClient;
});

async function loadProject() {
  const bundle = await build({
    entryPoints: [
      new URL('../../modules/lody-kit/data-runtime/project.ts', import.meta.url)
        .pathname,
    ],
    bundle: true,
    format: 'esm',
    platform: 'neutral',
    write: false,
    external: ['loro-crdt/base64'],
  });
  return import(
    'data:text/javascript;base64,' +
      Buffer.from(bundle.outputFiles[0].text).toString('base64')
  );
}

test('projection carries stable item ids, tool summaries, and diff counts', async () => {
  const mod = await loadProject();

  const doc = new LoroDoc();
  const entry = doc.getList('history').pushContainer(new LoroMap());
  entry.set('id', 'e1');
  entry.set('role', 'assistant');
  entry.set('finished', false);
  const items = entry.setContainer('items', new LoroList());

  const prose = items.pushContainer(new LoroMap());
  prose.set('type', 'text');
  prose.setContainer('text', new LoroText()).insert(0, '看了一眼 auth.ts');

  const call = items.pushContainer(new LoroMap());
  call.set('type', 'tool_call');
  call.set('toolCallId', 'tc_1');
  call.set('kind', 'edit');
  call.set('title', 'Edit src/auth.ts');
  call.set('status', 'completed');
  call.set('content', [
    {
      type: 'diff',
      path: 'src/auth.ts',
      oldText: 'a\nb\nc\n',
      newText: 'a\nB\nc\nd\n',
    },
  ]);
  doc.commit();

  const first = mod.projectSession(doc, 'live');
  assert.equal(first.v, 1);
  assert.equal(first.entries.length, 1);

  const [textItem, toolItem] = first.entries[0].items;
  assert.equal(textItem.type, 'text');
  assert.equal(textItem.text, '看了一眼 auth.ts');
  assert.match(textItem.itemId, /^\d+:\d+$/);

  assert.equal(toolItem.itemId, 'tc_1');
  assert.equal(toolItem.kind, 'edit');
  assert.equal(toolItem.path, 'src/auth.ts');
  assert.equal(toolItem.added, 2);
  assert.equal(toolItem.removed, 1);
  assert.equal(toolItem.hasDetail, true);
  assert.equal(toolItem.permission, undefined);

  const idBefore = textItem.itemId;
  prose.get('text').insert(11, '，超时来自 fetch');
  doc.commit();
  const second = mod.projectSession(doc, 'live');
  assert.equal(second.entries[0].items[0].itemId, idBefore);
  assert.ok(second.entries[0].items[0].rev > textItem.rev);
  assert.equal(second.entries[0].items[1].rev, toolItem.rev);
  assert.ok(second.revision > first.revision);
});

test('unchanged entries keep their summary objects; prose is coalesced, status is not', async () => {
  const { projectSession } = await loadProject();
  const doc = new LoroDoc();
  const first = doc.getList('history').pushContainer(new LoroMap());
  first.set('id', 'e1');
  first.set('role', 'user');
  const second = doc.getList('history').pushContainer(new LoroMap());
  second.set('id', 'e2');
  second.set('role', 'assistant');
  const items = second.setContainer('items', new LoroList());
  const prose = items.pushContainer(new LoroMap());
  prose.set('type', 'text');
  prose.setContainer('text', new LoroText()).insert(0, 'hi');
  doc.commit();

  const a = projectSession(doc, 'live');
  prose.get('text').insert(2, ' there');
  doc.commit();
  const b = projectSession(doc, 'live');

  assert.equal(a.entries[0].rev, b.entries[0].rev);
  assert.ok(b.entries[1].rev > a.entries[1].rev);
});

test('itemDetail 按需取回 blocks，超限分页，缺失不抛错', async () => {
  const { runtime, server, pushUpdate, close } = await openTestSession();
  const entry = server.getList('history').pushContainer(new LoroMap());
  entry.set('id', 'e9');
  entry.set('role', 'assistant');
  const items = entry.setContainer('items', new LoroList());
  const call = items.pushContainer(new LoroMap());
  call.set('type', 'tool_call');
  call.set('toolCallId', 'tc_9');
  call.set('kind', 'execute');
  call.set('status', 'completed');
  call.set('content', [
    { type: 'terminal_command', command: 'pnpm', args: ['test'], cwd: '/w' },
    { type: 'terminal_output', output: 'ok\n', stream: 'combined' },
  ]);
  server.commit();
  await pushUpdate();

  const detail = await runtime.itemDetail({
    sessionId: 's1',
    entryId: 'e9',
    itemId: 'tc_9',
  });
  assert.equal(detail.itemId, 'tc_9');
  assert.equal(detail.blocks.length, 2);
  assert.equal(detail.blocks[0].command, 'pnpm');
  assert.equal(detail.truncated, false);
  assert.equal(detail.nextCursor, undefined);
  assert.ok(detail.rev > 0);

  call.set('content', [
    { type: 'terminal_output', output: 'x'.repeat(400 * 1024) },
    { type: 'terminal_output', output: 'y'.repeat(400 * 1024) },
  ]);
  server.commit();
  await pushUpdate();

  const page1 = await runtime.itemDetail({
    sessionId: 's1',
    entryId: 'e9',
    itemId: 'tc_9',
  });
  assert.equal(page1.truncated, true);
  assert.equal(page1.blocks.length, 1);
  assert.ok(page1.nextCursor);

  const page2 = await runtime.itemDetail({
    sessionId: 's1',
    entryId: 'e9',
    itemId: 'tc_9',
    cursor: page1.nextCursor,
  });
  assert.equal(page2.blocks.length, 1);
  assert.equal(page2.truncated, false);

  const missing = await runtime.itemDetail({
    sessionId: 's1',
    entryId: 'e9',
    itemId: 'nope',
  });
  assert.deepEqual(missing.blocks, []);
  assert.equal(missing.truncated, false);

  await assert.rejects(
    runtime.itemDetail({ sessionId: 'other', entryId: 'e9', itemId: 'tc_9' }),
    /session_not_ready/,
  );
  close();
});

test(
  'background Sessions keep syncing, visits promote LRU, eviction aborts reads and preserves the final cache',
  { timeout: 15000 },
  async (t) => {
    const servers = new Map();
    const clients = [];
    const events = [];
    const waiters = [];
    const ok = (result) => ({ ok: true, result });
    const until = (predicate) =>
      new Promise((resolve) => waiters.push({ predicate, resolve }));
    const emit = (event) => {
      const value = { ...event, data: JSON.parse(event.session) };
      events.push(value);
      for (const waiter of [...waiters]) {
        if (waiter.predicate(value)) {
          waiters.splice(waiters.indexOf(waiter), 1);
          waiter.resolve(value);
        }
      }
    };
    globalThis.__sessionClient = class {
      constructor({ url }) {
        this.id = decodeURIComponent(url).split(':s:')[1];
        clients.push(this);
      }
      async bootstrap({ signal }) {
        this.signal = signal;
        const server = servers.get(this.id) ?? new LoroDoc();
        servers.set(this.id, server);
        this.version = server.version();
        return ok({
          snapshotOffset: '1',
          nextOffset: '1',
          upToDate: true,
          snapshot: { body: server.export({ mode: 'snapshot' }) },
          updates: [],
        });
      }
      readOnce(request) {
        this.request = request;
        return new Promise((resolve, reject) => {
          this.resolve = resolve;
          request.signal.addEventListener(
            'abort',
            () => reject(new Error('aborted')),
            { once: true },
          );
        });
      }
      push(text) {
        const server = servers.get(this.id);
        let entry = server.getList('history').get(0);
        if (!entry) {
          entry = server.getList('history').pushContainer(new LoroMap());
          // Deliberately collide across Sessions to exercise projection isolation.
          entry.set('id', 'same-entry');
          entry.set('role', 'assistant');
          const item = entry
            .setContainer('items', new LoroList())
            .pushContainer(new LoroMap());
          item.set('type', 'tool_call');
          item.set('toolCallId', 'same-tool');
        }
        entry.get('items').get(0).set('title', text);
        server.commit();
        const body = frame(
          server.export({ mode: 'update', from: this.version }),
        );
        this.version = server.version();
        this.resolve(
          ok({
            nextOffset: String(Number(this.request.offset) + 1),
            upToDate: true,
            closed: false,
            payload: { body },
          }),
        );
      }
    };
    const runtime = await loadRuntime();
    t.after(() => {
      runtime.stopSessions();
      delete globalThis.__sessionClient;
    });
    const open = async (id, workspace = 'w1') => {
      const ready = until(
        (e) =>
          e.sessionId === id &&
          e.type === 'session' &&
          e.data.status === 'live',
      );
      await runtime.openSession(
        id,
        workspace,
        async () => ({
          token: 'synthetic',
          gatewayBaseUrl: 'https://x.invalid',
        }),
        emit,
        async () => {},
      );
      return ready;
    };
    const client = (id) => clients.findLast((c) => c.id === id);
    await open('a');
    await open('b');
    await open('c');
    await open('d');
    assert.equal(clients.filter((c) => !c.signal.aborted).length, 4);
    const background = until(
      (e) =>
        e.sessionId === 'a' &&
        e.type === 'sessionCache' &&
        e.data.entries.length,
    );
    client('a').push('changed while away');
    const cached = await background;
    assert.equal(cached.synced, true);
    assert.equal(cached.data.entries[0].items[0].title, 'changed while away');
    assert.equal(
      events.filter((e) => e.sessionId === 'a' && e.type === 'session').length,
      2,
    );

    await open('e');
    assert.equal(
      client('a').signal.aborted,
      true,
      'updates must not promote a',
    );
    const bCount = clients.filter((c) => c.id === 'b').length;
    await open('b');
    assert.equal(
      clients.filter((c) => c.id === 'b').length,
      bCount,
      'retained replica needs no bootstrap',
    );
    await open('f');
    assert.equal(client('c').signal.aborted, true, 'visiting b protects it');
    assert.equal(client('b').signal.aborted, false);

    const bUpdate = until(
      (e) =>
        e.sessionId === 'b' &&
        e.type === 'sessionCache' &&
        e.data.entries.length,
    );
    client('b').push('b version one');
    const before = await bUpdate;
    const fUpdate = until((e) => e.sessionId === 'f' && e.data.entries.length);
    client('f').push('different session');
    await fUpdate;
    const reopened = await open('b');
    assert.equal(reopened.data.entries[0].items[0].title, 'b version one');
    assert.equal(
      reopened.data.entries[0].items[0].rev,
      before.data.entries[0].items[0].rev,
    );
    assert.equal(
      (
        await runtime.itemDetail({
          sessionId: 'b',
          entryId: 'same-entry',
          itemId: 'same-tool',
        })
      ).rev,
      before.data.entries[0].items[0].rev,
    );

    runtime.closeSession();
    assert.equal(
      clients.filter((c) => !c.signal.aborted).length,
      3,
      'no foreground means only three subscriptions',
    );
    assert.equal(
      (await runtime.sendTurn({ sessionId: 'b', text: 'hidden' })).state,
      'not_sent',
    );
    const afterClose = until(
      (e) =>
        e.sessionId === 'b' &&
        e.type === 'sessionCache' &&
        e.data.entries[0]?.items[0]?.title === 'after close',
    );
    client('b').push('after close');
    await afterClose;
    const count = clients.length;
    assert.equal(
      (await open('b')).data.entries[0].items[0].title,
      'after close',
    );
    assert.equal(clients.length, count);

    // Queue an update on the oldest Session and evict before its cache timer fires.
    client('e').push('last before eviction');
    await new Promise((resolve) => setImmediate(resolve));
    await open('g');
    await open('h');
    assert.equal(client('e').signal.aborted, true);
    assert.ok(
      events.some(
        (e) =>
          e.sessionId === 'e' &&
          e.type === 'sessionCache' &&
          e.data.entries[0]?.items[0]?.title === 'last before eviction',
      ),
    );
    const oldClients = [...clients];
    await open('b', 'other-workspace');
    assert.ok(oldClients.every((c) => c.signal.aborted));
    runtime.stopSessions();
    assert.ok(clients.every((c) => c.signal.aborted));
  },
);

test(
  'eviction during authorization cannot start a late bootstrap',
  { timeout: 5000 },
  async (t) => {
    const bootstraps = [];
    globalThis.__sessionClient = class {
      constructor({ url }) {
        this.url = url;
      }
      async bootstrap() {
        bootstraps.push(this.url);
        return { ok: false, result: { code: 'synthetic_offline' } };
      }
    };
    const runtime = await loadRuntime();
    t.after(() => {
      runtime.stopSessions();
      delete globalThis.__sessionClient;
    });
    let authorize;
    const grant = new Promise((resolve) => {
      authorize = resolve;
    });
    const events = [];
    for (const id of ['late-a', 'late-b', 'late-c', 'late-d', 'late-e'])
      await runtime.openSession(
        id,
        'w1',
        () => grant,
        (e) => events.push(e),
        async () => {},
      );
    authorize({ token: 'synthetic', gatewayBaseUrl: 'https://x.invalid' });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(bootstraps.length, 4);
    assert.ok(
      bootstraps.every((url) => !decodeURIComponent(url).endsWith(':late-a')),
    );
    assert.ok(
      events
        .filter((e) => e.sessionId === 'late-a')
        .every((e) => JSON.parse(e.session).status === 'syncing'),
    );
    const before = bootstraps.length;
    await runtime.openSession(
      'late-e',
      'w1',
      () => grant,
      () => {},
      async () => {},
    );
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(
      bootstraps.length,
      before + 1,
      'opening an offline retained Session retries bootstrap',
    );
  },
);
