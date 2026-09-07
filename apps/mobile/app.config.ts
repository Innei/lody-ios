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
      NSPhotoLibraryUsageDescription: '选择照片作为消息附件。',
    },
  },
  plugins: [
    'expo-router',
    ['expo-dev-client', { toolsButton: false }],
    './plugins/withMarkdownView',
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
