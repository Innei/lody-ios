import type { ExpoConfig } from 'expo/config';

const config: ExpoConfig = {
  name: 'Lody',
  slug: 'lody-ios',
  version: '0.1.0',
  platforms: ['ios'],
  scheme: 'lody-ios',
  orientation: 'portrait',
  userInterfaceStyle: 'automatic',
  icon: './assets/icon.png',
  ios: {
    bundleIdentifier: 'app.innei.lody',
    supportsTablet: false,
    config: { usesNonExemptEncryption: false },
    infoPlist: {
      BGTaskSchedulerPermittedIdentifiers: ['app.innei.lody.session-sync.*'],
      UIBackgroundModes: ['processing'],
    },
  },
  plugins: [
    'expo-router',
    ['expo-dev-client', { toolsButton: false }],
    './plugins/withMarkdownView',
    './plugins/withLocales',
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
    enabled: true,
    fallbackToCacheTimeout: 0,
    requestHeaders: {
      'expo-channel-name': 'production',
      'expo-app-id': 'lody',
    },
  },
};

export default config;
