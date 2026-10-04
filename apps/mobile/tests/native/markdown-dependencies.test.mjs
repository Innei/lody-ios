import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import withMarkdownView from '../../plugins/withMarkdownView.js';

test('prebuild migrates fork declarations and remains idempotent', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lody-markdown-pods-'));
  const podfile = join(directory, 'Podfile');
  const base = "target 'Lody' do\n  use_expo_modules!\nend\n";
  const config = withMarkdownView({ name: 'Test', slug: 'test' });
  async function generate(source) {
    await writeFile(podfile, source);
    await config.mods.ios.dangerous({
      ...config,
      modRequest: { platformProjectRoot: directory },
    });
    return readFile(podfile, 'utf8');
  }
  try {
    const fresh = await generate(base);
    const legacy = base.replace(
      "target 'Lody' do\n",
      "target 'Lody' do\n" +
        '  spm_pkg "MarkdownView", :url => "https://github.com/Innei/MarkdownView.git", :branch => "lody/inject-text-label-view"\n',
    );
    assert.equal(await generate(legacy), fresh);
    const oldChatPackage = base.replace(
      "target 'Lody' do\n",
      "target 'Lody' do\n" +
        '  spm_pkg "NativeChatUI", :path => File.expand_path("../../../packages/native-chat-ui", __dir__)\n',
    );
    assert.equal(await generate(oldChatPackage), fresh);
    assert.equal(await generate(fresh), fresh);
    assert.ok(fresh.includes('  use_expo_modules!\nend\n'));
    assert.ok(!fresh.includes('github.com/Innei/'));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
