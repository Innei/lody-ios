const { IOSConfig, withXcodeProject } = require('@expo/config-plugins');

// Compile LodyKit's vectors with the app's asset catalog. A CocoaPods resource
// catalog would produce a second Assets.car; a resource bundle would hide the
// icons from the native toolbar button's UIImage(named:) lookup.
module.exports = (config) =>
  withXcodeProject(config, (config) => {
    const project = config.modResults;
    const filepath = '../modules/lody-kit/ios/Icons.xcassets';
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
    return config;
  });
