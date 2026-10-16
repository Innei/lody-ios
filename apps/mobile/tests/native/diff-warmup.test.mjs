import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';

const bundle = await build({
  entryPoints: [
    new URL('../../src/features/diff/DiffWebViewWarmer.tsx', import.meta.url)
      .pathname,
  ],
  bundle: true,
  format: 'esm',
  platform: 'node',
  write: false,
  plugins: [
    {
      name: 'native-stubs',
      setup(builder) {
        builder.onResolve(
          { filter: /^(react|react\/jsx-runtime|react-native)$/ },
          ({ path }) => ({ path, namespace: 'test' }),
        );
        builder.onResolve({ filter: /\.\/DiffView$/ }, ({ path }) => ({
          path,
          namespace: 'test',
        }));
        builder.onLoad({ filter: /^react$/, namespace: 'test' }, () => ({
          contents:
            'export const useEffect = () => {}; export const useState = (value) => [value, () => {}];',
        }));
        builder.onLoad(
          { filter: /^react\/jsx-runtime$/, namespace: 'test' },
          () => ({
            contents:
              'export const jsx = () => null; export const jsxs = () => null;',
          }),
        );
        builder.onLoad(
          { filter: /^(react-native|\.\/DiffView)$/, namespace: 'test' },
          () => ({
            contents:
              'export const StyleSheet = { create: (value) => value }; export const useColorScheme = () => "light"; export const useWindowDimensions = () => ({ height: 0, width: 0 }); export const View = () => null; export const DiffView = () => null;',
          }),
        );
      },
    },
  ],
});
const warmer = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);

test('diff WebView warmup can be claimed only once per app process', () => {
  assert.equal(typeof warmer.claimDiffWebViewWarmup, 'function');
  assert.equal(warmer.claimDiffWebViewWarmup(), true);
  assert.equal(warmer.claimDiffWebViewWarmup(), false);
});
