require_relative 'push-extension'

# Compile a small, explicit set of extension-safe native sources. No Expo,
# React Native, WebView, catalog replica, or application lifecycle code.
def lody_share_extension(bundle_id)
  name = 'LodyShare'
  access_group = "$(AppIdentifierPrefix)#{bundle_id}"
  lody_extension(bundle_id,
    name: name, suffix: 'share', source_dir: 'modules/lody-kit/share-extension',
    point_identifier: 'com.apple.share-services', display_name: 'Lody',
    swift_version: '5.0', principal_class: '$(PRODUCT_MODULE_NAME).ShareViewController',
    extra_plist: {
      'LodyAuthAccessGroup' => access_group,
      'NSPhotoLibraryUsageDescription' => 'Choose photos to attach to a Lody message.',
      'NSExtension' => {
        'NSExtensionPointIdentifier' => 'com.apple.share-services',
        'NSExtensionPrincipalClass' => '$(PRODUCT_MODULE_NAME).ShareViewController',
        'NSExtensionAttributes' => { 'NSExtensionActivationRule' => {
          'NSExtensionActivationSupportsText' => true,
          'NSExtensionActivationSupportsWebURLWithMaxCount' => 8,
          'NSExtensionActivationSupportsImageWithMaxCount' => 8,
          'NSExtensionActivationSupportsFileWithMaxCount' => 8
        } }
      }
    })
  root = File.expand_path('../ios', __dir__)
  project = Xcodeproj::Project.open(Dir[File.join(root, '*.xcodeproj')].first)
  target = project.targets.find { |t| t.name == name }
  group = project.main_group.find_subpath('LodyShareShared', true)
  sources = %w[
    Auth/AuthKeychain.swift Cloud/SessionAttachments.swift Cloud/GitHubMentions.swift
    CreateSession/CreateSessionForm.swift CreateSession/CreateSessionController.swift
    CreateSession/CreateSessionOptionsController.swift CreateSession/ShareStore.swift
    CreateSession/ShareSubmission.swift CreateSession/ShareIngest.swift
    Chat/ChatAttachments.swift Chat/ChatAttachmentSheet.swift Chat/ChatPendingSend.swift
    Chat/ChatComposerView.swift Chat/ChatComposerModelPanel.swift Chat/ChatComposerSurfaceLayout.swift
    Chat/ChatComposerLiquidGlassSurfaceLayout.swift Chat/ChatQuickReplies.swift Chat/ChatMentionPanel.swift
    Chat/Shaders/ChatEffortParticles.metal
    Chrome/LodyGlassView.swift Chrome/LodyScrollEdges.swift
    UIFont+Dynamic.swift LodyTint.swift LodyStrings.swift LodyUIVerify.swift
  ]
  sources.each do |source|
    path = "../modules/lody-kit/ios/#{source}"
    reference = group.files.find { |f| f.path == path } || group.new_file(path)
    target.source_build_phase.add_file_reference(reference, true)
  end
  locale = group.files.find { |f| f.path == 'Lody/Localizable.xcstrings' } || group.new_file('Lody/Localizable.xcstrings')
  target.resources_build_phase.add_file_reference(locale, true)
  target.build_configurations.each do |configuration|
    configuration.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    configuration.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) LODY_SHARE_EXTENSION'
  end
  Xcodeproj::Plist.write_to_path({
    'com.apple.security.application-groups' => ["group.#{bundle_id}"],
    'keychain-access-groups' => [access_group]
  }, File.join(root, name, "#{name}.entitlements"))
  project.save
end
