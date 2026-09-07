const fs = require('fs');
const path = require('path');

const LOCALES = ['zh-Hans', 'en'];
const PLACEHOLDER = /\{([A-Za-z][A-Za-z0-9_]*)\}/g;
const INFO_KEYS = {
  'ios.info.bundleDisplayName': 'CFBundleDisplayName',
  'ios.info.photoLibraryUsage': 'NSPhotoLibraryUsageDescription',
};

function localesDir(projectRoot) {
  return path.join(projectRoot, 'locales');
}

function placeholders(template) {
  return Array.from(template.matchAll(PLACEHOLDER), (m) => m[1])
    .sort()
    .join(',');
}

function readCatalogs(projectRoot, fail) {
  const catalogs = {};
  for (const locale of LOCALES) {
    const file = path.join(localesDir(projectRoot), `${locale}.json`);
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    for (const [key, value] of Object.entries(parsed)) {
      if (typeof value !== 'string')
        fail(`${locale}.json: ${key} is not a string`);
    }
    catalogs[locale] = parsed;
  }

  const [reference, ...rest] = LOCALES;
  const keys = Object.keys(catalogs[reference]);
  for (const locale of rest) {
    for (const key of keys)
      if (!(key in catalogs[locale])) fail(`${locale}.json: missing ${key}`);
    for (const key of Object.keys(catalogs[locale]))
      if (!(key in catalogs[reference]))
        fail(`${reference}.json: missing ${key}`);
  }

  for (const key of keys) {
    const expected = placeholders(catalogs[reference][key]);
    for (const locale of rest) {
      const actual = placeholders(catalogs[locale][key] ?? '');
      if (actual !== expected)
        fail(
          `${key}: placeholders differ (${reference}=${expected || 'none'}, ${locale}=${actual || 'none'})`,
        );
    }
  }

  for (const key of keys) {
    if (!key.endsWith('.one')) continue;
    const other = `${key.slice(0, -4)}.other`;
    for (const locale of LOCALES)
      if (!(other in catalogs[locale]))
        fail(`${locale}.json: missing ${other}`);
  }
  for (const key of keys) {
    if (!key.endsWith('.other')) continue;
    const one = `${key.slice(0, -6)}.one`;
    for (const locale of LOCALES)
      if (!(one in catalogs[locale])) fail(`${locale}.json: missing ${one}`);
  }

  for (const key of Object.keys(INFO_KEYS))
    if (!keys.includes(key)) fail(`missing required key ${key}`);

  return catalogs;
}

module.exports = { LOCALES, INFO_KEYS, PLACEHOLDER, readCatalogs, localesDir };
