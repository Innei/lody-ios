const fs = require('fs');
const path = require('path');
const {
  IOSConfig,
  withDangerousMod,
  withInfoPlist,
  withXcodeProject,
} = require('expo/config-plugins');
const { LOCALES, INFO_KEYS, readCatalogs } = require('./locales');

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
  const keys = Object.keys(catalogs.en).filter((key) =>
    key.startsWith('native.'),
  );
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

const withGeneratedResources = (config) =>
  withDangerousMod(config, [
    'ios',
    (config) => {
      const catalogs = load(config.modRequest.projectRoot);
      const target = path.join(
        config.modRequest.platformProjectRoot,
        config.modRequest.projectName,
      );
      fs.writeFileSync(
        path.join(target, 'Localizable.xcstrings'),
        `${JSON.stringify(nativeStrings(catalogs), null, 2)}\n`,
      );
      fs.writeFileSync(
        path.join(target, 'InfoPlist.xcstrings'),
        `${JSON.stringify(infoStrings(catalogs), null, 2)}\n`,
      );
      return config;
    },
  ]);

const withResourcesLinked = (config) =>
  withXcodeProject(config, (config) => {
    const project = config.modResults;
    const group = config.modRequest.projectName;
    for (const resource of RESOURCES) {
      const filepath = `${group}/${resource}`;
      if (project.hasFile(filepath)) continue;
      IOSConfig.XcodeUtils.addResourceFileToGroup({
        filepath,
        groupName: group,
        project,
        isBuildFile: true,
        verbose: false,
      });
      // Without an explicit type Xcode copies the catalog instead of compiling it.
      for (const entry of Object.values(project.pbxFileReferenceSection()))
        if (entry.path === `"${filepath}"` || entry.path === filepath)
          entry.lastKnownFileType = '"text.json.xcstrings"';
    }
    return config;
  });

const withLocalizedInfoPlist = (config) =>
  withInfoPlist(config, (config) => {
    const catalogs = load(config.modRequest.projectRoot);
    config.modResults.CFBundleLocalizations = LOCALES;
    config.modResults.CFBundleDevelopmentRegion = 'en';
    for (const [key, plistKey] of Object.entries(INFO_KEYS))
      config.modResults[plistKey] = catalogs.en[key];
    return config;
  });

module.exports = (config) =>
  withResourcesLinked(withGeneratedResources(withLocalizedInfoPlist(config)));
