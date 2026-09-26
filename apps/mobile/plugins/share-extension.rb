require_relative 'push-extension'

# Shared LodyKit sources compile by reference: one form and composer, no Expo,
# React Native, WebView or data runtime in the extension process.
LODY_SHARE_SOURCES = %w[
  LodyAppearanceView.swift LodyStrings.swift LodyTint.swift UIFont+Dynamic.swift LodyUIVerify.swift
  Chrome/LodyScrollEdges.swift Chrome/LodyEdgeFade.swift
  List/LodyGroupedList.swift List/LodyListModels.swift List/LodyPagedList.swift
  List/LodyPageSectionRail.swift List/LodyPageProgress.swift List/LiquidGlassSegmentedControl.swift
  List/LodyListCellBackground.swift List/LodyListPhoto.swift List/LodyListRowInteractions.swift
  List/LodyListSectionAnimation.swift List/LodyProgressRowView.swift List/LodyProjectRowView.swift
  List/LodyRowDensity.swift List/LodySessionRowView.swift List/LodyStepStrip.swift
  List/LodyUnreadNavigationHold.swift
  Chat/LodyAgentIcon.swift Chat/ChatAttachments.swift Chat/ChatAttachmentSheet.swift Chat/ChatAttachmentCamera.swift
  Chat/ChatComposerView.swift Chat/ChatComposerModelPanel.swift Chat/ChatComposerSurfaceLayout.swift
  Chat/ChatComposerLiquidGlassSurfaceLayout.swift Chat/ChatQuickReplies.swift Chat/ChatMentionPanel.swift
  Chat/ChatSendHandoff.swift Chat/ChatThrowCurve.swift Chat/ChatNumericText.swift Chat/ChatPendingSend.swift
  Toast/LodyToastOverlay.swift Toast/LodyToastPillView.swift Toast/LodySessionBannerView.swift
  CreateSession/CreateSessionModels.swift CreateSession/CreateSessionLogic.swift CreateSession/CreateSessionForm.swift
  CreateSession/CreateSessionSections.swift CreateSession/CreateModelOptions.swift
  CreateSession/CreateSessionController.swift CreateSession/CreateSessionPickers.swift CreateSession/ShareStore.swift
].freeze

def lody_share_extension(bundle_id)
  name = 'LodyShare'
  lody_extension(bundle_id,
    name: name, suffix: 'share', source_dir: 'modules/lody-kit/share-extension',
    point_identifier: 'com.apple.share-services', display_name: 'Lody',
    swift_version: '6.0', principal_class: '$(PRODUCT_MODULE_NAME).ShareViewController',
    extra_plist: {
      'NSPhotoLibraryUsageDescription' => 'Choose photos to attach to a Lody message.',
      'NSCameraUsageDescription' => 'Take photos to attach to a Lody message.',
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
  wanted = LODY_SHARE_SOURCES.map { |source| "../modules/lody-kit/ios/#{source}" }
  target.source_build_phase.files.to_a.each do |file|
    path = file.file_ref&.path.to_s
    file.remove_from_project if path.start_with?('../modules/lody-kit/ios/') && !wanted.include?(path)
  end
  wanted.each do |path|
    reference = group.files.find { |f| f.path == path } || group.new_file(path)
    target.source_build_phase.add_file_reference(reference, true)
  end
  package_path = '../../../packages/chat-kit'
  package = project.root_object.package_references.find { |ref| ref.isa == 'XCLocalSwiftPackageReference' && ref.relative_path == package_path }
  unless package
    package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    package.relative_path = package_path
    project.root_object.package_references << package
  end
  unless target.package_product_dependencies.any? { |dep| dep.product_name == 'ChatKit' }
    product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    product.package = package
    product.product_name = 'ChatKit'
    target.package_product_dependencies << product
    build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    build_file.product_ref = product
    target.frameworks_build_phase.files << build_file
  end
  %w[
    Lody/Localizable.xcstrings ../modules/lody-kit/ios/Icons.xcassets
    ../modules/lody-kit/ios/Colors.xcassets ../modules/lody-kit/live-activity/AgentIcons.xcassets
  ].each do |path|
    reference = group.files.find { |f| f.path == path } || group.new_file(path)
    target.resources_build_phase.add_file_reference(reference, true)
  end
  target.build_configurations.each do |configuration|
    configuration.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    configuration.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) LODY_SHARE_EXTENSION'
    configuration.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  end
  project.save
end
