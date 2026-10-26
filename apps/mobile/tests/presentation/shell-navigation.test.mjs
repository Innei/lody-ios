import assert from 'node:assert/strict';
import { test } from 'node:test';
import { build } from 'esbuild';

const shown = [];
const replies = [];
let listener;
let popped = 0;
const stacks = [];
globalThis.__shellNative = {
  navSetStack: async (ids) => {
    stacks.push(ids);
  },
  navPresent: async (page) => {
    shown.push(page);
  },
  navPopToRoot: async () => {
    popped += 1;
  },
  addNavListener: (next) => {
    listener = next;
    return { remove() {} };
  },
  navReply: (id, error = '') => {
    replies.push([id, error]);
  },
};
const mocks = {
  react:
    'export const createContext = () => ({}); export const use = () => null; export const useEffect = () => {}; export const useSyncExternalStore = () => false;',
  '@lody-ios/kit':
    'export const { navPresent, navPopToRoot, navSetStack, addNavListener, navReply } = globalThis.__shellNative;',
};
const root = new URL('../../src/lib/presentation/', import.meta.url).pathname;
const bundle = await build({
  stdin: {
    contents:
      "export * from './presentationStore.ts'; export * from './shellNavigation.ts';",
    resolveDir: root,
    loader: 'ts',
  },
  bundle: true,
  write: false,
  format: 'esm',
  platform: 'node',
  plugins: [
    {
      name: 'mocks',
      setup(b) {
        b.onResolve({ filter: /^(react|@lody-ios\/kit)$/ }, ({ path }) => ({
          path,
          namespace: 'mock',
        }));
        b.onLoad({ filter: /.*/, namespace: 'mock' }, ({ path }) => ({
          contents: mocks[path],
        }));
      },
    },
  ],
});
const {
  present,
  getPresentationSession,
  installShellNavigation,
  isShellSheetPage,
  registerShellPages,
  registerShellPreviewHandler,
  registerShellSessionHandler,
  shellAtRoot,
  shellNavigationState,
  shellPopToRoot,
  shellSetStack,
  shellStackRoutes,
} = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);
installShellNavigation();

const page = (style, extra = {}) => ({
  id: style,
  Component: () => null,
  title: style,
  presentation: {
    animationType: 'slide',
    dismissible: true,
    headerShown: true,
    headerVariant: 'glass',
    style,
    ...extra,
  },
});
const last = () => shown.at(-1);

test('pages reach native with their presentation, root and sheet containers', async () => {
  void present(page('push'), undefined, { root: true });
  const root = last();
  assert.equal(root.root, true);
  assert.equal(root.style, 'push');
  assert.equal(isShellSheetPage(root.id), false);
  assert.equal(shellAtRoot(), true);

  void present(
    page('formSheet', {
      sheetAllowedDetents: [0.62, 1],
      sheetGrabberVisible: true,
      sheetInitialDetentIndex: 'last',
    }),
  );
  const sheet = last();
  assert.deepEqual(
    {
      style: sheet.style,
      detents: sheet.detents,
      grabber: sheet.grabber,
      initialDetent: sheet.initialDetent,
      container: sheet.container,
    },
    {
      style: 'formSheet',
      detents: [0.62, 1],
      grabber: true,
      initialDetent: -1,
      container: undefined,
    },
  );
  assert.equal(isShellSheetPage(sheet.id), true);
  assert.equal(shellAtRoot(), false);

  void present(page('formSheet'), undefined, { container: sheet.id });
  const inner = last();
  assert.equal(inner.style, 'push');
  assert.equal(inner.container, sheet.id);
  assert.equal(isShellSheetPage(inner.id), true);

  void present(page('push'));
  assert.equal(isShellSheetPage(last().id), false);

  void present(page('pageSheet', { sheetAllowedDetents: 'fitToContents' }));
  assert.equal(last().detents, undefined);
});

test('a native close cancels the session once and releases the page', async () => {
  const result = present(page('pageSheet'));
  const { id } = last();
  listener({ type: 'focus', id });
  listener({ type: 'closed', id });
  assert.deepEqual(await result, { status: 'cancelled' });
  assert.equal(getPresentationSession(id), undefined);
  assert.equal(isShellSheetPage(id), false);
  listener({ type: 'closed', id });

  await shellPopToRoot();
  assert.equal(popped, 1);
});

test('the shell reports Router-shaped route names for root, pushed and presented pages', () => {
  const names = () => shellNavigationState().routes.map((route) => route.name);
  void present(page('push'), undefined, { root: true });
  assert.deepEqual(names(), ['index']);
  void present({ ...page('push'), id: 'project' });
  const sheet = present(page('formSheet'));
  const sheetId = last().id;
  void present(page('push'), undefined, { container: sheetId });
  assert.deepEqual(names(), [
    'index',
    'project/[projectId]',
    'presented/[presentationId]',
  ]);
  listener({ type: 'closed', id: sheetId });
  assert.deepEqual(names(), ['index', 'project/[projectId]']);
  return sheet;
});

test('a page inserted under the top keeps the route order native uses', async () => {
  void present(page('push'), undefined, { root: true });
  const root = last().id;
  void present(page('formSheet'));
  const sheet = last().id;
  void present({ ...page('push'), id: 'session' }, undefined, { insertAt: 1 });
  const session = last();
  assert.equal(session.insertAt, 1);
  const routes = shellStackRoutes();
  assert.deepEqual(
    routes.map((route) => route.params.presentationId),
    [root, session.id, sheet].map(String),
  );
  await shellSetStack([routes[0], routes[2]]);
  assert.deepEqual(stacks.at(-1), [root, sheet]);
});

test('native pages receive their params, and open registered pages in their sheet', () => {
  void present(
    { ...page('formSheet'), native: 'editor' },
    { item: { id: 'a' } },
  );
  const editor = last();
  assert.equal(editor.native, 'editor');
  assert.deepEqual(JSON.parse(editor.nativeParams), { item: { id: 'a' } });
  void present(page('pageSheet'));
  assert.equal(last().nativeParams, undefined);

  registerShellPages([{ ...page('push'), id: 'notification-settings' }]);
  listener({
    type: 'open',
    page: 'notification-settings',
    params: '{"from":"native"}',
    container: editor.id,
  });
  const opened = last();
  assert.equal(opened.container, editor.id);
  assert.equal(opened.style, 'push');
  assert.deepEqual(getPresentationSession(opened.id).params, {
    from: 'native',
  });

  void present(page('push'), undefined, { root: true });
  const root = last().id;
  listener({
    type: 'open',
    page: 'notification-settings',
    params: '{}',
    container: root,
  });
  assert.equal(last().container, undefined);
  assert.equal(last().style, 'push');

  const count = shown.length;
  listener({ type: 'open', page: 'missing', params: '{}', container: root });
  assert.equal(shown.length, count);
});

test('native pages open registered pages with a title, or as their own sheet', () => {
  registerShellPages([
    { ...page('push'), id: 'remote-settings' },
    { ...page('formSheet'), id: 'workspace-editor' },
  ]);
  void present(page('formSheet'));
  const sheet = last().id;
  listener({
    type: 'open',
    page: 'remote-settings',
    params: '{"kind":"agent"}',
    options: { title: 'Agents' },
    container: sheet,
  });
  assert.deepEqual(
    { title: last().title, style: last().style, container: last().container },
    { title: 'Agents', style: 'push', container: sheet },
  );
  listener({
    type: 'open',
    page: 'workspace-editor',
    params: '{"workspaceId":"w"}',
    options: { title: 'General', present: true },
    container: sheet,
  });
  assert.deepEqual(
    { title: last().title, style: last().style, container: last().container },
    { title: 'General', style: 'formSheet', container: undefined },
  );
  assert.deepEqual(getPresentationSession(last().id).params, {
    workspaceId: 'w',
  });
});

test('native session intents reach the registered handler without opening pages', () => {
  const intents = [];
  registerShellSessionHandler((intent) => intents.push(intent));
  const count = shown.length;
  const intent = {
    type: 'session',
    action: 'open',
    workspaceId: 'w',
    session: '{"id":"s"}',
  };
  listener(intent);
  assert.deepEqual(intents, [intent]);
  assert.equal(shown.length, count);
});

test('a native picker result completes its presentation before the page closes', async () => {
  registerShellPages([{ ...page('push'), id: 'picker' }]);
  const result = present({ ...page('push'), id: 'picker' }, { options: [] });
  const id = last().id;
  listener({ type: 'result', id, value: '"sheet-choice-2"' });
  listener({ type: 'closed', id });
  assert.deepEqual(await result, {
    status: 'completed',
    value: 'sheet-choice-2',
  });
});

test('preview requests reply after the fixture applies them, and fail without one', async () => {
  listener({ type: 'preview', id: 'r1', action: 'noop', fields: {} });
  assert.deepEqual(replies.at(-1), ['r1', 'preview_unavailable']);
  const applied = [];
  const unregister = registerShellPreviewHandler(async (action, fields) => {
    if (action === 'fail') throw new Error('offline_fixture');
    applied.push([action, fields]);
  });
  listener({
    type: 'preview',
    id: 'r2',
    action: 'deleteSessions',
    fields: { sessionIds: ['s'] },
  });
  listener({ type: 'preview', id: 'r3', action: 'fail', fields: {} });
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(applied, [['deleteSessions', { sessionIds: ['s'] }]]);
  assert.deepEqual(replies.slice(-2), [
    ['r2', ''],
    ['r3', 'offline_fixture'],
  ]);
  unregister();
  listener({ type: 'preview', id: 'r4', action: 'noop', fields: {} });
  assert.deepEqual(replies.at(-1), ['r4', 'preview_unavailable']);
});

test('native callbacks reach the presenting params once and reply, but not after the page closes', async () => {
  const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
  const calls = [];
  let release;
  const result = present(page('formSheet'), {
    label: 'not a function',
    onCreated: async (value) => {
      calls.push(value);
      if (value.fail) throw new Error('open_failed');
      if (value.wait) await new Promise((resolve) => (release = resolve));
    },
  });
  const id = last().id;
  const value = (body) => JSON.stringify(body);
  listener({
    type: 'callback',
    id: 'c1',
    page: id,
    name: 'onCreated',
    value: value({ ok: 1 }),
  });
  listener({
    type: 'callback',
    id: 'c2',
    page: id,
    name: 'onCreated',
    value: value({ fail: true }),
  });
  listener({
    type: 'callback',
    id: 'c3',
    page: id,
    name: 'label',
    value: 'null',
  });
  listener({
    type: 'callback',
    id: 'c4',
    page: 999,
    name: 'onCreated',
    value: 'null',
  });
  await settle();
  assert.deepEqual(calls, [{ ok: 1 }, { fail: true }]);
  assert.deepEqual(replies.slice(-4), [
    ['c3', 'callback_unavailable'],
    ['c4', 'callback_unavailable'],
    ['c1', ''],
    ['c2', 'open_failed'],
  ]);
  listener({
    type: 'callback',
    id: 'c5',
    page: id,
    name: 'onCreated',
    value: value({ wait: true }),
  });
  await settle();
  const before = replies.length;
  listener({ type: 'closed', id });
  release();
  await settle();
  assert.equal(
    replies.length,
    before,
    'A reply after the page closed must be dropped',
  );
  assert.equal((await result).status, 'cancelled');
});
