import type { ExpoConfig } from 'expo/config';

const fixtureBuild = process.env.EXPO_PUBLIC_UI_VERIFY === '1';

const config: ExpoConfig = {
  name: 'Lody',
  slug: 'lody-ios',
  version: '0.2.0',
  platforms: ['ios'],
  scheme: 'lody',
  orientation: 'portrait',
  userInterfaceStyle: 'automatic',
  icon: './assets/icon.png',
  ios: {
    deploymentTarget: '26.0',
    bundleIdentifier: 'app.innei.lody',
    appleTeamId: 'KAMM5N88X3',
    supportsTablet: true,
    config: { usesNonExemptEncryption: false },
    infoPlist: {
      // Clear the old continued-processing declarations on incremental prebuilds.
      BGTaskSchedulerPermittedIdentifiers: [],
      UIBackgroundModes: [],
      UIApplicationSceneManifest: {
        UIApplicationSupportsMultipleScenes: false,
        UISceneConfigurations: {
          UIWindowSceneSessionRoleApplication: [
            {
              UISceneConfigurationName: 'Default Configuration',
              UISceneDelegateClassName: '$(PRODUCT_MODULE_NAME).SceneDelegate',
            },
          ],
        },
      },
    },
  },
  plugins: [
    'expo-router',
    ['expo-dev-client', { toolsButton: false }],
    './plugins/withSceneLifecycle',
    './plugins/withMarkdownView',
    './plugins/withLocales',
    './plugins/withLodyIcons',
    './plugins/withShareProbe',
    'expo-localization',
    [
      './plugins/withPushNotifications',
      {
        appId:
          process.env.LODY_ONESIGNAL_APP_ID ??
          'e383bf31-7c8e-4641-b3f6-3486e77b9a82',
      },
    ],
  ],
  experiments: { typedRoutes: true, reactCompiler: true },
  runtimeVersion: { policy: 'fingerprint' },
  updates: {
    url: 'https://ota.innei.in/manifest',
    enabled: !fixtureBuild,
    fallbackToCacheTimeout: 0,
    requestHeaders: {
      'expo-channel-name': 'production',
      'expo-app-id': 'lody',
    },
  },
};

export default config;
