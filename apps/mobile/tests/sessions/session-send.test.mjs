import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const tick = () => new Promise((resolve) => setImmediate(resolve));
function deferred() {
  let resolve;
  const promise = new Promise((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
function harness() {
  const cells = [];
  let cursor = 0,
    hook,
    input,
    result,
    queued = false;
  const effects = [];
  const schedule = () => {
    if (queued) return;
    queued = true;
    queueMicrotask(() => {
      queued = false;
      render();
    });
  };
  function render() {
    cursor = 0;
    result = hook(input);
    effects.splice(0).forEach((effect) => effect());
  }
  return {
    react: {
      useRef(value) {
        const index = cursor++;
        return (cells[index] ??= { current: value });
      },
      useState(value) {
        const index = cursor++;
        if (!(index in cells)) cells[index] = value;
        return [
          cells[index],
          (next) => {
            const updated =
              typeof next === 'function' ? next(cells[index]) : next;
            if (Object.is(cells[index], updated)) return;
            cells[index] = updated;
            schedule();
          },
        ];
      },
      useEffect(effect, deps) {
        const index = cursor++;
        if (
          cells[index] &&
          deps.every((dep, i) => Object.is(dep, cells[index][i]))
        )
          return;
        cells[index] = deps;
        effects.push(effect);
      },
    },
    start(fn, args) {
      hook = fn;
      input = args;
      render();
    },
    update(change) {
      Object.assign(input, change);
      schedule();
    },
    get result() {
      return result;
    },
  };
}

const session = {
  id: 's1',
  machineId: 'm1',
  cliType: 'builtin',
  agentType: 'codex',
  archived: false,
};
const draft = {
  id: 'BFBAD3D5-3B07-4E9A-BA66-FC3002179887',
  text: 'hello',
  startedAt: 1_780_000_000_000,
  attachments: [{ id: 'a', uri: 'file:///a', name: 'a.txt', kind: 'file' }],
  choice: {},
  phase: 'waiting',
};

async function load(hooks, native) {
  globalThis.__sendHooks = hooks;
  globalThis.__sendNative = native;
  const bundle = await build({
    entryPoints: [
      new URL('../../src/features/sessions/useSessionSend.ts', import.meta.url)
        .pathname,
    ],
    bundle: true,
    format: 'esm',
    write: false,
    plugins: [
      {
        name: 'hooks',
        setup(b) {
          b.onResolve(
            { filter: /^(react|react-native|@lody-ios\/kit)$/ },
            ({ path }) => ({ path, namespace: 'mock' }),
          );
          b.onLoad({ filter: /.*/, namespace: 'mock' }, ({ path }) => ({
            contents: {
              react:
                'export const {useEffect,useRef,useState}=globalThis.__sendHooks;',
              'react-native': 'export const Alert={alert(){}};',
              '@lody-ios/kit':
                'export const {createSession,sendSessionTurn}=globalThis.__sendNative;',
            }[path],
          }));
        },
      },
    ],
  });
  return import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text + `\n// ${Math.random()}`).toString('base64')}`
  );
}

async function setup(
  initialSend,
  native,
  persist = async () => {},
  status = 'live',
) {
  const hooks = harness();
  const { useSessionSend } = await load(hooks.react, native);
  const outbox = {
    ready: true,
    records: [{ session, send: initialSend }],
    getSnapshot() {
      return { records: outbox.records, ready: true };
    },
    put(record) {
      outbox.records = [record];
      hooks.update({ record });
      return persist(record);
    },
    async remove() {
      outbox.records = [];
      hooks.update({ record: undefined });
    },
  };
  hooks.start(useSessionSend, {
    outbox,
    session,
    record: outbox.records[0],
    snapshot: { status, entries: [] },
    connected: true,
    serverCreated: true,
    userId: 'u1',
    overflow: false,
  });
  await tick();
  return { hooks, outbox };
}

test('send waits for durable dispatch state and carries the same identity and attachments', async () => {
  const disk = deferred();
  const calls = [];
  const { hooks, outbox } = await setup(
    {
      ...draft,
      choice: {
        configOptionValues: { permission_mode: 'always-approve', fast: false },
      },
    },
    {
      createSession() {
        throw Error('unexpected creation');
      },
      async sendSessionTurn(payload) {
        calls.push(JSON.parse(payload));
        return JSON.stringify({ state: 'accepted' });
      },
    },
    (record) =>
      record.send.phase === 'sending' ? disk.promise : Promise.resolve(),
  );
  assert.equal(calls.length, 0);
  disk.resolve();
  await tick();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].id, draft.id);
  assert.deepEqual(calls[0].attachments, draft.attachments);
  assert.deepEqual(calls[0].configOptionValues, {
    permission_mode: 'always-approve',
    fast: false,
  });
  assert.equal(outbox.records[0].send.phase, 'accepted');
  assert.equal(
    hooks.result.awaitingReply,
    true,
    'The ACK-to-assistant gap must still use busy composer behavior',
  );
});

test('a definite send failure retains the draft and an ambiguous result never automatically retries', async () => {
  for (const state of ['not_sent', 'unknown']) {
    let calls = 0;
    const { hooks, outbox } = await setup(draft, {
      async createSession() {
        throw Error('unexpected creation');
      },
      async sendSessionTurn() {
        calls++;
        return JSON.stringify({ state });
      },
    });
    assert.equal(
      outbox.records[0].send.phase,
      state === 'not_sent' ? 'failed' : 'unknown',
    );
    assert.equal(outbox.records[0].send.text, draft.text);
    assert.deepEqual(outbox.records[0].send.attachments, draft.attachments);
    hooks.update({ snapshot: { status: 'live', entries: [] } });
    await tick();
    assert.equal(calls, 1);
  }
});

test('resubmitting a failed first turn keeps independent configuration unless the next draft overrides it', async () => {
  const saved = { permission_mode: 'always-approve', fast: false };
  for (const override of [undefined, { permission_mode: 'ask' }]) {
    const calls = [];
    const { hooks } = await setup(
      { ...draft, phase: 'failed', choice: { configOptionValues: saved } },
      {
        async sendSessionTurn(payload) {
          calls.push(JSON.parse(payload));
          return JSON.stringify({ state: 'accepted' });
        },
      },
    );
    hooks.result.submit({
      ...draft,
      choice: { modelId: 'picked', configOptionValues: override },
    });
    await tick();
    assert.equal(calls.length, 1);
    assert.deepEqual(calls[0].configOptionValues, override ?? saved);
    assert.equal(calls[0].modelId, 'picked');
  }
});

test('creation transitions into one first turn only after the destination runtime is live', async () => {
  let creates = 0,
    sends = 0;
  const { hooks, outbox } = await setup(
    { ...draft, creation: '{"sessionId":"s1"}' },
    {
      async createSession() {
        creates++;
        return JSON.stringify({ state: 'created', session });
      },
      async sendSessionTurn() {
        sends++;
        return JSON.stringify({ state: 'accepted' });
      },
    },
    async () => {},
    'syncing',
  );
  assert.equal(creates, 1);
  assert.equal(sends, 0);
  assert.equal(outbox.records[0].send.phase, 'waiting');
  hooks.update({ snapshot: { status: 'live', entries: [] } });
  await tick();
  assert.equal(sends, 1);
  assert.equal(outbox.records[0].send.phase, 'accepted');
});

test('a cached user entry cannot confirm an ambiguous write or discard the draft', async () => {
  const { hooks, outbox } = await setup(
    { ...draft, phase: 'unknown' },
    {
      async createSession() {
        throw Error('must not create');
      },
      async sendSessionTurn() {
        throw Error('must not replay');
      },
    },
  );
  hooks.update({
    snapshot: {
      status: 'live',
      entries: [{ id: draft.id, role: 'user', items: [] }],
    },
  });
  await tick();
  assert.equal(outbox.records[0].send.phase, 'unknown');
  assert.equal(hooks.result.clearDraftToken, 0);
});

test('a send superseded while its state is being saved cannot dispatch', async () => {
  const disk = deferred();
  let sends = 0;
  const { outbox } = await setup(
    draft,
    {
      async createSession() {
        throw Error('unexpected creation');
      },
      async sendSessionTurn() {
        sends++;
        return JSON.stringify({ state: 'accepted' });
      },
    },
    (record) =>
      record.send.phase === 'sending' ? disk.promise : Promise.resolve(),
  );
  await outbox.put({
    session,
    send: { ...draft, phase: 'failed', reason: 'previous persistence failed' },
  });
  disk.resolve();
  await tick();
  assert.equal(sends, 0);
  assert.equal(outbox.records[0].send.phase, 'failed');
});

test('receipts unlock successive sends while an assistant is running; writes still serialize', async () => {
  const ack = deferred();
  let calls = 0;
  const { hooks, outbox } = await setup(draft, {
    sendSessionTurn: async () => {
      calls++;
      return ack.promise;
    },
  });
  await tick();
  assert.equal(hooks.result.canSend, false);
  ack.resolve(JSON.stringify({ state: 'queued' }));
  await tick();
  await tick();
  assert.equal(outbox.records[0].send.phase, 'queued');
  assert.equal(hooks.result.awaitingReply, false);
  assert.equal(hooks.result.canSend, true);
  assert.equal(hooks.result.sending, false);
  hooks.result.submit({ ...draft, id: 'next' });
  await tick();
  await tick();
  assert.equal(calls, 2);
  assert.equal(outbox.records[0].send.id, 'next');
});

test('explicit retry keeps the failed message identity and attachments, and cannot replay an unknown send', async () => {
  for (const state of ['failed', 'unknown']) {
    const calls = [];
    const { hooks, outbox } = await setup(
      { ...draft, phase: state },
      {
        async sendSessionTurn(payload) {
          calls.push(JSON.parse(payload));
          return JSON.stringify({ state: 'accepted' });
        },
      },
    );
    assert.equal(calls.length, 0);
    hooks.result.retry();
    await tick();
    if (state === 'failed') {
      assert.equal(calls.length, 1);
      assert.equal(calls[0].id, draft.id);
      assert.deepEqual(calls[0].attachments, draft.attachments);
      assert.equal(outbox.records[0].send.phase, 'accepted');
    } else {
      assert.equal(calls.length, 0);
      assert.equal(outbox.records[0].send.phase, 'unknown');
    }
  }
});
