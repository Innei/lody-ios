const {
  withDangerousMod,
  withEntitlementsPlist,
  withInfoPlist,
} = require('expo/config-plugins');
const fs = require('fs');
const path = require('path');

module.exports = function withShareExtension(config) {
  const accessGroup = `$(AppIdentifierPrefix)${config.ios.bundleIdentifier}`;
  config = withEntitlementsPlist(config, (config) => {
    config.modResults['keychain-access-groups'] = [
      ...new Set([
        ...(config.modResults['keychain-access-groups'] ?? []),
        accessGroup,
      ]),
    ];
    config.modResults['com.apple.security.application-groups'] = [
      ...new Set([
        ...(config.modResults['com.apple.security.application-groups'] ?? []),
        `group.${config.ios.bundleIdentifier}`,
      ]),
    ];
    return config;
  });
  config = withInfoPlist(config, (config) => {
    config.modResults.LodyAuthAccessGroup = accessGroup;
    return config;
  });
  return withDangerousMod(config, [
    'ios',
    (config) => {
      const podfile = path.join(
        config.modRequest.platformProjectRoot,
        'Podfile',
      );
      const marker = '# Lody share extension';
      const contents = fs.readFileSync(podfile, 'utf8');
      if (!contents.includes(marker)) {
        fs.writeFileSync(
          podfile,
          `${contents}\n${marker}\nrequire_relative '../plugins/share-extension'\nlody_share_extension('${config.ios.bundleIdentifier}')\n`,
        );
      }
      return config;
    },
  ]);
};
