const path = require('node:path');
const { withBuildProperties } = require('expo-build-properties');

// Resolve on the build machine; never persist a developer's checkout path.
module.exports = function withAnchoredOverlay(config) {
  const packagePath = path.dirname(
    require.resolve('@rien7/anchored-overlay-kit/package.json'),
  );
  return withBuildProperties(config, {
    ios: {
      extraPods: [{ name: 'AnchoredOverlayKit', path: packagePath }],
    },
  });
};
