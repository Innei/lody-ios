// Regenerates `iOS/Resources/Licenses/LodyLicenses.json` and
// `macOS/Resources/LodyLicenses.json`, the data behind each app's open source
// licenses screen. Each app lists only the components it ships.
//
// The list is the production dependency closure of the app (every library that
// can end up in the shipped build), plus the native and vendored components that
// do not come from npm. Development dependencies are outside this closure.
//
//   node scripts/build-licenses.mjs           # rewrite the generated file
//   node scripts/build-licenses.mjs --check   # fail if the file is stale
//
// Re-run it whenever a dependency is added, removed, or upgraded.
import { existsSync, readFileSync, readdirSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { format } from 'prettier';

const root = fileURLToPath(new URL('../', import.meta.url));
const repo = root;
const check = process.argv.includes('--check');

/** Workspace packages whose production dependencies make up the app. */
const workspacePackages = ['.', 'packages/cloud-runtime'];

/**
 * Components that ship without a matching npm dependency: native Swift packages
 * and vendored icon sets.
 */
const nativeComponents = [
  {
    name: 'libdatachannel',
    license: 'MPL-2.0',
    url: 'https://github.com/paullouisageneau/libdatachannel',
    file: 'iOS/Resources/Licenses/libdatachannel-LICENSE.txt',
  },
  {
    name: 'libjuice',
    license: 'MPL-2.0',
    url: 'https://github.com/paullouisageneau/libjuice',
    file: 'iOS/Resources/Licenses/libjuice-LICENSE.txt',
  },
  {
    name: 'usrsctp',
    license: 'BSD-3-Clause',
    url: 'https://github.com/sctplab/usrsctp',
    file: 'iOS/Resources/Licenses/usrsctp-LICENSE.txt',
  },
  {
    name: 'Mbed TLS',
    license: 'Apache-2.0',
    url: 'https://github.com/Mbed-TLS/mbedtls',
    file: 'iOS/Resources/Licenses/MbedTLS-LICENSE.txt',
  },
  {
    name: 'plog',
    license: 'MIT',
    url: 'https://github.com/SergiusTheBest/plog',
    file: 'iOS/Resources/Licenses/plog-LICENSE.txt',
  },
  {
    name: 'Octicons',
    license: 'MIT',
    url: 'https://github.com/primer/octicons',
    file: 'iOS/Resources/Licenses/Octicons-LICENSE.txt',
  },
  {
    name: 'MarkdownView',
    license: 'MIT',
    url: 'https://github.com/Lakr233/MarkdownView',
    file: 'iOS/Resources/Licenses/MarkdownView-LICENSE.txt',
  },
  {
    name: 'Beautiful Mermaid Swift',
    license: 'MIT',
    url: 'https://github.com/lukilabs/beautiful-mermaid-swift',
    file: 'iOS/Resources/Licenses/BeautifulMermaid-LICENSE.txt',
  },
  {
    name: 'ElkSwift',
    license: 'EPL-2.0',
    url: 'https://github.com/lukilabs/elk-swift',
    file: 'iOS/Resources/Licenses/ElkSwift-LICENSE.txt',
  },
  {
    name: 'Lexical iOS',
    license: 'MIT',
    url: 'https://github.com/facebook/lexical-ios',
    file: 'iOS/Resources/Licenses/LexicalIOS-LICENSE.txt',
  },
  {
    name: 'Litext',
    license: 'MIT',
    url: 'https://github.com/Lakr233/Litext',
    file: 'iOS/Resources/Licenses/Litext-LICENSE.txt',
  },
  {
    name: 'Material Icon Theme',
    license: 'MIT',
    url: 'https://github.com/material-extensions/vscode-material-icon-theme',
    file: 'iOS/Resources/Licenses/MaterialIconTheme-LICENSE.txt',
  },
  {
    name: 'Lobe Icons',
    license: 'MIT',
    url: 'https://github.com/lobehub/lobe-icons',
    file: 'iOS/Resources/Licenses/LobeIcons-LICENSE.txt',
  },
];

/** Swift packages the Mac app links that the iOS list does not name. */
const macComponents = [
  ...nativeComponents.filter((component) =>
    ['MarkdownView', 'Litext'].includes(component.name),
  ),
  {
    name: 'DisplayLink',
    license: 'MIT',
    url: 'https://github.com/Lakr233/DisplayLink',
    file: 'scripts/licenses/DisplayLink-LICENSE.txt',
  },
  {
    name: 'LRUCache',
    license: 'MIT',
    url: 'https://github.com/nicklockwood/LRUCache',
    file: 'scripts/licenses/LRUCache-LICENSE.txt',
  },
  {
    name: 'swift-cmark',
    license: 'BSD-2-Clause',
    url: 'https://github.com/swiftlang/swift-cmark',
    file: 'scripts/licenses/swift-cmark-LICENSE.txt',
  },
  {
    name: 'Swift Collections',
    license: 'Apache-2.0',
    url: 'https://github.com/apple/swift-collections',
    file: 'scripts/licenses/swift-collections-LICENSE.txt',
  },
  {
    name: 'SwiftMath',
    license: 'MIT',
    url: 'https://github.com/mgriebling/SwiftMath',
    file: 'scripts/licenses/SwiftMath-LICENSE.txt',
  },
];

/** Each app's own license comes first, so its notices carry the AGPL text. */
const targets = [
  {
    output: 'iOS/Resources/Licenses/LodyLicenses.json',
    firstParty: {
      name: 'Lody for iOS',
      license: 'AGPL-3.0-only',
      url: 'https://github.com/Innei/lody-ios',
      file: 'LICENSE',
    },
    components: nativeComponents,
  },
  {
    output: 'macOS/Resources/LodyLicenses.json',
    firstParty: {
      name: 'Lody for Mac',
      license: 'AGPL-3.0-only',
      url: 'https://github.com/Innei/lody-ios',
      file: 'LICENSE',
      heading: 'Lody for Mac',
    },
    components: macComponents,
  },
];

/** License ids that npm publishes in inconsistent casing. */
const licenseCasing = new Map(
  Object.entries({
    '0bsd': '0BSD',
    'agpl-3.0-only': 'AGPL-3.0-only',
    'apache-2.0': 'Apache-2.0',
    'blueoak-1.0.0': 'BlueOak-1.0.0',
    'bsd-2-clause': 'BSD-2-Clause',
    'bsd-3-clause': 'BSD-3-Clause',
    'cc-by-4.0': 'CC-BY-4.0',
    'cc0-1.0': 'CC0-1.0',
    isc: 'ISC',
    mit: 'MIT',
    'mpl-2.0': 'MPL-2.0',
    'python-2.0': 'Python-2.0',
    unlicense: 'Unlicense',
  }),
);

const mitTemplate = `MIT License

Copyright (c) {holder}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.`;

function readJson(file) {
  return JSON.parse(readFileSync(file, 'utf8'));
}

/** Resolves `name` the way Node does, walking up `fromDir`'s node_modules. */
function resolvePackage(name, fromDir) {
  let dir = fromDir;
  for (;;) {
    const candidate = path.join(dir, 'node_modules', name);
    if (existsSync(path.join(candidate, 'package.json')))
      return realpathSync(candidate);
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

/** Production dependency closure of the workspace. */
function collectPackages() {
  const packages = new Map();
  const queue = [];
  for (const workspace of workspacePackages) {
    const dir = path.join(repo, workspace);
    const manifest = readJson(path.join(dir, 'package.json'));
    for (const name of Object.keys(manifest.dependencies ?? {})) {
      const resolved = resolvePackage(name, dir);
      if (resolved) queue.push([name, resolved]);
    }
  }
  while (queue.length) {
    const [name, dir] = queue.shift();
    if (packages.has(dir)) continue;
    let manifest;
    try {
      manifest = readJson(path.join(dir, 'package.json'));
    } catch {
      continue;
    }
    packages.set(dir, manifest);
    for (const dependency of Object.keys(manifest.dependencies ?? {})) {
      const resolved = resolvePackage(dependency, dir);
      if (resolved) queue.push([dependency, resolved]);
    }
  }
  return packages;
}

function readLicenseText(dir) {
  const files = readdirSync(dir)
    .filter((name) => /^(licen[cs]e|copying|notice)/i.test(name))
    .sort();
  for (const name of files) {
    try {
      const text = readFileSync(path.join(dir, name), 'utf8').trim();
      if (text) return text;
    } catch {
      // Unreadable notice files are skipped rather than failing the build.
    }
  }
  return '';
}

function licenseId(manifest) {
  const raw =
    typeof manifest.license === 'string'
      ? manifest.license
      : (manifest.license?.type ??
        manifest.licenses?.map((entry) => entry.type).join(' OR '));
  if (!raw) return 'UNKNOWN';
  return licenseCasing.get(raw.toLowerCase()) ?? raw;
}

function projectUrl(manifest) {
  const raw =
    typeof manifest.repository === 'string'
      ? manifest.repository
      : (manifest.repository?.url ?? manifest.homepage ?? '');
  return raw
    .replace(/^git\+/, '')
    .replace(/^git:\/\//, 'https://')
    .replace(/^github:/, 'https://github.com/')
    .replace(/\.git$/, '')
    .replace(/^http:\/\//, 'https://');
}

function holder(manifest) {
  const author =
    typeof manifest.author === 'string'
      ? manifest.author
      : manifest.author?.name;
  return author ?? `${manifest.name} contributors`;
}

function canonicalText(manifest, id) {
  if (id === 'MIT') return mitTemplate.replace('{holder}', holder(manifest));
  return '';
}

/** The repository LICENSE opens with the iOS app's name; each app shows its own. */
function retitle(text, heading) {
  if (!heading) return text;
  const [, ...rest] = text.split('\n');
  return [heading, ...rest].join('\n');
}

function buildEntries({ firstParty, components }) {
  const entries = [];
  for (const [dir, manifest] of collectPackages()) {
    const id = licenseId(manifest);
    let text = readLicenseText(dir);
    if (!text) text = canonicalText(manifest, id);
    if (!text) {
      throw new Error(
        `${manifest.name}@${manifest.version} declares ${id} but ships no license text. ` +
          `Add its text to nativeComponents or a canonical template to the script.`,
      );
    }
    entries.push({
      name: manifest.name,
      version: manifest.version,
      license: id,
      url: projectUrl(manifest),
      text,
    });
  }
  for (const component of [firstParty, ...components]) {
    entries.push({
      name: component.name,
      version: '',
      license: component.license,
      url: component.url,
      firstParty: component === firstParty,
      text: retitle(
        readFileSync(path.join(root, component.file), 'utf8').trim(),
        component.heading,
      ),
    });
  }
  // The same package can be installed more than once (workspace links, nested
  // copies); one notice per name and version is enough. Sorted first so the
  // winner does not depend on node_modules traversal order.
  const unique = new Map();
  for (const entry of [...entries].sort((left, right) => {
    const byName = left.name.localeCompare(right.name, 'en');
    return byName !== 0
      ? byName
      : left.version.localeCompare(right.version, 'en');
  })) {
    const key = `${entry.name}@${entry.version}`;
    const seen = unique.get(key);
    if (!seen || entry.text.length > seen.text.length) unique.set(key, entry);
  }
  const merged = [...unique.values()];
  merged.sort((left, right) => left.name.localeCompare(right.name, 'en'));
  const counts = new Map();
  for (const entry of merged)
    counts.set(entry.name, (counts.get(entry.name) ?? 0) + 1);
  const texts = [];
  const textIndex = new Map();
  const packages = merged.map((entry) => {
    if (!textIndex.has(entry.text)) {
      textIndex.set(entry.text, texts.length);
      texts.push(entry.text);
    }
    const name =
      counts.get(entry.name) > 1
        ? `${entry.name}@${entry.version}`
        : entry.name;
    return {
      name,
      ...(entry.version ? { version: entry.version } : {}),
      license: entry.license,
      ...(entry.url ? { url: entry.url } : {}),
      ...(entry.firstParty ? { firstParty: true } : {}),
      text: textIndex.get(entry.text),
    };
  });
  const display = new Set(packages.map((entry) => entry.name));
  if (display.size !== packages.length)
    throw new Error('Duplicate display names in the generated license list');
  return { packages, texts };
}

async function render(target) {
  const config = readJson(path.join(repo, '.prettierrc.json'));
  return format(JSON.stringify(buildEntries(target)), {
    ...config,
    filepath: path.join(root, target.output),
  });
}

let stale = false;
for (const target of targets) {
  const output = path.join(root, target.output);
  const rendered = await render(target);
  const existing = existsSync(output) ? readFileSync(output, 'utf8') : '';
  if (check) {
    if (rendered !== existing) {
      console.error(`${target.output} is stale. Run: pnpm licenses:build`);
      stale = true;
    } else {
      console.log(`${target.output} is up to date`);
    }
  } else if (rendered !== existing) {
    const { mkdir, writeFile } = await import('node:fs/promises');
    await mkdir(path.dirname(output), { recursive: true });
    await writeFile(output, rendered);
    const size = (Buffer.byteLength(rendered) / 1024).toFixed(0);
    console.log(`Wrote ${target.output} (${size} KB)`);
  } else {
    console.log(`${target.output} unchanged`);
  }
}
if (stale) process.exit(1);
