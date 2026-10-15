import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { test } from 'node:test';
import { pathToFileURL } from 'node:url';
import { build } from 'esbuild';
import { createElement, use } from 'react';
import { renderToString } from 'react-dom/server';

const require = createRequire(import.meta.url);
const boundary = {
  routes: [{ name: 'index' }],
  dismissals: 0,
  nativeDismissal: () => new Promise(() => {}),
  navigation: {
    getState: () => ({
      routes: boundary.routes,
      index: boundary.routes.length - 1,
    }),
  },
  params: {},
  router: {
    push(target) {
      boundary.params = target.params;
      boundary.routes.push({ name: target.pathname, params: target.params });
    },
    canDismiss: () => boundary.routes.length > 1,
    dismiss() {
      boundary.dismissals++;
      boundary.routes.pop();
    },
  },
};
globalThis.__presentationCloseBoundary = boundary;

const bundle = await build({
  stdin: {
    contents: `
      export { PresentedPageProvider } from './PresentedPage';
      export { PageRuntimeContext } from './page';
      export * from './presentationStore';
    `,
    resolveDir: new URL('../../src/lib/presentation/', import.meta.url)
      .pathname,
    loader: 'tsx',
  },
  bundle: true,
  format: 'esm',
  write: false,
  plugins: [
    {
      name: 'native-navigation-boundary',
      setup(builder) {
        builder.onResolve({ filter: /^react(?:\/.*)?$/ }, ({ path }) => ({
          path: pathToFileURL(require.resolve(path)).href,
          external: true,
        }));
        const mocks = {
          'expo-router': `
          const boundary = globalThis.__presentationCloseBoundary;
          export const router = boundary.router;
          export const useLocalSearchParams = () => boundary.params;
          export const useNavigation = () => boundary.navigation;
          export const useRouter = () => router;
        `,
          'react-native':
            'export const Platform = { OS: "ios", isPad: false };',
          '@lody-ios/kit': `
          export const navigationScrollEdgeEffects = {};
          // The Router must release a sheet without awaiting a separate UIKit
          // dismissal. No second native dismissal callback is supplied here.
          export const dismissSheetZoom = () => globalThis.__presentationCloseBoundary.nativeDismissal();
        `,
          './SheetStack': 'export const SheetStack = () => null;',
        };
        builder.onResolve(
          {
            filter:
              /^(expo-router|react-native|@lody-ios\/kit|\.\/SheetStack)$/,
          },
          ({ path }) => ({ path, namespace: 'boundary' }),
        );
        builder.onLoad({ filter: /.*/, namespace: 'boundary' }, ({ path }) => ({
          contents: mocks[path],
        }));
      },
    },
  ],
});
const {
  PresentedPageProvider,
  PageRuntimeContext,
  present,
  getPresentationSession,
} = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);
const page = {
  id: 'create-session',
  title: 'New session',
  Component: () => null,
  presentation: { style: 'formSheet', zoomSourceLabel: 'New session' },
};

function open() {
  const result = present(page, {});
  const id = Number(boundary.params.presentationId);
  let runtime;
  function Capture() {
    runtime = use(PageRuntimeContext);
    return null;
  }
  renderToString(
    createElement(PresentedPageProvider, { page }, createElement(Capture)),
  );
  return { id, result, runtime };
}

test('closing a zoom sheet releases repeated creations without a second native dismissal callback', async () => {
  for (let attempt = 0; attempt < 3; attempt++) {
    const sheet = open();
    assert.ok(getPresentationSession(sheet.id));
    sheet.runtime.cancel();
    sheet.runtime.cancel();
    assert.equal(
      boundary.routes.length,
      1,
      'Closed sheet still occupies the Router stack',
    );
    assert.equal(getPresentationSession(sheet.id), undefined);
    assert.deepEqual(await sheet.result, { status: 'cancelled' });
    assert.equal(
      boundary.dismissals,
      attempt + 1,
      'Repeated close dismissed another page',
    );
  }

  const completed = open();
  let finishTransition;
  boundary.nativeDismissal = () =>
    new Promise((resolve) => {
      finishTransition = resolve;
    });
  completed.runtime.finish('created');
  assert.ok(
    getPresentationSession(completed.id),
    'Send completion removed the composer before its transition ended',
  );
  finishTransition();
  await completed.result;
  const next = open();
  completed.runtime.cancel();
  assert.equal(
    boundary.routes.length,
    2,
    'A stale close removed the newly opened sheet',
  );
  assert.ok(getPresentationSession(next.id));
  assert.deepEqual(await completed.result, {
    status: 'completed',
    value: 'created',
  });
  next.runtime.cancel();
  assert.deepEqual(await next.result, { status: 'cancelled' });
});
