import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import withMarkdownView from '../../plugins/withMarkdownView.js';

test('prebuild replaces stale Markdown and Litext declarations idempotently', async () => {
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
    assert.match(
      fresh,
      /spm_pkg "Litext", :url => "https:\/\/github.com\/Lakr233\/Litext.git", :version => "3.6.2"/,
    );
    assert.doesNotMatch(fresh, /Innei\/Litext/);
    const legacy = base.replace(
      "target 'Lody' do\n",
      "target 'Lody' do\n" +
        '  spm_pkg "MarkdownView", :url => "https://github.com/Innei/MarkdownView.git", :branch => "lody/inject-text-label-view"\n' +
        '  spm_pkg "Litext", :url => "https://github.com/Innei/Litext.git", :commit => "f7b6322051d8f9308cf63f5f5adb3c80549a6dd0"\n' +
        '  spm_pkg "Litext", :url => "https://github.com/Lakr233/Litext", :version => "3.3.2"\n' +
        '  spm_pkg "Litext", :path => File.expand_path("../../../packages/litext", __dir__)\n',
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
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
