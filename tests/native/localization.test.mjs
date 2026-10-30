import assert from 'node:assert/strict';
import { copyFile, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

test('String Catalog checks accept reordered arguments and reject broken translations and missing keys', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'lody-localization-'));
  const app = root;
  const kit = path.join(root, 'Shared/UIKit');
  const data = path.join(root, 'packages/LodyData/Sources');
  const entry = (en, zh = en) => ({
    localizations: Object.fromEntries(
      [
        ['en', en],
        ['zh-Hans', zh],
      ].map(([language, value]) => [
        language,
        { stringUnit: { state: 'translated', value } },
      ]),
    ),
  });
  const catalog = path.join(data, 'Resources/Localizable.xcstrings');
  const save = (file, strings) =>
    writeFile(
      file,
      JSON.stringify({ sourceLanguage: 'en', strings, version: '1.0' }),
    );
  const run = () =>
    spawnSync(process.execPath, [path.join(app, 'scripts/check-locales.mjs')], {
      encoding: 'utf8',
    });
  try {
    for (const directory of [
      path.join(app, 'scripts'),
      path.join(app, 'iOS'),
      path.join(app, 'Extensions'),
      path.dirname(catalog),
      kit,
    ]) {
      await mkdir(directory, { recursive: true });
    }
    await copyFile(
      new URL('../../scripts/check-locales.mjs', import.meta.url),
      path.join(app, 'scripts/check-locales.mjs'),
    );
    await save(
      path.join(app, 'iOS/InfoPlist.xcstrings'),
      Object.fromEntries(
        [
          'CFBundleDisplayName',
          'NSCameraUsageDescription',
          'NSLocalNetworkUsageDescription',
          'NSPhotoLibraryUsageDescription',
        ].map((key) => [key, entry('Prompt')]),
      ),
    );
    await writeFile(
      path.join(kit, 'Copy.swift'),
      'let title = String(localized: "summary", bundle: .lody)',
    );
    await save(catalog, {
      summary: entry('%1$@ / %2$@ (100%%)', '%2$@ / %1$@ (100%%)'),
    });
    let result = run();
    assert.equal(result.status, 0, result.stderr);

    await save(catalog, { summary: entry('%1$@', '%1$lld') });
    result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /incompatible format arguments/);

    const untranslated = entry('Hello');
    delete untranslated.localizations['zh-Hans'];
    await save(catalog, { summary: untranslated });
    result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /needs English and Simplified Chinese/);

    await save(catalog, {});
    result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /missing catalog key summary/);

    await writeFile(
      path.join(data, 'Status.swift'),
      'let status = String(localized: "status", bundle: .lodyData)',
    );
    await save(catalog, { summary: entry('Summary') });
    result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /missing catalog key status/);

    await save(catalog, { summary: entry('Summary'), status: entry('Status') });
    const mac = path.join(root, 'macOS');
    await mkdir(path.join(mac, 'Resources'), { recursive: true });
    await writeFile(
      path.join(mac, 'Menu.swift'),
      'let quit = String(localized: "mac.quit", bundle: .lodyMac)',
    );
    await save(path.join(mac, 'Resources/Localizable.xcstrings'), {});
    result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /missing catalog key mac\.quit/);

    await save(path.join(mac, 'Resources/Localizable.xcstrings'), {
      'mac.quit': entry('Quit'),
    });
    result = run();
    assert.equal(result.status, 0, result.stderr);
    for (const directory of [
      path.join(app, 'iOS/Features/Home'),
      path.join(app, 'Shared/UIKit/Composer'),
    ]) {
      await mkdir(directory, { recursive: true });
      const source = path.join(directory, 'Title.swift');
      await writeFile(
        source,
        'let title = String(localized: "missing.title", bundle: .lody)',
      );
      result = run();
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /missing catalog key missing\.title/);
      await rm(source);
    }
    for (const directory of ['iOS/Debug', 'iOS/ViewControllers/Debug']) {
      await mkdir(path.join(app, directory), { recursive: true });
      await writeFile(
        path.join(app, directory, 'Fixture.swift'),
        'let title = "调试场景"',
      );
      result = run();
      assert.equal(result.status, 0, result.stderr);
    }

    await writeFile(path.join(app, 'iOS/Page.swift'), 'let title = "页面"');
    result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Page\.swift:1: hardcoded copy/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
