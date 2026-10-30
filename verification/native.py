"""Compile and run existing production Swift behavior checks without credentials."""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
from simulator import run_with_simulator, SimulatorPool

root = Path(__file__).resolve().parents[1]
transport = root / 'Libraries/SimulatorTransport'
data = root / 'packages/LodyData/Sources'


def source(file):
    path = Path(file)
    if path.is_absolute():
        return path
    shared = data / path
    return shared if shared.exists() else root / path

checks_root = root / 'verification/kit'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--case', help='Run one named native check, such as attachments or chat')
parser.add_argument(
    '--udid',
    default=os.environ.get('LODY_VERIFY_UDID') or None,
    help='Existing Simulator; omit to lease a clean Lody Verify Simulator',
)
args = parser.parse_args()
if args.udid is None:
    command = [sys.executable, __file__, *sys.argv[1:]]
    raise SystemExit(run_with_simulator(SimulatorPool(), 'Native', command))
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
checks = {
    'home-layout': ['iOS/Models/Home/LodyHomeLayout.swift'],
    'fold-host': ['iOS/Navigation/Home/LodyFoldHost.swift', 'iOS/ViewControllers/Home/ArrangementController.swift'],
    'session-feed': ['Sessions/SessionFeed.swift', 'Sessions/SessionEnvelope.swift', 'Sessions/SessionPermission.swift'],
    'session-simulator': ['Sessions/SessionSimulator.swift'],
    'preview-feedback': ['Outbox/OutboxRecord.swift', 'Outbox/OutboxStore.swift', 'iOS/Views/Files/HTMLPreview/PreviewFeedback.swift'],
    'pull-request': ['iOS/Services/PullRequests/PullRequestStore.swift'],
    'item-details': ['iOS/Services/Sessions/ItemDetails/ItemDetailStore.swift'],
    'message-details': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Models/List/LodyListModels.swift', 'iOS/Views/List/LodyListState.swift', 'Chat/ChatTurnMetadata.swift', 'iOS/Models/Sessions/Messages/MessageDetailsSections.swift'],
    'html-preview': ['Shared/UIKit/Localization/LodyLocalization.swift', 'iOS/Views/Files/HTMLPreview/HTMLPreviewResource.swift', 'iOS/Views/Files/HTMLPreview/HTMLPreviewText.swift'],
    'simulator-transport': ['Shared/UIKit/Localization/LodyLocalization.swift', 'iOS/Views/Simulator/SimulatorDeviceView.swift', 'iOS/Services/Simulator/SimulatorRemote.swift', 'iOS/Models/Simulator/SimulatorRTCFrame.swift', 'iOS/Services/Simulator/SimulatorRTC.swift', 'iOS/Services/Simulator/SimulatorTransport.swift'],
    'chat-kit': [],
    'lexical-swift': [],
    'scroll-edges': ['Shared/UIKit/Chrome/LodyScrollEdges.swift', 'Shared/UIKit/Styling/LodyTint.swift', 'Shared/UIKit/Chrome/LodyEdgeFade.swift'],
    'glass-transition': [],
    'github-mentions': ['Cloud/GitHubMentions.swift'],
    'github-pr': ['Cloud/GitHubPullRequests.swift'],
    'session-sharing': ['Cloud/SessionSharing.swift'],
    'settings': ['Cloud/WorkspaceSettingsCloud.swift', 'Cloud/WorkspaceUsage.swift', 'Cloud/WorkspaceMembers.swift'],
    'workspace-settings-pages': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Models/List/LodyListModels.swift', 'Settings/SettingsWorkspace.swift', 'iOS/Views/Settings/SettingsText.swift', 'iOS/Models/Settings/ProjectVisibilitySections.swift', 'iOS/Models/Settings/GitHubSettingsSections.swift'],
    'settings-runtime-pages': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Models/List/LodyListModels.swift', 'iOS/Views/List/LodyListState.swift', 'iOS/Models/Settings/MemorySettingsSections.swift', 'iOS/Models/Settings/PublishedSharesSections.swift'],
    'remote-settings': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Models/List/LodyListModels.swift', 'iOS/Views/List/LodyListState.swift', 'Settings/SettingsWorkspace.swift', 'iOS/Views/Settings/SettingsText.swift', 'iOS/Models/Settings/RemoteSettingsSections.swift'],
    'session-rows': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Models/List/LodyListModels.swift', 'iOS/Views/List/LodyListState.swift', 'Sessions/SessionCatalog.swift', 'Sessions/SessionDeletion.swift', 'iOS/Models/Sessions/SessionRows.swift', 'iOS/Models/Home/Inbox/InboxSections.swift', 'Sessions/SessionEnvelope.swift', 'Sessions/SessionPermission.swift'],
    'ai-usage': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Models/List/LodyListModels.swift', 'iOS/Views/List/LodyListState.swift', 'Settings/AIUsageModels.swift', 'iOS/Models/Settings/AIUsageSections.swift'],
    'settings-roles': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Models/List/LodyListModels.swift', 'iOS/Models/Settings/PromptShortcutSections.swift', 'iOS/Models/Settings/AgentRoleSections.swift'],
    'notifications': ['iOS/Platform/Notifications/PushPermissionLaunchRequest.swift', 'iOS/Platform/Notifications/PushClickBuffer.swift'],
    'diagnostics': ['Diagnostics/DiagnosticsStore.swift'],
    'file-link': ['iOS/Views/Sessions/Transcript/ChatFileLink.swift'],
    'strings': ['Shared/UIKit/Localization/LodyLocalization.swift'],
    'auth': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Auth/AuthAPI.swift'],
    'session-permission': ['Sessions/PermissionProjection.swift', 'Sessions/SessionPermission.swift', 'Sessions/SessionEnvelope.swift'],
    'session-decisions': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Sessions/SessionEnvelope.swift', 'Sessions/SessionPermission.swift', 'Sessions/SessionDecisions.swift'],
    'outbox': ['Outbox/OutboxRecord.swift', 'Outbox/OutboxStore.swift', 'Outbox/OutboxDispatcher.swift', 'Outbox/OutboxForeground.swift', 'Sessions/SessionEnvelope.swift', 'Sessions/SessionPermission.swift'],
    'chat': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Chat/LodyAgentIcon.swift', 'Chat/ChatTranscript.swift', 'iOS/Views/Sessions/Transcript/ChatMessageShare.swift', 'Chat/ChatStream.swift', 'iOS/Views/Sessions/Transcript/ChatHaptics.swift', 'iOS/Views/Sessions/Transcript/ChatImagePreviewGeometry.swift', 'iOS/Views/Sessions/Transcript/ChatImageGallery.swift'],
    'markdown-repair': ['iOS/Views/Sessions/Transcript/ChatMarkdownRepair.swift'],
    'watchdog': [],
    'local-store': ['Cloud/LocalStore.swift', 'Cloud/SessionProse.swift', 'Text/MarkdownPlainText.swift', 'Text/MarkdownRuby.swift', 'Text/TextSearch.swift', 'Shared/UIKit/Localization/LodyLocalization.swift'],
    'content-store': ['Cloud/ContentStore.swift'],
    'chat-render': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Styling/LodyTint.swift', 'Shared/UIKit/Styling/UIFont+Dynamic.swift', 'Shared/UIKit/Styling/LodyDesign.swift', 'Shared/UIKit/Views/List/LodyStatusGlyph.swift', 'Chat/LodyAgentIcon.swift', 'Chat/ChatTranscript.swift', 'Shared/UIKit/Views/Composer/ChatThrowCurve.swift', 'Shared/UIKit/Views/Composer/ChatAttachments.swift', 'Shared/UIKit/Views/Composer/ChatSendHandoff.swift', 'Shared/UIKit/Views/Composer/ChatNumericText.swift', 'iOS/Views/Sessions/Transcript/ChatCell.swift', 'iOS/Views/Sessions/Transcript/ChatUserMentions.swift'],
    'chat-subagent': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Styling/LodyTint.swift', 'Shared/UIKit/Styling/UIFont+Dynamic.swift', 'Shared/UIKit/Styling/LodyDesign.swift', 'Shared/UIKit/Views/List/LodyStatusGlyph.swift', 'Chat/LodyAgentIcon.swift', 'Chat/ChatTranscript.swift', 'Shared/UIKit/Views/Composer/ChatThrowCurve.swift', 'Shared/UIKit/Views/Composer/ChatAttachments.swift', 'Shared/UIKit/Views/Composer/ChatSendHandoff.swift', 'Shared/UIKit/Views/Composer/ChatNumericText.swift', 'iOS/Views/Sessions/Transcript/ChatCell.swift', 'iOS/Views/Sessions/Transcript/ChatUserMentions.swift', 'iOS/Views/Sessions/Transcript/ChatSubagentCell.swift'],
    'chat-files': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Styling/LodyTint.swift', 'Shared/UIKit/Styling/UIFont+Dynamic.swift', 'Shared/UIKit/Styling/LodyDesign.swift', 'Shared/UIKit/Views/List/LodyStatusGlyph.swift', 'Chat/LodyAgentIcon.swift', 'Chat/ChatTranscript.swift', 'Shared/UIKit/Views/Composer/ChatThrowCurve.swift', 'Shared/UIKit/Views/Composer/ChatAttachments.swift', 'Shared/UIKit/Views/Composer/ChatSendHandoff.swift', 'Shared/UIKit/Views/Composer/ChatNumericText.swift', 'iOS/Views/Sessions/Transcript/ChatCell.swift', 'iOS/Views/Sessions/Transcript/ChatUserMentions.swift', 'iOS/Views/Sessions/Transcript/ChatFileCell.swift'],
    'chat-chrome': ['Shared/UIKit/Localization/LodyLocalization.swift', 'iOS/Views/Sessions/Transcript/ChatOverlay.swift'],
    'context-chip': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Views/Composer/ChatQuickReplies.swift'],
    'model-panel': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Styling/LodyTint.swift', 'Shared/UIKit/Styling/UIFont+Dynamic.swift', 'Shared/UIKit/ViewControllers/Composer/ComposerOptionsController.swift'],
    'composer': ['Shared/UIKit/Chrome/LodyScrollEdges.swift', 'Shared/UIKit/Chrome/LodyEdgeFade.swift', 'Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Styling/UIFont+Dynamic.swift', 'Shared/UIKit/Views/Composer/ChatAttachments.swift', 'iOS/Views/Composer/ChatRecentPhotosView.swift', 'iOS/Views/Composer/ChatAttachmentMenu.swift', 'Shared/UIKit/Views/Composer/ChatCameraCapture.swift', 'iOS/Views/Composer/ChatAttachmentOverlayCameraView.swift', 'iOS/Views/Composer/ChatCameraPage.swift', 'Shared/UIKit/Views/Composer/ChatComposerSurfaceLayout.swift', 'Shared/UIKit/Views/Composer/ChatComposerLiquidGlassSurfaceLayout.swift', 'Shared/UIKit/Views/Composer/ChatComposerAttachmentStack.swift', 'Shared/UIKit/Views/Composer/ChatComposerGrabber.swift', 'Shared/UIKit/Views/Composer/ChatMentionPanel.swift', 'Shared/UIKit/ViewControllers/Composer/ComposerOptionsController.swift', 'Shared/UIKit/Views/Composer/ChatComposerView.swift', 'Shared/UIKit/Views/Composer/ChatReferenceNode.swift', 'Chat/LodyAgentIcon.swift', 'Chat/ChatTranscript.swift', 'Shared/UIKit/Views/Composer/ChatSendHandoff.swift', 'Shared/UIKit/Views/Composer/ChatNumericText.swift', 'Shared/UIKit/Views/Composer/ChatThrowCurve.swift', 'Shared/UIKit/Styling/LodyTint.swift', 'Shared/UIKit/Feedback/LodyToastOverlay.swift', 'Shared/UIKit/Feedback/LodyToastPillView.swift', 'Shared/UIKit/Feedback/LodySessionBannerView.swift'],
    'attachments': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Diagnostics/DiagnosticsStore.swift', 'Cloud/SessionAttachments.swift'],
    'inline-diff': ['Shared/UIKit/Styling/UIFont+Dynamic.swift', 'iOS/Models/Files/Diff/InlineDiffModel.swift', 'iOS/Views/Files/Diff/InlineDiffRenderer.swift', 'iOS/Models/Files/Diff/DiffDocumentModel.swift', 'iOS/Models/Files/Diff/DiffDocumentLayout.swift'],
    'list': [
        'iOS/Views/Chrome/LodyMenuButtonStyle.swift',
        'Shared/UIKit/Views/List/LodyRowDensity.swift',
        'Shared/UIKit/Views/List/LodyListCellBackground.swift',
        'Shared/UIKit/Views/List/LodyListPhoto.swift',
        'Shared/UIKit/Views/List/LodyListSectionAnimation.swift',
        'Shared/UIKit/Views/List/LodyUnreadNavigationHold.swift',
        'Shared/UIKit/Views/List/LodySessionRowView.swift',
        'Shared/UIKit/Views/List/LodyProjectRowView.swift',
        'Shared/UIKit/Styling/LodyDesign.swift',
        'Shared/UIKit/Views/List/LodyStatusGlyph.swift',
        'Shared/UIKit/Views/List/LodyFlatRows.swift',
        'Text/TextSearch.swift',
    ],
    'list-snapshots': ['Shared/UIKit/Models/List/LodyListModels.swift'],
    'banner': [
        'Shared/UIKit/Localization/LodyLocalization.swift',
        'Shared/UIKit/Feedback/LodySessionBannerView.swift',
    ],
    'chat-title': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Debug/LodyUIVerify.swift', 'Shared/UIKit/Styling/LodyTint.swift', 'iOS/Views/Chrome/LodyNavigationHeader.swift', 'iOS/Views/Chrome/LodyNavigationSearch.swift', 'iOS/Views/Sessions/Transcript/ChatNavigationTitle.swift'],
    'live-activity-registration': ['iOS/Platform/Notifications/LiveActivityRegistration.swift'],
    'live-activity': ['Shared/LiveActivity/LodyActivityAttributes.swift', 'Shared/LiveActivity/LiveActivityCatalog.swift'],
    'page-progress': ['Shared/UIKit/Views/List/LodyPageProgress.swift'],
    'create-session': ['Shared/UIKit/Localization/LodyLocalization.swift', 'CreateSession/CreateSessionForm.swift'],
    'unified-patch': ['iOS/Models/Files/Diff/UnifiedPatch.swift'],
    'create-draft': ['Shared/UIKit/Localization/LodyLocalization.swift', 'CreateSession/CreateSessionForm.swift', 'Outbox/OutboxRecord.swift', 'CreateSession/CreateDraftRecord.swift'],
    'share-ingest': ['Shared/UIKit/Localization/LodyLocalization.swift', 'Shared/UIKit/Views/Composer/ChatAttachments.swift', 'CreateSession/CreateSessionForm.swift', 'Shared/ShareSupport/ShareStore.swift', str(root / 'Extensions/Share/ShareIngest.swift')],
    'share': ['Shared/UIKit/Localization/LodyLocalization.swift', 'CreateSession/CreateSessionForm.swift', 'Shared/ShareSupport/ShareStore.swift'],
    'design': ['Shared/UIKit/Styling/LodyTint.swift'],
    'form': ['Shared/UIKit/Styling/LodyTint.swift', 'Shared/UIKit/Styling/UIFont+Dynamic.swift', 'Shared/UIKit/Chrome/LodyScrollEdges.swift', 'Shared/UIKit/Chrome/LodyEdgeFade.swift', 'iOS/Views/Form/LodyForm.swift'],
}
if args.case:
    if args.case not in checks:
        parser.error(f'Unknown check {args.case}; choose from {", ".join(checks)}')
    checks = {args.case: checks[args.case]}
for files in checks.values():
    if 'Shared/UIKit/ViewControllers/Composer/ComposerOptionsController.swift' in files:
        files += ['Shared/UIKit/Models/ComposerOptions.swift', 'Shared/UIKit/Views/Composer/ChatEffortSlider.swift']
    if 'iOS/Views/Form/LodyForm.swift' in files:
        files.append('iOS/ViewControllers/Base/FormController.swift')
    if 'Shared/UIKit/Views/Composer/ChatAttachments.swift' in files:
        files.append('Shared/UIKit/ViewControllers/Attachments/AttachmentPreviewController.swift')
    if files and 'Shared/UIKit/Localization/LodyLocalization.swift' not in files:
        files.append('Shared/UIKit/Localization/LodyLocalization.swift')
    if files and 'LodyDataBundle.swift' not in files:
        files.append('LodyDataBundle.swift')
    if 'Shared/UIKit/Styling/LodyTint.swift' in files and 'Preferences/LodyAppearanceChoices.swift' not in files:
        files.append('Preferences/LodyAppearanceChoices.swift')
    if 'Shared/UIKit/Views/List/LodyStatusGlyph.swift' in files and 'Shared/UIKit/Views/List/LodyTentacle.swift' not in files:
        files.append('Shared/UIKit/Views/List/LodyTentacle.swift')
    if 'Shared/UIKit/Styling/LodyTint.swift' in files and 'Shared/UIKit/Styling/LodyDesign.swift' not in files:
        files.append('Shared/UIKit/Styling/LodyDesign.swift')
    if 'Shared/UIKit/Views/Composer/ChatComposerView.swift' in files:
        files.append('Shared/UIKit/Views/Composer/ChatQuickReplies.swift')
        files.append('Shared/UIKit/Views/Composer/ChatComposerFormatBar.swift')
    if ('Cloud/LocalStore.swift' in files or 'Diagnostics/DiagnosticsStore.swift' in files) and 'LodyStorage.swift' not in files:
        files.append('LodyStorage.swift')
    if 'Chat/ChatTranscript.swift' in files:
        files.append('Chat/ChatPendingSend.swift')
        files.append('Chat/ChatTurnMetadata.swift')
    if 'Shared/UIKit/Views/Composer/ChatSendHandoff.swift' in files or 'Shared/UIKit/Views/Composer/ChatMentionPanel.swift' in files:
        files.insert(0, 'Debug/LodyUIVerify.swift')
if 'markdown-repair' in checks:
    subprocess.run(['node', str(root / 'scripts/build-decoder.mjs')], cwd=root, check=True, timeout=120)
with tempfile.TemporaryDirectory(prefix='lody-native-verify-') as output:
    shader_bundle = Path(output) / 'ComposerShaders.bundle'
    shader_bundle.mkdir()
    air = str(Path(output) / 'ChatEffortHeat.air')
    subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'metal', '-c', '-target', 'air64-apple-ios26.0-simulator', '-isysroot', sdk, str(root / 'iOS/Resources/Shaders/ChatEffortHeat.metal'), '-o', air], check=True, timeout=120)
    subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'metallib', air, '-o', str(shader_bundle / 'default.metallib')], check=True, timeout=120)
    # Build the extracted modules from their production sources. Core remains
    # host-testable; UIKit checks link the same package module as the app.
    module_dirs = {}
    def chat_modules(simulator):
        if simulator in module_dirs:
            return module_dirs[simulator]
        directory = Path(output) / ('chat-package-ios' if simulator else 'chat-package-host')
        directory.mkdir()
        module_dirs[simulator] = directory
        command = ['xcrun', 'swiftc', '-swift-version', '6']
        if simulator:
            arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
            command += ['-sdk', sdk, '-target', f'{arch}-apple-ios26.0-simulator']
        modules = ['ChatKitCore', 'ChatKit'] if simulator else ['ChatKitCore']
        for module in modules:
            sources = sorted((root / 'packages/chat-kit/Sources' / module).glob('*.swift'))
            subprocess.run(command + ['-I', str(directory), '-emit-module', '-emit-library', '-static',
                '-module-name', module, '-emit-module-path', str(directory / f'{module}.swiftmodule'),
                *map(str, sources), '-o', str(directory / f'lib{module}.a')], check=True, timeout=240)
        return directory

    lexical_dir = Path(output) / 'lexical-package'
    lexical_modules = [('Lexical', '5'), ('LexicalListPlugin', '5'), ('LexicalLinkPlugin', '5'), ('LexicalMarkdown', '6'), ('EditorHistoryPlugin', '5'), ('LexicalHTML', '6')]

    def lexical_package():
        if lexical_dir.exists():
            return lexical_dir
        lexical_dir.mkdir()
        arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
        for module, version in lexical_modules:
            sources = sorted((root / 'packages/lexical-swift/Sources' / module).rglob('*.swift'))
            subprocess.run(['xcrun', 'swiftc', '-swift-version', version, '-sdk', sdk, '-target', f'{arch}-apple-ios26.0-simulator',
                '-I', str(lexical_dir), '-emit-module', '-emit-library', '-static', '-module-name', module,
                '-emit-module-path', str(lexical_dir / f'{module}.swiftmodule'), *map(str, sources),
                '-o', str(lexical_dir / f'lib{module}.a')], check=True, timeout=600)
        return lexical_dir

    for name, files in checks.items():
        if name == 'lexical-swift':
            subprocess.run(['xcodebuild', 'test', '-scheme', 'Lexical-Package', '-destination', f'id={args.udid}',
                '-derivedDataPath', str(root / '.artifacts/native-lexical-swift'), '-collect-test-diagnostics', 'never'],
                cwd=root / 'packages/lexical-swift', check=True, timeout=1800)
            continue
        if name == 'local-store':
            # Compile the production parser, not a regex or a test-only stand-in.
            package = Path(output) / name
            sources = package / 'Sources'
            sources.mkdir(parents=True)
            for file in files:
                (sources / Path(file).name).symlink_to(source(file))
            (sources / 'Resources').symlink_to(data / 'Resources', target_is_directory=True)
            (sources / 'main.swift').symlink_to(checks_root / name / 'main.swift')
            (package / 'Package.swift').symlink_to(checks_root / name / 'Package.swift')
            subprocess.run(['swift', 'run', '--package-path', str(package), '--scratch-path', str(root / '.artifacts/native-local-store')], check=True, timeout=600)
            continue
        binary = str(Path(output) / name)
        simulator = name in ['fold-host', 'message-details', 'simulator-transport', 'share-ingest', 'chat-kit', 'scroll-edges', 'glass-transition', 'model-panel', 'chat-render', 'composer', 'context-chip', 'attachments', 'inline-diff', 'list', 'list-snapshots', 'ai-usage', 'workspace-settings-pages', 'settings-roles', 'settings-runtime-pages', 'remote-settings', 'session-rows', 'banner', 'chat-title', 'live-activity', 'chat-chrome', 'design', 'form', 'chat-subagent', 'chat-files']
        command = ['xcrun', '--sdk', 'iphonesimulator', 'swiftc'] if simulator else ['xcrun', 'swiftc']
        command += ['-swift-version', '6']
        if name in ['message-details', 'list-snapshots', 'ai-usage', 'workspace-settings-pages', 'settings-roles', 'settings-runtime-pages', 'remote-settings', 'session-rows']:
            command += ['-D', 'LODY_SHARE_EXTENSION']
        if name == 'simulator-transport':
            subprocess.run(['/bin/bash', str(transport / 'DataChannel/build.sh')], check=True)
            command += ['-F', str(transport / 'Vendor/LodyDataChannel.xcframework/ios-arm64_x86_64-simulator'),
                        '-framework', 'LodyDataChannel']
        if simulator:
            arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
            ios = '26.0'
            command += ['-sdk', sdk, '-target', f'{arch}-apple-ios{ios}-simulator']
        if name == 'composer':
            manifest = subprocess.check_output([
                'node', '-p', 'require.resolve("@rien7/anchored-overlay-kit/package.json")',
            ], cwd=root, text=True).strip()
            sources = sorted((Path(manifest).parent / 'Sources/AnchoredOverlayKit').glob('*.swift'))
            subprocess.run([
                *command, '-emit-library', '-static', '-emit-module',
                '-module-name', 'AnchoredOverlayKit',
                '-emit-module-path', str(Path(output) / 'AnchoredOverlayKit.swiftmodule'),
                *map(str, sources), '-o', str(Path(output) / 'libAnchoredOverlayKit.a'),
            ], check=True, timeout=120)
            command += ['-I', output, '-L', output, '-lAnchoredOverlayKit']
        if name in ['session-feed', 'session-simulator', 'preview-feedback', 'pull-request', 'item-details', 'attachments', 'auth', 'outbox', 'github-mentions', 'github-pr', 'session-sharing', 'settings']:
            command += ['-parse-as-library']
        if name == 'inline-diff':
            command += ['-framework', 'UIKit']
        if name in ['chat-render', 'composer', 'context-chip', 'chat-title', 'chat-subagent', 'chat-files']:
            command += ['-framework', 'SwiftUI']
        main = checks_root / name / 'main.swift'
        package_sources = [source(file) for file in files] + [main]
        if any('import LodyCore' in source.read_text() for source in package_sources):
            directory = Path(output) / ('lody-core-ios' if simulator else 'lody-core-host')
            if not directory.exists():
                directory.mkdir()
                sources = sorted((root / 'packages/lody-core/Sources/LodyCore').rglob('*.swift'))
                compile_core = ['xcrun', 'swiftc', '-swift-version', '6']
                if simulator:
                    compile_core += ['-sdk', sdk, '-target', f'{arch}-apple-ios26.0-simulator']
                subprocess.run(compile_core + ['-emit-module', '-emit-library', '-static', '-module-name', 'LodyCore',
                    '-emit-module-path', str(directory / 'LodyCore.swiftmodule'), *map(str, sources),
                    '-o', str(directory / 'libLodyCore.a')], check=True, timeout=120)
            command += ['-I', str(directory), '-L', str(directory), '-lLodyCore']
        if any('import ChatKit' in source.read_text() for source in package_sources):
            modules = chat_modules(simulator)
            command += ['-I', str(modules), '-L', str(modules), '-lChatKitCore']
            if simulator:
                command += ['-lChatKit']
        if any('import Lexical' in source.read_text() for source in package_sources):
            modules = lexical_package()
            command += ['-I', str(modules), '-L', str(modules)] + [f'-l{module}' for module, _ in lexical_modules]
        command += [str(source(file)) for file in files]
        command += [str(main), '-o', binary]
        # Xcode 27 CI compiles the larger chat/composer graphs much slower than a local Mac.
        subprocess.run(command, check=True, timeout=240)
        # A cold CI Simulator draws its first text far slower than a warm local one.
        command = ['xcrun', 'simctl', 'spawn', args.udid, binary] if simulator else [binary]
        if name == 'simulator-transport':
            subprocess.run(['codesign', '--force', '--sign', '-', binary], check=True)
            with subprocess.Popen(['node', str(checks_root / 'simulator-transport/server.mjs')], stdout=subprocess.PIPE, text=True) as server:
                try:
                    endpoint = server.stdout.readline().strip()
                    if not endpoint.startswith('http://127.0.0.1:'):
                        raise RuntimeError('Simulator transport fixture server did not start')
                    subprocess.run(command, check=True, timeout=90, env={**os.environ, 'SIMCTL_CHILD_LODY_SIMULATOR_TEST_URL': endpoint,
                                                                       'SIMCTL_CHILD_OS_ACTIVITY_DT_MODE': 'enable'})
                finally:
                    server.terminate()
        elif name == 'strings':
            resources = Path(output) / 'Localization.bundle'
            resources.mkdir()
            subprocess.run(['xcrun', 'xcstringstool', 'compile', str(data / 'Resources/Localizable.xcstrings'),
                            '--output-directory', str(resources)], check=True)
            subprocess.run([*command, str(resources)], check=True, timeout=60)
        elif name == 'attachments':
            command += ['--ui-verify']
            with subprocess.Popen([sys.executable, str(checks_root / 'attachments/progress-server.py')], stdout=subprocess.PIPE, text=True) as server:
                try:
                    endpoint = server.stdout.readline().strip()
                    subprocess.run(command, check=True, timeout=300, env={**os.environ, 'SIMCTL_CHILD_LODY_UPLOAD_TEST_URL': endpoint})
                finally:
                    server.terminate()
        else:
            subprocess.run(command, check=True, timeout=300)
