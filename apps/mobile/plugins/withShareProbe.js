const { withDangerousMod } = require('expo/config-plugins');
const fs = require('node:fs');
const path = require('node:path');

// Deliberately opt-in: this proves the extension transport before migrating UI.
module.exports = function withShareProbe(config) {
  return withDangerousMod(config, [
    'ios',
    (config) => {
      const podfile = path.join(
        config.modRequest.platformProjectRoot,
        'Podfile',
      );
      const marker = '# Lody share transport probe';
      let contents = fs.readFileSync(podfile, 'utf8');
      if (!contents.includes(marker)) {
        contents += `\n${marker}\nrequire_relative '../plugins/share-probe'\nlody_share_probe('${config.ios.bundleIdentifier}', enabled: ENV['LODY_SHARE_PROBE'] == '1')\n`;
        fs.writeFileSync(podfile, contents);
      }
      return config;
    },
  ]);
};
