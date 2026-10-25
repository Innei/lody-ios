import assert from 'node:assert/strict';
import { test } from 'node:test';
import { build } from 'esbuild';

const shown = [];
let listener;
let popped = 0;
globalThis.__shellNative = {
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
};
const mocks = {
  react:
    'export const createContext = () => ({}); export const use = () => null; export const useEffect = () => {}; export const useSyncExternalStore = () => false;',
  'expo-router': 'export const router = { push() {} };',
  '@lody-ios/kit':
    'export const { navPresent, navPopToRoot, addNavListener } = globalThis.__shellNative;',
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
        b.onResolve(
          { filter: /^(react|expo-router|@lody-ios\/kit)$/ },
          ({ path }) => ({
            path,
            namespace: 'mock',
          }),
        );
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
  shellAtRoot,
  shellNavigationState,
  shellPopToRoot,
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
