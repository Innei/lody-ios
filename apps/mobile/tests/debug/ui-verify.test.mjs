import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const read = (relative) =>
  fs.readFileSync(new URL(relative, import.meta.url), 'utf8');

test('offline fixtures opt in from EXPO_PUBLIC_UI_VERIFY without __DEV__', () => {
  const uiVerify = read('../../src/lib/uiVerify.ts');
  assert.match(
    uiVerify,
    /^export const uiVerify = process\.env\.EXPO_PUBLIC_UI_VERIFY === '1';$/m,
  );

  for (const file of [
    '../../src/cloud/auth/AuthProvider.tsx',
    '../../src/features/community/notice.ts',
    '../../src/features/notifications/PushCoordinator.tsx',
    '../../src/screens/debug/HomePreviewScreen.tsx',
  ]) {
    assert.doesNotMatch(
      read(file),
      /__DEV__ &&\s*process\.env\.EXPO_PUBLIC_UI_VERIFY/,
      file,
    );
  }
});

test('the product onboarding gate stays off during fixture runs', () => {
  const source = read('../../src/hooks/screens/useOnboardingGate.ts');
  assert.match(source, /if \(uiVerify \|\| !localReady/);
});

test('native --ui-verify works without a Debug compilation gate', () => {
  const flag = read('../../modules/lody-kit/ios/LodyUIVerify.swift');
  assert.match(flag, /enum LodyUIVerify/);
  assert.doesNotMatch(flag, /#if DEBUG/);

  const push = read(
    '../../modules/lody-kit/ios/Notifications/PushNotifications.swift',
  );
  assert.match(
    push,
    /func start\([^\)]*\) \{\n    if LodyUIVerify\.enabled \|\| LodyUIVerify\.offline \{ return \}/,
  );

  const module = read('../../modules/lody-kit/ios/LodyKitModule.swift');
  assert.match(module, /let offlineProbe = LodyUIVerify\.offline/);
  assert.match(module, /let uiVerifyHome = LodyUIVerify\.home/);
  assert.doesNotMatch(module, /#if DEBUG\s+offlineProbe = ProcessInfo/);
});
