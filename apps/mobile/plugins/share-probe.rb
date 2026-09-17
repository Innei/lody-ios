require_relative 'push-extension'

def lody_share_probe(bundle_id, enabled:)
  root = File.expand_path('../ios', __dir__)
  project = Xcodeproj::Project.open(Dir[File.join(root, '*.xcodeproj')].first)
  target = project.targets.find { |t| t.name == 'LodyShareProbe' }
  unless enabled
    if target
      project.targets.each do |owner|
        owner.dependencies.select { |d| d.target == target }.each(&:remove_from_project)
        owner.copy_files_build_phases.each do |phase|
          phase.files.select { |f| f.file_ref == target.product_reference }.each(&:remove_from_project)
        end
      end
      target.product_reference.remove_from_project
      target.remove_from_project
      project.save
    end
    return
  end

  lody_extension(
    bundle_id,
    name: 'LodyShareProbe', suffix: 'share-probe',
    source_dir: 'modules/lody-kit/share-probe',
    point_identifier: 'com.apple.share-services',
    principal_class: '$(PRODUCT_MODULE_NAME).ShareProbeController',
    display_name: 'Lody Send Probe', swift_version: '6.0'
  )
  project = Xcodeproj::Project.open(project.path)
  target = project.targets.find { |t| t.name == 'LodyShareProbe' }
  group = project.main_group.find_subpath('LodyShareProbe', true)
  kit = File.expand_path('../modules/lody-kit/ios', __dir__)
  %w[Auth/AuthKeychain.swift Cloud/RuntimeHealth.swift].each do |name|
    source = File.join(kit, name)
    reference = group.files.find { |f| f.path == source } || group.new_file(source)
    target.source_build_phase.add_file_reference(reference, true)
  end
  %w[DataRuntime.html Flock-LICENSE.txt Loro-LICENSE.txt].each do |name|
    path = File.join(kit, 'Resources', name)
    reference = group.files.find { |f| f.path == path } || group.new_file(path)
    target.resources_build_phase.add_file_reference(reference, true)
  end
  # Dependencies bundled in DataRuntime, not additional linked frameworks.
  folder = File.join(root, 'LodyShareProbe')
  { '@loro-dev/streams-client' => 'Streams-LICENSE.txt', 'fzstd' => 'Fzstd-LICENSE.txt' }.each do |dependency, name|
    path = File.expand_path("../../../node_modules/#{dependency}/LICENSE", __dir__)
    FileUtils.cp(path, File.join(folder, name))
    reference = group.files.find { |f| f.path == name } || group.new_file(name)
    target.resources_build_phase.add_file_reference(reference, true)
  end
  info_path = File.join(folder, 'Info.plist')
  info = Xcodeproj::Plist.read_from_path(info_path)
  info['LodyShareAppGroup'] = "group.#{bundle_id}"
  info['NSExtension']['NSExtensionAttributes'] = {
    'NSExtensionActivationRule' => {
      'NSExtensionActivationSupportsText' => true,
      'NSExtensionActivationSupportsWebURLWithMaxCount' => 1
    }
  }
  Xcodeproj::Plist.write_to_path(info, info_path)
  Xcodeproj::Plist.write_to_path({
    'com.apple.security.application-groups' => ["group.#{bundle_id}"],
    # Read the containing app's existing item. No credential migration or copy.
    'keychain-access-groups' => ["$(AppIdentifierPrefix)#{bundle_id}"]
  }, File.join(folder, 'LodyShareProbe.entitlements'))
  target.build_configurations.each do |configuration|
    configuration.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  end
  project.save
end
