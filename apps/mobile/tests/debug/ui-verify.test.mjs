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
