require 'xcodeproj'
require 'fileutils'

# cocoapods-spm reopens Pod::Project in post_integrate. Its sequential UUID
# allocator otherwise starts over and can overwrite the existing PBXProject.
module LodyUniquePodUUIDs
  def generate_uuid
    loop do
      uuid = super
      return uuid unless objects_by_uuid.key?(uuid)
    end
  end
end
Pod::Project.prepend(LodyUniquePodUUIDs) if defined?(Pod::Project)

# All output lives in generated ios/. Safe to repeat after Expo prebuild.
def lody_extension(bundle_id, name:, suffix:, source_dir:, point_identifier:, display_name:, swift_version:, principal_class: nil, extra_plist: {})
  root = __dir__ + '/../ios'
  project_path = Dir[File.join(root, '*.xcodeproj')].first
  project = Xcodeproj::Project.open(project_path)
  app = project.targets.find { |t| t.product_type == 'com.apple.product-type.application' }
  deployment = app.build_configurations.first.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '16.4'
  target = project.targets.find { |t| t.name == name } || project.new_target(:app_extension, name, :ios, deployment)
  folder = File.join(root, name)
  FileUtils.mkdir_p(folder)
  group = project.main_group.find_subpath(name, true)
  group.set_source_tree('<group>')
  group.set_path(name)
  Dir[File.join(__dir__, '..', source_dir, '*.swift')].sort.each do |path|
    basename = File.basename(path)
    FileUtils.cp(path, folder)
    file = group.files.find { |f| f.path == basename } || group.new_file(basename)
    target.source_build_phase.add_file_reference(file, true)
  end
  extension_info = { 'NSExtensionPointIdentifier' => point_identifier }
  extension_info['NSExtensionPrincipalClass'] = principal_class if principal_class
  Xcodeproj::Plist.write_to_path({
    'CFBundleDisplayName' => display_name,
    'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)',
    'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
    'CFBundleName' => '$(PRODUCT_NAME)',
    'CFBundlePackageType' => 'XPC!',
    'CFBundleShortVersionString' => '$(MARKETING_VERSION)',
    'CFBundleVersion' => '$(CURRENT_PROJECT_VERSION)',
    'NSExtension' => extension_info
  }.merge(extra_plist), File.join(folder, 'Info.plist'))
  Xcodeproj::Plist.write_to_path({ 'com.apple.security.application-groups' => ["group.#{bundle_id}"] }, File.join(folder, "#{name}.entitlements"))
  target.build_configurations.each do |configuration|
    owner = app.build_configurations.find { |c| c.name == configuration.name }.build_settings
    plist_path = owner['INFOPLIST_FILE'].to_s.delete('\"')
    app_info = Xcodeproj::Plist.read_from_path(File.join(root, plist_path))
    version = app_info['CFBundleShortVersionString']
    build = app_info['CFBundleVersion']
    version = owner['MARKETING_VERSION'] if version.to_s.start_with?('$(')
    build = owner['CURRENT_PROJECT_VERSION'] if build.to_s.start_with?('$(')
    configuration.build_settings.merge!({
      'PRODUCT_NAME' => '$(TARGET_NAME)',
      'PRODUCT_BUNDLE_IDENTIFIER' => "#{bundle_id}.#{suffix}",
      'INFOPLIST_FILE' => "#{name}/Info.plist",
      'CODE_SIGN_ENTITLEMENTS' => "#{name}/#{name}.entitlements",
      'CODE_SIGN_STYLE' => 'Automatic',
      'SWIFT_VERSION' => swift_version,
      'IPHONEOS_DEPLOYMENT_TARGET' => deployment,
      'TARGETED_DEVICE_FAMILY' => '1',
      'SKIP_INSTALL' => 'YES',
      'GENERATE_INFOPLIST_FILE' => 'NO',
      'MARKETING_VERSION' => version || '0.1.0',
      'CURRENT_PROJECT_VERSION' => build || '1'
    })
    configuration.build_settings['DEVELOPMENT_TEAM'] = owner['DEVELOPMENT_TEAM'] if owner['DEVELOPMENT_TEAM']
  end
  app.add_dependency(target) unless app.dependencies.any? { |d| d.target == target }
  phase = app.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' } || app.new_copy_files_build_phase('Embed App Extensions')
  phase.dst_subfolder_spec = '13'
  phase.add_file_reference(target.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  project.save
end

def lody_push_extension(bundle_id)
  lody_extension(
    bundle_id,
    name: 'LodyNotificationService',
    suffix: 'notification-service',
    source_dir: 'modules/lody-kit/notification-extension',
    point_identifier: 'com.apple.usernotifications.service',
    principal_class: '$(PRODUCT_MODULE_NAME).NotificationService',
    display_name: 'Lody Notifications',
    swift_version: '5.0',
    extra_plist: { 'OneSignal_app_groups_key' => "group.#{bundle_id}" }
  )
end

def lody_live_activity_extension(bundle_id)
  lody_extension(
    bundle_id,
    name: 'LodyLiveActivity',
    suffix: 'live-activity',
    source_dir: 'modules/lody-kit/live-activity',
    point_identifier: 'com.apple.widgetkit-extension',
    display_name: 'Lody',
    swift_version: '6.0'
  )
end
