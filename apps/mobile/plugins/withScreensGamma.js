const { withPodfile } = require('expo/config-plugins');

// ScrollViewMarker and the other Fabric-only react-native-screens views compile
// only with this flag.
module.exports = function withScreensGamma(config) {
  return withPodfile(config, (config) => {
    if (!config.modResults.contents.includes('RNS_GAMMA_ENABLED')) {
      config.modResults.contents = `ENV['RNS_GAMMA_ENABLED'] ||= '1'\n${config.modResults.contents}`;
    }
    return config;
  });
};
