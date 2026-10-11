require 'xcodeproj'
require 'fileutils'

# Persist this recipe, never hand-edit the generated application or Pods project.
mobile = File.expand_path('../../..', __dir__)
require File.join(mobile, 'plugins/push-extension')
lody_live_activity_extension('app.innei.lody')
project = Xcodeproj::Project.open(File.join(mobile, 'ios/Lody.xcodeproj'))
name = 'LodyActivityVerify'
target = project.targets.find { |t| t.name == name } || project.new_target(:application, name, :ios, '26.0')
widget = project.targets.find { |t| t.name == 'LodyLiveActivity' }
source = File.join(mobile, 'modules/lody-kit/live-activity')
files = [File.join(__dir__, 'App.swift')] + %w[LodyActivityAttributes.swift LiveActivityCatalog.swift LiveActivityViews.swift SmallActivityView.swift LiveActivityFixtures.swift].map { |f| File.join(source, f) }
group = project.main_group.find_subpath('ActivityVerify', true)
target.source_build_phase.files.to_a.each(&:remove_from_project)
files.each do |path|
  ref = group.files.find { |f| f.real_path.to_s == path } || group.new_file(path)
  target.source_build_phase.add_file_reference(ref, true)
end
assets = File.join(source, 'AgentIcons.xcassets')
ref = group.files.find { |f| f.real_path.to_s == assets } || group.new_file(assets)
target.resources_build_phase.files.to_a.each(&:remove_from_project)
target.resources_build_phase.add_file_reference(ref, true)
folder = File.join(mobile, 'ios', name)
FileUtils.mkdir_p(folder)
Xcodeproj::Plist.write_to_path({
  'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
  'CFBundleName' => 'Lody Verify', 'CFBundleVersion' => '1', 'CFBundleShortVersionString' => '0.2.0',
  'CFBundlePackageType' => 'APPL', 'NSSupportsLiveActivities' => true,
  'UILaunchScreen' => {}, 'UIApplicationSceneManifest' => { 'UIApplicationSupportsMultipleScenes' => false },
  'CFBundleURLTypes' => [{ 'CFBundleURLSchemes' => ['lodyverify', 'lody'] }]
}, File.join(folder, 'Info.plist'))
target.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    'PRODUCT_NAME' => '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER' => 'app.innei.lody', 'INFOPLIST_FILE' => "#{name}/Info.plist",
    'GENERATE_INFOPLIST_FILE' => 'NO', 'ASSETCATALOG_COMPILER_APPICON_NAME' => '', 'SWIFT_VERSION' => '6.0', 'IPHONEOS_DEPLOYMENT_TARGET' => '26.0',
    'TARGETED_DEVICE_FAMILY' => '1', 'CODE_SIGN_STYLE' => 'Automatic',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DEBUG', 'SWIFT_OPTIMIZATION_LEVEL' => '-Onone'
  })
end
target.add_dependency(widget) unless target.dependencies.any? { |d| d.target == widget }
phase = target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' } || target.new_copy_files_build_phase('Embed App Extensions')
phase.dst_subfolder_spec = '13'
phase.add_file_reference(widget.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(target, nil)
scheme.save_as(project.path, name, true)
workspace = File.join(mobile, 'ios/Lody.xcworkspace')
unless File.exist?(workspace)
  Xcodeproj::Workspace.new_from_xcworkspace(File.join(project.path, 'project.xcworkspace')).tap do |w|
    w << Xcodeproj::Workspace::FileReference.new('Lody.xcodeproj')
    w.save_as(workspace)
  end
end

watch_name = 'LodySmallActivityVerify'
watch = project.targets.find { |t| t.name == watch_name } || project.new_target(:application, watch_name, :watchos, '26.0')
watch.source_build_phase.files.to_a.each(&:remove_from_project)
watch_files = [File.join(__dir__, 'WatchApp.swift')] + files.drop(1)
watch_files.each do |path|
  ref = group.files.find { |f| f.real_path.to_s == path } || group.new_file(path)
  watch.source_build_phase.add_file_reference(ref, true)
end
watch.resources_build_phase.files.to_a.each(&:remove_from_project)
watch.resources_build_phase.add_file_reference(group.files.find { |f| f.real_path.to_s == assets }, true)
watch_folder = File.join(mobile, 'ios', watch_name)
FileUtils.mkdir_p(watch_folder)
Xcodeproj::Plist.write_to_path({
  'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
  'CFBundleName' => 'Small Activity Verify', 'CFBundleVersion' => '1', 'CFBundleShortVersionString' => '0.2.0',
  'CFBundlePackageType' => 'APPL', 'WKApplication' => true, 'WKWatchOnly' => true
}, File.join(watch_folder, 'Info.plist'))
watch.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    'PRODUCT_NAME' => '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER' => 'app.innei.lody.small-activity-verify',
    'INFOPLIST_FILE' => "#{watch_name}/Info.plist", 'GENERATE_INFOPLIST_FILE' => 'NO',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => '', 'SWIFT_VERSION' => '6.0',
    'WATCHOS_DEPLOYMENT_TARGET' => '26.0', 'TARGETED_DEVICE_FAMILY' => '4',
    'CODE_SIGN_STYLE' => 'Automatic', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DEBUG',
    'SWIFT_OPTIMIZATION_LEVEL' => '-Onone'
  })
end
project.save
watch_scheme = Xcodeproj::XCScheme.new
watch_scheme.configure_with_targets(watch, nil)
watch_scheme.save_as(project.path, watch_name, true)
