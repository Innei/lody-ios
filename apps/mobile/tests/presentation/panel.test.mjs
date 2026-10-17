import assert from 'node:assert/strict';
import { mock, test } from 'node:test';

const routed = [];
mock.module('expo-router', {
  namedExports: {
    router: {
      push(value) {
        routed.push(value);
      },
    },
  },
});
const {
  closePanel,
  getPanelEntries,
  openPanel,
  panelPresent,
  popPanel,
  subscribePanel,
} = await import('../../src/lib/presentation/panelStore.ts');

const page = (id, panel = true) => ({
  id,
  Component: () => null,
  panel,
  presentation: { style: 'push' },
  title: id,
});
const diff = page('diff');
const files = page('files');
const content = page('content');
const permission = page('permission', false);

test('a chat tap replaces the panel stack and cancels what it showed', async () => {
  const first = openPanel(diff, { path: 'a.ts' }, 'replace');
  const nested = openPanel(content, { path: 'a.ts' }, 'push');
  const second = openPanel(files, { sessionId: 's' }, 'replace');
  assert.deepEqual(await first, { status: 'cancelled' });
  assert.deepEqual(await nested, { status: 'cancelled' });
  assert.deepEqual(
    getPanelEntries().map((entry) => entry.page.id),
    ['files'],
  );
  closePanel();
  assert.deepEqual(await second, { status: 'cancelled' });
  assert.equal(getPanelEntries().length, 0);
});

test('tapping the item the panel already shows keeps it', async () => {
  openPanel(diff, { path: 'a.ts', entryId: 'e1' }, 'replace');
  const root = getPanelEntries()[0];
  const again = await openPanel(
    diff,
    { path: 'a.ts', entryId: 'e1' },
    'replace',
  );
  assert.deepEqual(again, { status: 'cancelled' });
  assert.equal(getPanelEntries()[0], root);
  closePanel();
});

test('taps inside the panel push, and popping a level settles it and everything above', async () => {
  void openPanel(files, { sessionId: 's' }, 'replace');
  const file = openPanel(content, { path: 'b.ts' }, 'push');
  const fileDiff = openPanel(diff, { path: 'b.ts' }, 'push');
  assert.deepEqual(
    getPanelEntries().map((entry) => entry.page.id),
    ['files', 'content', 'diff'],
  );
  popPanel(getPanelEntries()[1].key, { status: 'completed', value: 'done' });
  assert.deepEqual(await file, { status: 'completed', value: 'done' });
  assert.deepEqual(await fileDiff, { status: 'cancelled' });
  assert.deepEqual(
    getPanelEntries().map((entry) => entry.page.id),
    ['files'],
  );
  closePanel();
});

test('subscribers hear every stack change', () => {
  let heard = 0;
  const unsubscribe = subscribePanel(() => heard++);
  void openPanel(diff, { path: 'c.ts' }, 'replace');
  void openPanel(content, { path: 'c.ts' }, 'push');
  closePanel();
  unsubscribe();
  void openPanel(diff, { path: 'd.ts' }, 'replace');
  closePanel();
  assert.equal(heard, 3);
});

test('a panel-aware present sends view pages to the panel and everything else through the router', async () => {
  const before = routed.length;
  const replace = panelPresent('replace');
  void replace(diff, { path: 'e.ts' });
  assert.deepEqual(
    getPanelEntries().map((entry) => entry.page.id),
    ['diff'],
  );
  assert.equal(routed.length, before);
  void replace(permission, { id: 1 });
  assert.equal(routed.length, before + 1);
  void panelPresent('push')(content, { path: 'e.ts' });
  assert.deepEqual(
    getPanelEntries().map((entry) => entry.page.id),
    ['diff', 'content'],
  );
  closePanel();
});
