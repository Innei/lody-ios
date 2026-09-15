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
import React

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else {
      return
    }
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
      let factory = appDelegate.reactNativeFactory
    else {
      return
    }

    let window = UIWindow(windowScene: windowScene)
    self.window = window
    appDelegate.window = window
    factory.startReactNative(withModuleName: "main", in: window, launchOptions: nil)
  }
}
`;

const WINDOW_BLOCK =
  /#if os\(iOS\) \|\| os\(tvOS\)\n\s*window = UIWindow\(frame: UIScreen\.main\.bounds\)\n\s*factory\.startReactNative\(\n\s*withModuleName: "main",\n\s*in: window,\n\s*launchOptions: launchOptions\)\n#endif\n\n/;

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
