const {
  IOSConfig,
  withAppDelegate,
  withDangerousMod,
  withInfoPlist,
  withXcodeProject,
} = require('expo/config-plugins');
const fs = require('fs');
const path = require('path');

const SCENE_DELEGATE = `internal import Expo

@objc(SceneDelegate)
class SceneDelegate: ExpoAppSceneDelegate {}
`;

const WINDOW_BLOCK =
  /#if os\(iOS\) \|\| os\(tvOS\)\n\s*window = UIWindow\(frame: UIScreen\.main\.bounds\)\n\s*factory\.startReactNative\(\n\s*withModuleName: "main",\n\s*in: window,\n\s*launchOptions: launchOptions\)\n#endif\n\n/;

const SHELL_SURFACE = `    LodyShellHost.surface = { [weak factory] module, props in
      guard let views = factory?.rootViewFactory as? ExpoReactRootViewFactory else { return UIView() }
      return views.superView(
        withModuleName: module,
        initialProperties: props,
        launchOptions: nil,
        bundleConfiguration: RCTBundleConfiguration.default(),
        devMenuConfiguration: nil
      )
    }
`;

const CONNECTING_METHOD = `
  public func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: "Default Configuration",
      sessionRole: connectingSceneSession.role
    )
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }
`;

module.exports = function withSceneLifecycle(config) {
  config = withInfoPlist(config, (config) => {
    config.modResults.UIApplicationSceneManifest = {
      UIApplicationSupportsMultipleScenes: false,
      UISceneConfigurations: {
        UIWindowSceneSessionRoleApplication: [
          {
            UISceneConfigurationName: 'Default Configuration',
            UISceneDelegateClassName: '$(PRODUCT_MODULE_NAME).SceneDelegate',
          },
        ],
      },
    };
    return config;
  });

  config = withDangerousMod(config, [
    'ios',
    (config) => {
      const file = path.join(
        config.modRequest.platformProjectRoot,
        config.modRequest.projectName,
        'SceneDelegate.swift',
      );
      fs.writeFileSync(file, SCENE_DELEGATE);
      return config;
    },
  ]);

  config = withXcodeProject(config, (config) => {
    const project = config.modResults;
    const groupName = config.modRequest.projectName;
    const filepath = `${groupName}/SceneDelegate.swift`;
    if (!project.hasFile(filepath)) {
      IOSConfig.XcodeUtils.addBuildSourceFileToGroup({
        filepath,
        groupName,
        project,
        verbose: false,
      });
    }
    return config;
  });

  config = withAppDelegate(config, (config) => {
    if (config.modResults.language !== 'swift') return config;
    let contents = config.modResults.contents;
    contents = contents.replace(WINDOW_BLOCK, '');
    if (!contents.includes('LodyShellHost.surface')) {
      contents = contents
        .replace(
          'import ReactAppDependencyProvider\n',
          'import ReactAppDependencyProvider\ninternal import LodyKit\n',
        )
        .replace(
          '    reactNativeFactory = factory\n',
          `    reactNativeFactory = factory\n${SHELL_SURFACE}`,
        );
    }
    if (!contents.includes('configurationForConnecting')) {
      contents = contents.replace(
        '    return super.application(application, didFinishLaunchingWithOptions: launchOptions)\n  }\n',
        `    return super.application(application, didFinishLaunchingWithOptions: launchOptions)\n  }\n${CONNECTING_METHOD}`,
      );
    }
    config.modResults.contents = contents;
    return config;
  });

  return config;
};
