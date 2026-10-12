import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const tick = () => new Promise((resolve) => setImmediate(resolve));
function harness() {
  const cells = [];
  const effects = [];
  let cursor = 0,
    hook,
    input,
    result,
    active = true,
    queued = false;
  const render = () => {
    if (!active) return;
    queued = false;
    cursor = 0;
    result = hook(input);
    effects.splice(0).forEach((effect) => effect());
  };
  const schedule = () => {
    if (queued) return;
    queued = true;
    queueMicrotask(render);
  };
  return {
    react: {
      useRef(value) {
        return (cells[cursor++] ??= { current: value });
      },
      useState(value) {
        const index = cursor++;
        if (!(index in cells)) cells[index] = value;
        return [
          cells[index],
          (next) => {
            const value =
              typeof next === 'function' ? next(cells[index]) : next;
            if (Object.is(value, cells[index])) return;
            cells[index] = value;
            schedule();
          },
        ];
      },
      useEffect(effect, deps) {
        const index = cursor++;
        const previous = cells[index];
        if (
          previous &&
          deps.every((value, i) => Object.is(value, previous.deps[i]))
        )
          return;
        const current = { deps };
        cells[index] = current;
        effects.push(() => {
          previous?.cleanup?.();
          current.cleanup = effect();
        });
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
    unmount() {
      active = false;
      cells.forEach((cell) => cell?.cleanup?.());
    },
  };
}
const entry = {
  id: 'queued-1',
  role: 'user',
  status: 'queued',
  finished: false,
  rev: 0,
  items: [{ itemId: 'text', type: 'text', text: 'First', rev: 0 }],
};
const key = 'queue-controls:u:w:s';
async function setup({
  disk = new Map(),
  snapshot = { status: 'live', entries: [entry] },
  request,
  write,
} = {}) {
  const hooks = harness();
  const calls = [];
  const notices = [];
  const native = async (payload) => {
    const args = JSON.parse(payload);
    calls.push(args);
    return JSON.stringify(
      (await request?.(args)) ?? {
        state: 'rejected',
        reason: 'queue_item_started',
      },
    );
  };
  globalThis.__queueHooks = hooks.react;
  globalThis.__queueNative = native;
  globalThis.__queueLocal = {
    localGeneration: () => 0,
    readLocal: async (path) => disk.get(path),
    writeLocal: async (path, value) => {
      await write?.(path, value);
      disk.set(path, structuredClone(value));
    },
    showToast: (value) => notices.push(value),
  };
  const bundle = await build({
    entryPoints: [
      new URL('../../src/features/sessions/useSessionQueue.ts', import.meta.url)
        .pathname,
    ],
    bundle: true,
    format: 'esm',
    write: false,
    plugins: [
      {
        name: 'queue',
        setup(b) {
          b.onResolve(
            {
              filter:
                /^(react|@lody-ios\/kit|@\/cloud\/kv|@\/ui\/toast|@\/lib\/i18n)$/,
            },
            ({ path }) => ({ path, namespace: 'mock' }),
          );
          b.onLoad({ filter: /.*/, namespace: 'mock' }, ({ path }) => ({
            contents: {
              react:
                'export const {useEffect,useRef,useState}=globalThis.__queueHooks;',
              '@lody-ios/kit':
                'export const queueSessionMessage=globalThis.__queueNative;',
              '@/cloud/kv':
                'export const {localGeneration,readLocal,writeLocal}=globalThis.__queueLocal;',
              '@/ui/toast': 'export const {showToast}=globalThis.__queueLocal;',
              '@/lib/i18n': 'export const t=(key)=>key;',
            }[path],
          }));
        },
      },
    ],
  });
  const { useSessionQueue } = await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text + `\n// ${Math.random()}`).toString('base64')}`
  );
  hooks.start(useSessionQueue, {
    snapshot,
    sessionId: 's',
    workspaceId: 'w',
    userId: 'u',
    editable: true,
    request: native,
  });
  await tick();
  return { hooks, calls, notices, disk };
}

test('uncertain queue receipt hydration never repeats a write and retains a missing row until checked or dismissed', async () => {
  const disk = new Map([
    [key, [{ entry, receipt: { id: entry.id, action: 'delete' } }]],
  ]);
  const snapshot = { status: 'live', entries: [] };
  const { hooks, calls } = await setup({ disk, snapshot });
  assert.equal(calls.length, 0);
  assert.deepEqual(hooks.result.queueState.unknownIds, [entry.id]);
  assert.equal(hooks.result.entries[0].id, entry.id);
  await hooks.result.act({ id: entry.id, action: 'delete' });
  assert.equal(calls.length, 0, 'Unknown intent cannot be repeated');
  await hooks.result.act({ id: entry.id, action: 'check' });
  await tick();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].action, 'check');
  assert.equal(
    hooks.result.entries,
    snapshot.entries,
    'Known-started receipt releases its ghost without copying unrelated history',
  );
  assert.deepEqual(disk.get(key), []);
  hooks.unmount();
});

test('queue editor keeps its lease and independent draft after rejected save and closes only after successful save', async () => {
  const { hooks, calls, disk } = await setup({
    request: async (args) => {
      assert.equal(
        disk.get(key)[0].receipt.id,
        entry.id,
        'Intent must be durable before native mutation',
      );
      if (args.action === 'begin-edit')
        return { state: 'applied', editingStartedAt: 1000, text: 'First' };
      if (!args.text) return { state: 'rejected', reason: 'invalid_message' };
      return { state: 'applied' };
    },
  });
  await hooks.result.act({ id: entry.id, action: 'begin-edit' });
  await tick();
  assert.equal(hooks.result.queueState.editingId, entry.id);
  await hooks.result.act({ id: entry.id, action: 'save-edit', text: '' });
  await tick();
  assert.equal(hooks.result.queueState.editingId, entry.id);
  assert.equal(hooks.result.queueState.editingStartedAt, 1000);
  await hooks.result.act({
    id: entry.id,
    action: 'save-edit',
    text: 'Changed',
  });
  await tick();
  assert.equal(calls[2].baseText, 'First');
  assert.equal(calls[2].editingStartedAt, 1000);
  assert.equal(hooks.result.queueState.editingId, '');
  assert.deepEqual(disk.get(key), []);
  hooks.unmount();
});

test('offline queue changes do not dispatch and dismiss only clears local tracking', async () => {
  const disk = new Map([
    [key, [{ entry, receipt: { id: entry.id, action: 'delete' } }]],
  ]);
  const { hooks, calls } = await setup({ disk });
  hooks.update({ editable: false });
  await tick();
  await hooks.result.act({ id: entry.id, action: 'check' });
  assert.equal(calls.length, 0);
  await hooks.result.act({ id: entry.id, action: 'dismiss' });
  await tick();
  assert.deepEqual(disk.get(key), []);
  assert.equal(calls.length, 0);
  hooks.unmount();
});

test('receipt save failure prevents native mutation; a late old-account result cannot publish into the new scope', async () => {
  const failed = await setup({
    write: async () => {
      throw new Error('disk full');
    },
  });
  await failed.hooks.result.act({ id: entry.id, action: 'begin-edit' });
  await tick();
  assert.equal(failed.calls.length, 0);
  assert.equal(failed.hooks.result.queueState.busyId, '');
  failed.hooks.unmount();
  let complete;
  const pending = new Promise((resolve) => {
    complete = resolve;
  });
  const { hooks, disk } = await setup({ request: () => pending });
  const operation = hooks.result.act({ id: entry.id, action: 'begin-edit' });
  await tick();
  hooks.update({ userId: 'other', snapshot: { status: 'live', entries: [] } });
  await tick();
  complete({ state: 'applied', editingStartedAt: 1000, text: 'First' });
  await operation;
  await tick();
  assert.equal(hooks.result.queueState.editingId, '');
  assert.deepEqual(hooks.result.entries, []);
  assert.equal(disk.get('queue-controls:other:w:s'), undefined);
  assert.equal(
    disk.get(key)[0].receipt.action,
    'begin-edit',
    'Old scope retains an uncertain receipt rather than replaying',
  );
  hooks.unmount();
});
