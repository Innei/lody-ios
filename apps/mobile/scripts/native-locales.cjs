const fs = require('fs');
const path = require('path');
const {
  LOCALES,
  INFO_KEYS,
  isNativeKey,
  readCatalogs,
} = require('../plugins/locales');

const RESOURCES = ['Localizable.xcstrings', 'InfoPlist.xcstrings'];

function load(projectRoot) {
  const problems = [];
  const catalogs = readCatalogs(projectRoot, (message) =>
    problems.push(message),
  );
  if (problems.length)
    throw new Error(`Invalid locale catalogs:\n${problems.join('\n')}`);
  return catalogs;
}

/** Foundation selects the plural variation, so `{count}` becomes its substitution. */
function nativeStrings(catalogs) {
  const keys = Object.keys(catalogs.en).filter(isNativeKey);
  const strings = {};
  for (const key of keys) {
    if (key.endsWith('.other')) continue;
    if (key.endsWith('.one')) {
      const base = key.slice(0, -4);
      strings[base] = {
        extractionState: 'manual',
        localizations: Object.fromEntries(
          LOCALES.map((locale) => [
            locale,
            {
              variations: {
                plural: Object.fromEntries(
                  ['one', 'other'].map((category) => [
                    category,
                    {
                      stringUnit: {
                        state: 'translated',
                        value: catalogs[locale][`${base}.${category}`].replace(
                          '{count}',
                          '%lld',
                        ),
                      },
                    },
                  ]),
                ),
              },
            },
          ]),
        ),
      };
      continue;
    }
    strings[key] = {
      extractionState: 'manual',
      localizations: Object.fromEntries(
        LOCALES.map((locale) => [
          locale,
          { stringUnit: { state: 'translated', value: catalogs[locale][key] } },
        ]),
      ),
    };
  }
  return { sourceLanguage: 'en', strings, version: '1.0' };
}

/** Xcode compiles this into each language's InfoPlist.strings at build time. */
function infoStrings(catalogs) {
  const strings = Object.fromEntries(
    Object.entries(INFO_KEYS).map(([key, plistKey]) => [
      plistKey,
      {
        extractionState: 'manual',
        localizations: Object.fromEntries(
          LOCALES.map((locale) => [
            locale,
            {
              stringUnit: { state: 'translated', value: catalogs[locale][key] },
            },
          ]),
        ),
      },
    ]),
  );
  return { sourceLanguage: 'en', strings, version: '1.0' };
}

function writeResources(projectRoot, target) {
  const catalogs = load(projectRoot);
  for (const [name, contents] of [
    ['Localizable.xcstrings', nativeStrings(catalogs)],
    ['InfoPlist.xcstrings', infoStrings(catalogs)],
  ]) {
    const file = path.join(target, name);
    const next = `${JSON.stringify(contents, null, 2)}\n`;
    if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== next)
      fs.writeFileSync(file, next);
  }
}

module.exports = { writeResources, nativeStrings, infoStrings };
