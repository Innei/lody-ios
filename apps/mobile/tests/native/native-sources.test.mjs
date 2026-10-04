import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const repoRoot = fileURLToPath(new URL('../../../../', import.meta.url));
const script = join(repoRoot, 'apps/mobile/scripts/check-native-sources.py');

function run(cwd, env = {}) {
  return spawnSync('python3', [script], {
    encoding: 'utf8',
    cwd,
    env: { ...process.env, ...env },
  });
}

async function write(path, contents = '') {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, contents);
}

test('passes when every first-party native source is linked in Pods', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lody-native-sources-'));
  try {
    await write(join(directory, 'pnpm-workspace.yaml'), 'packages: []\n');
    await write(
      join(directory, 'apps/mobile/modules/lody-kit/ios/Chat/Cell.swift'),
      'enum Cell {}\n',
    );
    await write(
      join(
        directory,
        'apps/mobile/modules/lody-kit/ios/Chat/Shaders/Particles.metal',
      ),
      '',
    );
    await write(
      join(directory, 'packages/dom-webview/ios/DomWebView.swift'),
      'enum Dom {}\n',
    );
    const pbxproj = join(
      directory,
      'apps/mobile/ios/Pods/Pods.xcodeproj/project.pbxproj',
    );
    await write(
      pbxproj,
      [
        '/* Cell.swift in Sources */',
        '/* Particles.metal in Resources */',
        '/* DomWebView.swift in Sources */',
        '',
      ].join('\n'),
    );
    const result = run(directory, { PROJECT_FILE_PATH: pbxproj });
    assert.equal(result.status, 0, result.stderr);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('fails when a new Swift file is not in the LodyKit compile sources', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lody-native-sources-'));
  try {
    await write(join(directory, 'pnpm-workspace.yaml'), 'packages: []\n');
    await write(
      join(directory, 'apps/mobile/modules/lody-kit/ios/Chat/Cell.swift'),
      'enum Cell {}\n',
    );
    await write(
      join(directory, 'apps/mobile/modules/lody-kit/ios/Chat/Gallery.swift'),
      'enum Gallery {}\n',
    );
    await write(
      join(directory, 'packages/dom-webview/ios/DomWebView.swift'),
      'enum Dom {}\n',
    );
    const pbxproj = join(
      directory,
      'apps/mobile/ios/Pods/Pods.xcodeproj/project.pbxproj',
    );
    await write(
      pbxproj,
      [
        '/* Cell.swift in Sources */',
        '/* DomWebView.swift in Sources */',
        '',
      ].join('\n'),
    );
    const result = run(directory, { PROJECT_FILE_PATH: pbxproj });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Gallery\.swift/);
    assert.match(result.stderr, /pnpm --filter @lody-ios\/mobile pods/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('skips when the generated Pods project is absent', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lody-native-sources-'));
  try {
    await write(join(directory, 'pnpm-workspace.yaml'), 'packages: []\n');
    await write(
      join(directory, 'apps/mobile/modules/lody-kit/ios/Chat/Cell.swift'),
      'enum Cell {}\n',
    );
    const result = run(directory);
    assert.equal(result.status, 0, result.stderr);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
