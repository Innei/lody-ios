import assert from 'node:assert/strict';
import fs from 'node:fs';
import { test } from 'node:test';
import { build } from 'esbuild';

const copy = JSON.parse(
  fs.readFileSync(new URL('../../locales/en.json', import.meta.url), 'utf8'),
);
const toasts = [];
const shares = [];
globalThis.__shareKit = {
  showToast: (message, kind) => toasts.push({ message, kind }),
};
globalThis.__shares = shares;
globalThis.__shareOutcome = () => ({ action: 'sharedAction' });
globalThis.__shareFailure = undefined;

const bundle = await build({
  entryPoints: [new URL('../../src/lib/share.ts', import.meta.url).pathname],
  bundle: true,
  format: 'esm',
  write: false,
  plugins: [
    {
      name: 'share',
      setup(b) {
        b.onResolve({ filter: /^@lody-ios\/kit$/ }, () => ({
          path: 'kit',
          namespace: 'mock',
        }));
        b.onResolve({ filter: /^react-native$/ }, () => ({
          path: 'rn',
          namespace: 'mock',
        }));
        b.onLoad({ filter: /.*/, namespace: 'mock' }, ({ path }) => ({
          contents:
            path === 'kit'
              ? 'export const showToast=globalThis.__shareKit.showToast;'
              : 'export const Share={dismissedAction:"dismissedAction",share:async(content)=>{globalThis.__shares.push(content);const failure=globalThis.__shareFailure;if(failure)throw failure;return globalThis.__shareOutcome();}};',
        }));
      },
    },
  ],
});
const { shareLink } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);

test('a completed share is announced', async () => {
  toasts.length = 0;
  shares.length = 0;
  await shareLink('https://lody.ai/work/sessions/s1');
  assert.deepEqual(shares, [{ url: 'https://lody.ai/work/sessions/s1' }]);
  assert.deepEqual(toasts, [
    { message: copy['share.toast.shared'], kind: 'info' },
  ]);
});

test('copying through the share sheet names the clipboard', async () => {
  toasts.length = 0;
  globalThis.__shareOutcome = () => ({
    action: 'sharedAction',
    activityType: 'com.apple.UIKit.activity.CopyToPasteboard',
  });
  await shareLink('https://lody.ai/work/sessions/s1');
  assert.deepEqual(toasts, [
    { message: copy['share.toast.linkCopied'], kind: 'info' },
  ]);
  globalThis.__shareOutcome = () => ({ action: 'sharedAction' });
});

test('dismissing the share sheet stays silent', async () => {
  toasts.length = 0;
  globalThis.__shareOutcome = () => ({ action: 'dismissedAction' });
  await shareLink('https://lody.ai/work/sessions/s1');
  assert.deepEqual(toasts, []);
  globalThis.__shareOutcome = () => ({ action: 'sharedAction' });
});

test('a failed share sheet reports the failure', async () => {
  toasts.length = 0;
  globalThis.__shareFailure = new Error('no window');
  await shareLink('https://lody.ai/work/sessions/s1');
  assert.deepEqual(
    toasts.map((toast) => toast.message),
    [copy['share.toast.failed']],
  );
  globalThis.__shareFailure = undefined;
});
