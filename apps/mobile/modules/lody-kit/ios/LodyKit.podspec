require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name = 'LodyKit'
  s.version = package['version']
  s.summary = 'First-party iOS capabilities and native UI for Lody.'
  s.homepage = 'https://github.com/Innei/lody-ios'
  s.license = { type: 'Proprietary' }
  s.authors = 'Innei'
  s.platform = :ios, '16.4'
  s.swift_version = '5.9'
  s.source = { git: 'https://github.com/Innei/lody-ios.git', tag: s.version.to_s }
  s.static_framework = true
  s.libraries = 'sqlite3'
  s.dependency 'ExpoModulesCore'
  # Precompiled ExpoModulesCore skips autolinking's macro-plugin injection.
  macros_plugin = File.join(File.dirname(`node --print "require.resolve('@expo/expo-modules-macros-plugin/package.json')"`.strip), 'apple')
  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => "$(inherited) -Xfrontend -load-plugin-executable -Xfrontend \"#{macros_plugin}/ExpoModulesMacros-tool#ExpoModulesMacros\""
  }
  s.spm_dependency 'MarkdownView/MarkdownView'
  s.spm_dependency 'MarkdownView/MarkdownParser'
  s.source_files = '**/*.swift'
  s.resources = 'Resources/*'
end
