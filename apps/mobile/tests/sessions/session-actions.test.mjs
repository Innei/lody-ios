import assert from 'node:assert/strict';
import { test } from 'node:test';
import { build } from 'esbuild';

const writes = [];
const shares = [];
const alerts = [];
let deleteRequest;
globalThis.__sessionAlerts = alerts;
globalThis.__sessionActionKit = {
  archiveSession: async () => {},
  deleteSession: (payload) => deleteRequest(payload),
  pinSession: async () => {},
  markSessionRead: async (payload) => {
    writes.push(JSON.parse(payload));
    return '{}';
  },
  renameSession: async (payload) => {
    writes.push(JSON.parse(payload));
    return '{}';
  },
  showToast() {},
};
globalThis.__sessionShares = shares;
globalThis.__sessionPrompts = [];
globalThis.__sessionPromptValue = undefined;

const bundle = await build({
  entryPoints: [
    new URL('../../src/features/sessions/sessionActions.ts', import.meta.url)
      .pathname,
  ],
  bundle: true,
  format: 'esm',
  write: false,
  plugins: [
    {
      name: 'kit',
      setup(b) {
        b.onResolve({ filter: /^@lody-ios\/kit$/ }, () => ({
          path: 'kit',
          namespace: 'mock',
        }));
        b.onResolve({ filter: /^react-native$/ }, () => ({
          path: 'rn',
          namespace: 'mock',
        }));
        b.onResolve(
          { filter: /openCatalogRow|sessionNav|\/inbox\.ts$/ },
          () => ({
            path: 'nav',
            namespace: 'mock',
          }),
        );
        b.onLoad({ filter: /.*/, namespace: 'mock' }, ({ path }) => ({
          contents:
            path === 'kit'
              ? 'export const {archiveSession,deleteSession,pinSession,markSessionRead,renameSession,showToast}=globalThis.__sessionActionKit;'
              : path === 'rn'
                ? 'export const Share={share:async(content)=>{globalThis.__sessionShares.push(content);}}; export const Alert={alert:(title,message,buttons)=>globalThis.__sessionAlerts.push({title,message,buttons}),prompt:(title,message,buttons,type,defaultValue)=>{globalThis.__sessionPrompts.push({title,message,type,defaultValue}); const confirm=buttons.find((button)=>button.style!=="cancel"); confirm?.onPress?.(globalThis.__sessionPromptValue??defaultValue);}};'
                : 'export function openCatalogRow(){} export function requestNewSession(){} export function isChatSession(){return false} export function projectIdOfRow(){}',
        }));
      },
    },
  ],
});
const { sessionRowAction, setRead, listRowAction, subscribeSessionDeletion } =
  await import(
    `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  );

const session = {
  id: 's1',
  machineId: 'm1',
  title: 'T',
  status: 'completed',
  archived: false,
  pinned: false,
  projectId: 'p1',
  createdAt: '2026-09-06T14:00:00+08:00',
  lastMessageAt: 1_000,
};

test('delete requires confirmation, locks duplicates, reports failure without closing and permits retry', async () => {
  const events = [],
    requests = [];
  const unsubscribe = subscribeSessionDeletion((event) =>
    events.push(event.state),
  );
  let reject, resolve;
  deleteRequest = (payload) => {
    requests.push(JSON.parse(payload));
    return new Promise((yes, no) => {
      resolve = yes;
      reject = no;
    });
  };
  const catalog = { projects: [], machineIds: [], sessions: [session] };
  const open = () => sessionRowAction('w1', catalog, session.id, 'delete');
  open();
  assert.equal(requests.length, 0);
  alerts
    .at(-1)
    .buttons.find((button) => button.style === 'cancel')
    .onPress?.();
  assert.equal(requests.length, 0);
  open();
  const confirm = alerts
    .at(-1)
    .buttons.find((button) => button.style === 'destructive');
  confirm.onPress();
  confirm.onPress();
  assert.equal(requests.length, 1);
  reject(new Error('offline'));
  await new Promise(setImmediate);
  assert.deepEqual(events, ['deleting', 'failed']);
  open();
  alerts
    .at(-1)
    .buttons.find((button) => button.style === 'destructive')
    .onPress();
  resolve('{}');
  await new Promise(setImmediate);
  assert.deepEqual(events, ['deleting', 'failed', 'deleting', 'deleted']);
  assert.deepEqual(requests[0], {
    workspaceId: 'w1',
    sessionId: 's1',
    sessionIds: ['s1'],
  });
  unsubscribe();
});

test('a running contained tab blocks deletion before confirmation; independent running sessions do not', () => {
  const child = {
    ...session,
    id: 'tab',
    parentSessionId: session.id,
    status: 'requestPermission',
  };
  const catalog = { projects: [], machineIds: [], sessions: [session, child] };
  sessionRowAction('w1', catalog, session.id, 'delete');
  assert.equal(alerts.at(-1).buttons, undefined);
  catalog.sessions[1] = { ...child, archived: true };
  sessionRowAction('w1', catalog, session.id, 'delete');
  assert.ok(
    alerts.at(-1).buttons.some((button) => button.style === 'destructive'),
  );
  catalog.sessions[1] = {
    ...session,
    id: 'independent',
    openedBySessionId: session.id,
    status: 'running',
  };
  sessionRowAction('w1', catalog, session.id, 'delete');
  assert.ok(
    alerts.at(-1).buttons.some((button) => button.style === 'destructive'),
  );
});

test('swipe 已读 writes lastReadAt at least as new as the last message', async () => {
  const before = Date.now();
  sessionRowAction(
    'w1',
    { projects: [], sessions: [session], machineIds: [] },
    's1',
    'read',
  );
  await Promise.resolve();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].workspaceId, 'w1');
  assert.equal(writes[0].sessionId, 's1');
  assert.ok(writes[0].lastReadAt >= session.lastMessageAt);
  assert.ok(writes[0].lastReadAt >= before);
});

test('setRead covers a lastMessageAt that is ahead of now', async () => {
  writes.length = 0;
  const future = Date.now() + 60_000;
  await setRead('w1', { ...session, lastMessageAt: future });
  assert.equal(writes[0].lastReadAt, future);
});

test('list share opens the desktop session url', async () => {
  shares.length = 0;
  listRowAction(
    { id: 'workspace', slug: 'work' },
    { projects: [], sessions: [session], machineIds: [] },
    's1',
    'share',
  );
  await Promise.resolve();
  assert.deepEqual(shares, [{ url: 'https://lody.ai/work/sessions/s1' }]);
});

test('list rename prompts with the current title and writes the trimmed name', async () => {
  writes.length = 0;
  globalThis.__sessionPrompts.length = 0;
  globalThis.__sessionPromptValue = '  New title  ';
  listRowAction(
    { id: 'workspace', slug: 'work' },
    { projects: [], sessions: [session], machineIds: [] },
    's1',
    'rename',
  );
  await Promise.resolve();
  assert.equal(globalThis.__sessionPrompts.length, 1);
  assert.equal(globalThis.__sessionPrompts[0].defaultValue, 'T');
  assert.equal(globalThis.__sessionPrompts[0].type, 'plain-text');
  assert.equal(writes.length, 1);
  assert.equal(writes[0].workspaceId, 'workspace');
  assert.equal(writes[0].sessionId, 's1');
  assert.equal(writes[0].title, 'New title');
});

test('list rename ignores a blank title', async () => {
  writes.length = 0;
  globalThis.__sessionPromptValue = '   ';
  listRowAction(
    { id: 'workspace', slug: 'work' },
    { projects: [], sessions: [session], machineIds: [] },
    's1',
    'rename',
  );
  await Promise.resolve();
  assert.equal(writes.length, 0);
});
