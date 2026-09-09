// Regenerates `src/features/licenses/licenses.generated.ts`, the data behind
// Settings -> Open Source Licenses.
//
// The list is the production dependency closure of the app (every library that
// can end up in the shipped build), plus the native and vendored components that
// do not come from npm. Build-only tooling (Metro, the Expo CLI, the Babel
// transform pipeline, React Native codegen) is pruned because it is never part
// of the distributed app.
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
const repo = path.resolve(root, '../..');
const output = path.join(root, 'src/features/licenses/licenses.generated.ts');
const check = process.argv.includes('--check');

/** Workspace packages whose production dependencies make up the app. */
const workspacePackages = ['apps/mobile', 'packages/dom-webview'];

/**
 * Build-only dependencies. These run while bundling or compiling the app and
 * never reach the device, so they are not distributed and need no notice.
 */
const buildTooling = [
  // Metro bundler, Expo CLI and project generation.
  /^metro$/,
  /^metro-.*/,
  /^@expo\/cli$/,
  /^@expo\/metro$/,
  /^@expo\/metro-config$/,
  /^@expo\/devtools$/,
  /^@expo\/fingerprint$/,
  /^@expo\/local-build-cache-provider$/,
  /^@expo\/package-manager$/,
  /^@expo\/image-utils$/,
  /^@expo\/spawn-async$/,
  /^@expo\/xcpretty$/,
  /^@expo\/json-file$/,
  /^@expo\/osascript$/,
  /^@expo\/plist$/,
  /^@expo\/prebuild-config$/,
  /^@expo\/env$/,
  /^@expo\/scheme$/,
  /^@expo\/xml$/,
  /^@expo\/config$/,
  /^@expo\/config-plugins$/,
  /^@expo\/config-types$/,
  /^@expo\/code-signing-certificates$/,
  /^@expo\/expo-modules-macros-plugin$/,
  /^@expo\/expo-modules-autolinking$/,
  /^expo-modules-autolinking$/,
  // Babel transform pipeline and the browser-target data it uses.
  /^babel-preset-expo$/,
  /^babel-plugin-syntax-hermes-parser$/,
  /^@babel\/(core|parser|generator|traverse|template|types|code-frame|compat-data)$/,
  /^@babel\/helper-.*/,
  /^@babel\/plugin-.*/,
  /^@babel\/preset-.*/,
  /^browserslist$/,
  /^caniuse-lite$/,
  /^electron-to-chromium$/,
  /^node-releases$/,
  /^update-browserslist-db$/,
  /^baseline-browser-mapping$/,
  /^regenerate$/,
  /^regenerate-unicode-properties$/,
  /^regexpu-core$/,
  /^regjsgen$/,
  /^regjsparser$/,
  /^unicode-.*-ecmascript$/,
  // React Native codegen, Gradle, template and dev-server tooling.
  /^@react-native\/(codegen|gradle-plugin|community-cli-plugin|dev-middleware|metro-config|typescript-utils)$/,
  /^@react-native\/babel-plugin.*/,
  /^@react-native\/template.*/,
  /^react-devtools-core$/,
  /^react-refresh$/,
  /^hermes-(compiler|parser|estree)$/,
  // Dev and test helpers.
  /^jest.*$/,
  /^@jest\/.*/,
  /^pretty-format$/,
];

/**
 * Components that ship without a matching npm dependency: native Swift packages,
 * the vendored icon set, and a CocoaPod pulled in by an Expo module.
 */
const nativeComponents = [
  {
    name: 'MarkdownView',
    license: 'MIT',
    url: 'https://github.com/Innei/MarkdownView',
    file: 'modules/lody-kit/licenses/MarkdownView-LICENSE.txt',
  },
  {
    name: 'Litext',
    license: 'MIT',
    url: 'https://github.com/Lakr233/Litext',
    file: 'modules/lody-kit/licenses/Litext-LICENSE.txt',
  },
  {
    name: 'Material Icon Theme',
    license: 'MIT',
    url: 'https://github.com/material-extensions/vscode-material-icon-theme',
    file: 'modules/lody-kit/licenses/MaterialIconTheme-LICENSE.txt',
  },
  {
    name: 'ReachabilitySwift',
    license: 'MIT',
    url: 'https://github.com/ashleymills/Reachability.swift',
    file: 'modules/lody-kit/licenses/ReachabilitySwift-LICENSE.txt',
  },
];

/** Npm packages linked natively but not reachable from the declared graph. */
const nativeOnlyPackages = ['react-native-gesture-handler'];

/** The app's own license, so the notices screen also carries the AGPL text. */
const firstPartyLicense = {
  name: 'Lody for iOS',
  license: 'AGPL-3.0-only',
  url: 'https://github.com/Innei/lody-ios',
  file: '../../LICENSE',
};

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

/** Production dependency closure of the workspace, minus build-only tooling. */
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
    if (packages.has(dir) || buildTooling.some((rule) => rule.test(name)))
      continue;
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
  for (const name of nativeOnlyPackages) {
    const resolved = resolvePackage(name, path.join(repo, 'apps/mobile'));
    if (resolved && !packages.has(resolved))
      packages.set(resolved, readJson(path.join(resolved, 'package.json')));
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

function buildEntries() {
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
  for (const component of [firstPartyLicense, ...nativeComponents]) {
    entries.push({
      name: component.name,
      version: '',
      license: component.license,
      url: component.url,
      firstParty: component === firstPartyLicense,
      text: readFileSync(path.join(root, component.file), 'utf8').trim(),
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

async function render() {
  const data = buildEntries();
  const source = `// Generated by scripts/build-licenses.mjs. Do not edit by hand.
// Regenerate after dependency changes:
//   pnpm --filter @lody-ios/mobile licenses:build
export type BundledLicense = {
  name: string;
  version?: string;
  license: string;
  url?: string;
  /** True for the app's own license entry. */
  firstParty?: boolean;
  /** Index into \`texts\`. */
  text: number;
};

export type LicensesData = {
  packages: BundledLicense[];
  texts: string[];
};

export const bundledLicenses: LicensesData = ${JSON.stringify(data, null, 2)};
`;
  const config = readJson(path.join(repo, '.prettierrc.json'));
  return format(source, { ...config, filepath: output });
}

const rendered = await render();
const existing = existsSync(output) ? readFileSync(output, 'utf8') : '';
if (check) {
  if (rendered !== existing) {
    console.error(
      'licenses.generated.ts is stale. Run: pnpm --filter @lody-ios/mobile licenses:build',
    );
    process.exit(1);
  }
  console.log('licenses.generated.ts is up to date');
} else if (rendered !== existing) {
  const { mkdir, writeFile } = await import('node:fs/promises');
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, rendered);
  const size = (Buffer.byteLength(rendered) / 1024).toFixed(0);
  console.log(`Wrote ${path.relative(repo, output)} (${size} KB)`);
} else {
  console.log('licenses.generated.ts unchanged');
}
