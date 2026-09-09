const {
  withInfoPlist,
  withEntitlementsPlist,
  withDangerousMod,
} = require('expo/config-plugins');
const fs = require('fs');
const path = require('path');

module.exports = function withPushNotifications(config, { appId = '' } = {}) {
  if (
    appId &&
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      appId,
    )
  ) {
    throw new Error('LODY_ONESIGNAL_APP_ID must be a OneSignal UUID');
  }
  config = withInfoPlist(config, (config) => {
    config.modResults.LodyOneSignalAppId = appId;
    config.modResults.OneSignal_app_groups_key = `group.${config.ios.bundleIdentifier}`;
    // Existing payloads also contain a Web URL. Let our click handler own navigation.
    config.modResults.OneSignal_suppress_launch_urls = true;
    config.modResults.NSSupportsLiveActivities = true;
    config.modResults.NSSupportsLiveActivitiesFrequentUpdates = false;
    config.modResults.UIBackgroundModes = [
      ...new Set([
        ...(config.modResults.UIBackgroundModes ?? []),
        'remote-notification',
      ]),
    ];
    return config;
  });
  config = withEntitlementsPlist(config, (config) => {
    config.modResults['aps-environment'] = 'development';
    const group = `group.${config.ios.bundleIdentifier}`;
    config.modResults['com.apple.security.application-groups'] = [
      ...new Set([
        ...(config.modResults['com.apple.security.application-groups'] ?? []),
        group,
      ]),
    ];
    return config;
  });
  return withDangerousMod(config, [
    'ios',
    (config) => {
      const root = config.modRequest.platformProjectRoot;
      const podfile = path.join(root, 'Podfile');
      const marker = '# Lody notification extension';
      let contents = fs.readFileSync(podfile, 'utf8');
      // Run before CocoaPods reads targets. The helper owns only the generated extensions.
      if (!contents.includes(marker)) {
        contents += `\n${marker}\nrequire_relative '../plugins/push-extension'\nlody_push_extension('${config.ios.bundleIdentifier}')\nlody_live_activity_extension('${config.ios.bundleIdentifier}')\ntarget 'LodyNotificationService' do\n  pod 'OneSignalXCFramework/OneSignal', '5.5.1'\nend\n`;
      }
      contents = contents.replace(
        /pod 'OneSignalXCFramework\/OneSignal(?:Extension)?', '[^']+'/g,
        "pod 'OneSignalXCFramework/OneSignal', '5.5.1'",
      );
      fs.writeFileSync(podfile, contents);
      return config;
    },
  ]);
};
