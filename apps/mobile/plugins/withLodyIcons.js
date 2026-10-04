const { IOSConfig, withXcodeProject } = require('@expo/config-plugins');

// Compile LodyKit's vectors with the app's asset catalog. A CocoaPods resource
// catalog would produce a second Assets.car; a resource bundle would hide the
// icons from the native toolbar button's UIImage(named:) lookup.
const CATALOGS = [
  '../modules/lody-kit/ios/Icons.xcassets',
  '../modules/lody-kit/ios/Colors.xcassets',
  '../modules/lody-kit/live-activity/AgentIcons.xcassets',
];

module.exports = (config) =>
  withXcodeProject(config, (config) => {
    const project = config.modResults;
    const configurations = project.pbxXCBuildConfigurationSection();
    for (const key of Object.keys(configurations)) {
      const settings = configurations[key].buildSettings;
      if (!settings) continue;
      if (
        !String(settings.ASSETCATALOG_COMPILER_APPICON_NAME || '').includes(
          'AppIcon',
        )
      ) {
        continue;
      }
      settings.ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = 'AccentColor';
      settings.ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = 'Aqua';
    }
    for (const filepath of CATALOGS) {
      if (!project.hasFile(filepath)) {
        IOSConfig.XcodeUtils.addResourceFileToGroup({
          filepath,
          groupName: config.modRequest.projectName,
          project,
          isBuildFile: true,
          verbose: false,
        });
      }
      for (const entry of Object.values(project.pbxFileReferenceSection())) {
        if (entry.path !== filepath && entry.path !== `"${filepath}"`) continue;
        entry.lastKnownFileType = 'folder.assetcatalog';
        entry.sourceTree = 'SOURCE_ROOT';
      }
    }
    const iconPath = '../assets/icons/Aqua.icon';
    if (!project.hasFile(iconPath)) {
      IOSConfig.XcodeUtils.addResourceFileToGroup({
        filepath: iconPath,
        groupName: config.modRequest.projectName,
        project,
        isBuildFile: true,
        verbose: false,
      });
    }
    for (const entry of Object.values(project.pbxFileReferenceSection())) {
      if (entry.path !== iconPath && entry.path !== `"${iconPath}"`) continue;
      entry.lastKnownFileType = 'folder.iconcomposer.icon';
      entry.sourceTree = 'SOURCE_ROOT';
    }
    return config;
  });
