const { withDangerousMod } = require('expo/config-plugins');
const fs = require('fs');
const path = require('path');

const PACKAGES = [
  {
    name: 'ChatKit',
    path: '../../../packages/chat-kit',
  },
  {
    name: 'MarkdownView',
    url: 'https://github.com/Lakr233/MarkdownView.git',
    version: '4.3.2',
  },
  {
    name: 'Litext',
    url: 'https://github.com/Lakr233/Litext',
    version: '2.2.2',
  },
];

const header = `require 'cocoapods/project'
# CocoaPods' sequential UUID list drops Xcodeproj's uniqueness filter, so objects
# added late (cocoapods-spm's SPM target dependencies) reuse the project object's
# own UUID and leave rootObject pointing at a PBXTargetDependency Xcode rejects.
module LodyUniqueProjectUUIDs
  def generate_available_uuid_list(count = 100)
    @lody_uuid_cursor ||= @generated_uuids.size
    taken = (@generated_uuids + uuids).to_set
    uniques = []
    while uniques.size < count
      candidate = format('%.6s%07X0', @uuid_prefix, @lody_uuid_cursor)
      @lody_uuid_cursor += 1
      uniques << candidate unless taken.include?(candidate)
    end
    @generated_uuids += uniques
    @available_uuids += uniques
  end
end
Pod::Project.prepend(LodyUniqueProjectUUIDs)
plugin 'cocoapods-spm'
require 'cocoapods-spm/hooks/helpers/update_script'
# cocoapods-spm 0.1.20 appends to the app target's xcfilelists, which Expo's
# generated project never creates; touch them so the hook does not raise.
module LodySPMFileLists
  def update_script(options = {})
    aggregate_targets.each do |target|
      user_build_configurations.each_key do |config|
        %w[copy_resources_script embed_frameworks_script].each do |name|
          %w[input output].each do |kind|
            path = target.send("#{name}_#{kind}_files_path", config)
            FileUtils.touch(path) unless path.exist?
          end
        end
      end
    end
    super
  end
end
Pod::SPM::UpdateScript::Mixin.prepend(LodySPMFileLists)
`;

const spmPkg = (pkg) => {
  if (pkg.path)
    return `  spm_pkg "${pkg.name}", :path => File.expand_path("${pkg.path}", __dir__)\n`;
  return `  spm_pkg "${pkg.name}", :url => "${pkg.url}", :version => "${pkg.version}"\n`;
};

module.exports = function withMarkdownView(config) {
  return withDangerousMod(config, [
    'ios',
    (config) => {
      const podfile = path.join(
        config.modRequest.platformProjectRoot,
        'Podfile',
      );
      let contents = fs.readFileSync(podfile, 'utf8');
      if (!contents.includes('LodyUniqueProjectUUIDs'))
        contents = header + contents;
      // Retire the previous local package declaration when regenerating iOS.
      contents = contents.replace(/^ *spm_pkg "NativeChatUI"[^\n]*\n/gm, '');
      for (const pkg of PACKAGES) {
        const existing = new RegExp(`^ *spm_pkg "${pkg.name}"[^\\n]*\\n`, 'gm');
        contents = contents.replace(existing, '');
      }
      contents = contents.replace(
        /^target '([^']+)' do\n/m,
        (line) => line + PACKAGES.map(spmPkg).join(''),
      );
      fs.writeFileSync(podfile, contents);
      return config;
    },
  ]);
};
