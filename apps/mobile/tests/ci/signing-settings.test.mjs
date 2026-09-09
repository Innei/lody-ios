import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../../../..', import.meta.url));
const filter = path.join(
  repositoryRoot,
  '.github/scripts/verify-signing-settings.jq',
);
const profiles = {
  'app.innei.lody': 'APP-UUID',
  'app.innei.lody.notification-service': 'EXTENSION-UUID',
};

function settings(bundle, profile) {
  return {
    CODE_SIGN_IDENTITY: 'Apple Distribution',
    CODE_SIGN_STYLE: 'Manual',
    DEVELOPMENT_TEAM: 'TEAM123',
    PRODUCT_BUNDLE_IDENTIFIER: bundle,
    PROVISIONING_PROFILE_SPECIFIER: profile,
  };
}

function verify(buildSettings) {
  return spawnSync(
    'jq',
    [
      '-e',
      '--arg',
      'team',
      'TEAM123',
      '--argjson',
      'profiles',
      JSON.stringify(profiles),
      '-f',
      filter,
    ],
    {
      encoding: 'utf8',
      input: JSON.stringify(buildSettings),
    },
  );
}

test('signing verification accepts duplicate rows for the same target', () => {
  const app = settings('app.innei.lody', 'APP-UUID');
  const result = verify([
    { target: 'Lody', buildSettings: app },
    {
      target: 'LodyNotificationService',
      buildSettings: settings(
        'app.innei.lody.notification-service',
        'EXTENSION-UUID',
      ),
    },
    { target: 'Lody', buildSettings: app },
  ]);

  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.equal(result.stdout.trim(), 'true');
});

test('signing verification checks every duplicate target row', () => {
  const result = verify([
    {
      target: 'Lody',
      buildSettings: settings('app.innei.lody', 'APP-UUID'),
    },
    {
      target: 'Lody',
      buildSettings: settings('app.innei.lody', 'WRONG-UUID'),
    },
    {
      target: 'LodyNotificationService',
      buildSettings: settings(
        'app.innei.lody.notification-service',
        'EXTENSION-UUID',
      ),
    },
  ]);

  assert.equal(result.status, 1, `${result.stdout}\n${result.stderr}`);
  assert.equal(result.stdout.trim(), 'false');
});
