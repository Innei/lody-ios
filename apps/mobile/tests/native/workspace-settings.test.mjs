import { test } from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
test('native settings enforce authenticated ownership and confirm visibility by readback', () => {
  const directory = mkdtempSync(join(tmpdir(), 'lody-settings-check-'));
  try {
    const root = new URL('../../modules/lody-kit/', import.meta.url).pathname;
    execFileSync(
      'xcrun',
      [
        'swiftc',
        '-parse-as-library',
        root + 'ios/Cloud/WorkspaceSettingsCloud.swift',
        root + 'verification/settings/WorkspaceSettingsCheck.swift',
        '-o',
        join(directory, 'check'),
      ],
      { timeout: 120000, stdio: 'pipe' },
    );
    execFileSync(join(directory, 'check'), [], {
      timeout: 30000,
      stdio: 'pipe',
    });
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
