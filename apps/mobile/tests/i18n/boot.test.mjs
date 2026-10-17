import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';

test('startup uses the native supported language even when the first device preference is unsupported', async () => {
  for (const nativeLocale of ['en', 'zh-Hans']) {
    const bundle = await build({
      stdin: {
        contents: `import './boot.ts'; export { currentLocale, t } from './index.ts';`,
        resolveDir: new URL('../../src/lib/i18n/', import.meta.url).pathname,
      },
      bundle: true,
      format: 'esm',
      write: false,
      plugins: [
        {
          name: 'native-language-boundary',
          setup(builder) {
            builder.onResolve(
              { filter: /^(@lody-ios\/kit|expo-localization)$/ },
              ({ path }) => ({ path, namespace: 'boundary' }),
            );
            builder.onLoad(
              { filter: /.*/, namespace: 'boundary' },
              ({ path }) => ({
                contents:
                  path === '@lody-ios/kit'
                    ? `export const initialLocale = ${JSON.stringify(nativeLocale)};`
                    : `export const getLocales = () => [{languageTag:'ja-JP'}, {languageTag:'zh-Hans-CN'}];`,
              }),
            );
          },
        },
      ],
    });
    const app = await import(
      `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
    );
    assert.equal(app.currentLocale(), nativeLocale);
    assert.equal(
      app.t('settings.preferences.language'),
      nativeLocale === 'en' ? 'Language' : '语言',
    );
  }
});
