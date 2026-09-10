import assert from 'node:assert/strict';
import { test } from 'node:test';
import { build } from 'esbuild';

const writes = [];
globalThis.__sessionActionKit = {
  archiveSession: async () => {},
  pinSession: async () => {},
  markSessionRead: async (payload) => {
    writes.push(JSON.parse(payload));
    return '{}';
  },
  showToast() {},
};

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
              ? 'export const {archiveSession,pinSession,markSessionRead,showToast}=globalThis.__sessionActionKit;'
              : 'export function openCatalogRow(){} export function requestNewSession(){} export function isChatSession(){return false} export function projectIdOfRow(){}',
        }));
      },
    },
  ],
});
const { sessionRowAction, setRead } = await import(
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
