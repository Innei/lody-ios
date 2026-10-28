import assert from 'node:assert/strict';
import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const repoRoot = fileURLToPath(new URL('../../../../', import.meta.url));
const buildModeGuard = join(
  repoRoot,
  '.github/scripts/verify-ios-build-mode.sh',
);
const linkageGuard = join(
  repoRoot,
  '.github/scripts/verify-apple-bundle-linkage.sh',
);

function runGuard(script, args, env = {}) {
  return spawnSync('/bin/bash', [script, ...args], {
    encoding: 'utf8',
    env: { ...process.env, ...env },
  });
}

async function touch(path, contents = '') {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, contents);
}

test('native builds reject any React Native, Expo, or Hermes pod', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lody-build-mode-'));
  const iosDirectory = join(directory, 'ios');
  try {
    await mkdir(join(iosDirectory, 'Pods'), { recursive: true });
    assert.equal(runGuard(buildModeGuard, [iosDirectory]).status, 0);
    for (const name of ['React-Core', 'ExpoModulesCore', 'hermes-engine']) {
      await mkdir(join(iosDirectory, 'Pods', name));
      assert.notEqual(runGuard(buildModeGuard, [iosDirectory]).status, 0, name);
      await rm(join(iosDirectory, 'Pods', name), { recursive: true });
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('rejects an app whose framework dependency is not embedded', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lody-linkage-'));
  const app = join(directory, 'Lody.app');
  const tools = join(directory, 'tools');
  const fileTool = join(tools, 'file');
  const otool = join(tools, 'otool');
  try {
    await touch(join(app, 'Lody'));
    await touch(
      join(app, 'Frameworks/ExpoModulesWorklets.framework/ExpoModulesWorklets'),
    );
    await touch(
      fileTool,
      '#!/bin/bash\nprintf "Mach-O 64-bit dynamically linked shared library arm64\\n"\n',
    );
    await touch(
      otool,
      `#!/bin/bash
binary="$2"
printf '%s:\\n' "$binary"
case "$binary" in
  */ExpoModulesWorklets)
    printf '\\t@rpath/ExpoModulesWorklets.framework/ExpoModulesWorklets (compatibility version 1.0.0, current version 1.0.0)\\n'
    printf '\\t@rpath/React.framework/React (compatibility version 1.0.0, current version 1.0.0)\\n'
    printf '\\t@rpath/libswiftCore.dylib (compatibility version 1.0.0, current version 1.0.0)\\n'
    ;;
esac
`,
    );
    await chmod(fileTool, 0o755);
    await chmod(otool, 0o755);

    const missing = runGuard(linkageGuard, [app], {
      FILE_BIN: fileTool,
      OTOOL_BIN: otool,
    });
    assert.notEqual(missing.status, 0);
    assert.match(
      `${missing.stdout}${missing.stderr}`,
      /React\.framework\/React/,
    );

    await touch(join(app, 'Frameworks/React.framework/React'));
    const complete = runGuard(linkageGuard, [app], {
      FILE_BIN: fileTool,
      OTOOL_BIN: otool,
    });
    assert.equal(complete.status, 0, complete.stderr);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('release checks the build mode and exported IPA before upload', async () => {
  const workflow = await readFile(
    join(repoRoot, '.github/workflows/release.yml'),
    'utf8',
  );

  const podInstall = workflow.indexOf('bundle exec pod install');
  const buildModeCheck = workflow.indexOf('verify-ios-build-mode.sh');
  const exportIpa = workflow.indexOf('- name: Export IPA');
  const linkageCheck = workflow.indexOf('verify-apple-bundle-linkage.sh');
  const upload = workflow.indexOf('- name: Upload to TestFlight');

  assert.ok(podInstall >= 0);
  assert.ok(buildModeCheck > podInstall);
  assert.ok(exportIpa > buildModeCheck);
  assert.ok(linkageCheck > exportIpa);
  assert.ok(upload > linkageCheck);
});
