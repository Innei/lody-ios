import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';

const boundary = { opens: 0, writes: 0, messages: [], failure: false };
globalThis.__languageSettings = boundary;
const bundle = await build({
  entryPoints: [
    new URL('../../src/screens/PreferencesScreen.tsx', import.meta.url)
      .pathname,
  ],
  bundle: true,
  jsx: 'automatic',
  format: 'esm',
  write: false,
  plugins: [
    {
      name: 'settings-boundaries',
      setup(builder) {
        const mocks = {
          '@lody-ios/kit': 'export const NativeGroupedList = () => null;',
          'react/jsx-runtime': 'export const jsx = (type, props) => props;',
          'react-native': `export const Linking = { async openSettings() {
            globalThis.__languageSettings.opens++;
            if (globalThis.__languageSettings.failure) throw Error('unavailable');
          } };`,
          '@/features/settings/queued-message-behavior': `export const useQueuedMessageBehavior = () => ({
            queuedMessageBehavior: 'guide', setQueuedMessageBehavior() { globalThis.__languageSettings.writes++; }
          });`,
          '@/hooks/screens/usePageRuntime': `export const usePageRuntime = () => ({ push() { throw Error('Unexpected navigation'); } });`,
          '@/lib/presentation': 'export const definePage = page => page;',
          '@/lib/theme/palette': 'export const usePalette = () => ({});',
          '@/ui/toast':
            'export const showToast = message => globalThis.__languageSettings.messages.push(message);',
          './NotificationSettingsScreen':
            'export const NotificationSettingsScreen = {};',
          './QuickRepliesScreen': 'export const QuickRepliesScreen = {};',
        };
        builder.onResolve({ filter: /.*/ }, ({ path }) =>
          path in mocks ? { path, namespace: 'boundary' } : undefined,
        );
        builder.onLoad({ filter: /.*/, namespace: 'boundary' }, ({ path }) => ({
          contents: mocks[path],
        }));
      },
    },
  ],
});
const { PreferencesScreen } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);

test('language opens system settings and handles rejection without changing local preferences', async () => {
  const view = PreferencesScreen.Component();
  for (const failure of [false, true]) {
    boundary.failure = failure;
    view.onRowPress({ nativeEvent: { id: 'language' } });
    await new Promise(setImmediate);
  }
  assert.equal(boundary.opens, 2);
  assert.equal(boundary.writes, 0);
  assert.deepEqual(boundary.messages, ['Couldn’t open iOS Settings.']);
  delete globalThis.__languageSettings;
});
