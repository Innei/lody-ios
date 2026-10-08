"""Compile and run existing production Swift behavior checks without credentials."""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
from simulator import run_with_simulator, SimulatorPool

root = Path(__file__).resolve().parents[3]
kit = root / 'apps/mobile/modules/lody-kit'
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
    'simulator-transport': ['LodyStrings.swift', 'SimulatorStream/SimulatorDeviceView.swift', 'SimulatorStream/SimulatorRemote.swift', 'SimulatorStream/SimulatorRTCFrame.swift', 'SimulatorStream/SimulatorRTC.swift', 'SimulatorStream/SimulatorTransport.swift'],
    'chat-kit': [],
    'lexical-swift': [],
    'scroll-edges': ['Chrome/LodyScrollEdges.swift', 'LodyTint.swift', 'Chrome/LodyEdgeFade.swift'],
    'glass-transition': [],
    'github-mentions': ['Cloud/GitHubMentions.swift'],
    'github-pr': ['Cloud/GitHubPullRequests.swift'],
    'session-sharing': ['Cloud/SessionSharing.swift'],
    'notifications': ['Notifications/PushPermissionLaunchRequest.swift', 'Notifications/PushClickBuffer.swift'],
    'file-link': ['Chat/ChatFileLink.swift'],
    'strings': ['LodyStrings.swift'],
    'chat': ['LodyStrings.swift', 'Chat/LodyAgentIcon.swift', 'Chat/ChatTranscript.swift', 'Chat/ChatMessageShare.swift', 'Chat/ChatStream.swift', 'Chat/ChatHaptics.swift', 'Chat/ChatImagePreviewGeometry.swift', 'Chat/ChatImageGallery.swift'],
    'markdown-repair': ['Chat/ChatMarkdownRepair.swift'],
    'watchdog': ['Cloud/RuntimeHealth.swift'],
    'local-store': ['Cloud/LocalStore.swift', 'Cloud/SessionProse.swift', 'Text/MarkdownPlainText.swift', 'Text/MarkdownRuby.swift', 'Text/TextSearch.swift', 'LodyStrings.swift'],
    'content-store': ['Cloud/ContentStore.swift'],
    'chat-render': ['LodyStrings.swift', 'LodyTint.swift', 'UIFont+Dynamic.swift', 'Chat/LodyAgentIcon.swift', 'Chat/ChatTranscript.swift', 'Chat/ChatThrowCurve.swift', 'Chat/ChatAttachments.swift', 'Chat/ChatSendHandoff.swift', 'Chat/ChatNumericText.swift', 'Chat/ChatCell.swift', 'Chat/ChatUserMentions.swift'],
    'chat-chrome': ['LodyStrings.swift', 'Chat/ChatOverlay.swift'],
    'context-chip': ['LodyStrings.swift', 'Chat/ChatQuickReplies.swift'],
    'model-panel': ['LodyStrings.swift', 'LodyTint.swift', 'UIFont+Dynamic.swift', 'Chat/ChatComposerModelPanel.swift'],
    'composer': ['Chrome/LodyScrollEdges.swift', 'Chrome/LodyEdgeFade.swift', 'LodyStrings.swift', 'UIFont+Dynamic.swift', 'Chat/ChatAttachments.swift', 'Chat/ChatRecentPhotosView.swift', 'Chat/ChatAttachmentMenu.swift', 'Chat/ChatCameraCapture.swift', 'Chat/ChatAttachmentOverlayCameraView.swift', 'Chat/ChatCameraPage.swift', 'Chat/ChatComposerSurfaceLayout.swift', 'Chat/ChatComposerLiquidGlassSurfaceLayout.swift', 'Chat/ChatMentionPanel.swift', 'Chat/ChatComposerModelPanel.swift', 'Chat/ChatComposerView.swift', 'Chat/ChatReferenceNode.swift', 'Chat/LodyAgentIcon.swift', 'Chat/ChatTranscript.swift', 'Chat/ChatSendHandoff.swift', 'Chat/ChatNumericText.swift', 'Chat/ChatThrowCurve.swift', 'LodyTint.swift', 'Toast/LodyToastOverlay.swift', 'Toast/LodyToastPillView.swift', 'Toast/LodySessionBannerView.swift'],
    'attachments': ['LodyStrings.swift', 'Cloud/SessionAttachments.swift'],
    'inline-diff': ['UIFont+Dynamic.swift', 'Diff/InlineDiffModel.swift', 'Diff/InlineDiffRenderer.swift'],
    'list': [
        'Chrome/LodyMenuButtonStyle.swift',
        'List/LodyRowDensity.swift',
        'List/LodyListCellBackground.swift',
        'List/LodyListPhoto.swift',
        'List/LodyListSectionAnimation.swift',
        'List/LodyUnreadNavigationHold.swift',
        'List/LodySessionRowView.swift',
        'List/LodyProjectRowView.swift',
    ],
    'banner': [
        'LodyStrings.swift',
        'Toast/LodySessionBannerView.swift',
    ],
    'chat-title': ['LodyStrings.swift', 'LodyUIVerify.swift', 'Chrome/LodyNavigationHeader.swift', 'Chat/ChatNavigationTitle.swift'],
    'live-activity': ['../live-activity/LodyActivityAttributes.swift', '../live-activity/LiveActivityCatalog.swift'],
    'page-progress': ['List/LodyPageProgress.swift'],
    'create-session': ['LodyStrings.swift', 'CreateSession/CreateSessionModels.swift', 'CreateSession/CreateSessionLogic.swift', 'CreateSession/CreateSessionForm.swift'],
    'share-ingest': ['LodyStrings.swift', 'Chat/ChatAttachments.swift', 'CreateSession/CreateSessionModels.swift', 'CreateSession/CreateSessionLogic.swift', 'CreateSession/CreateSessionForm.swift', 'CreateSession/ShareStore.swift', '../share-extension/ShareIngest.swift'],
    'share': ['LodyStrings.swift', 'CreateSession/CreateSessionModels.swift', 'CreateSession/CreateSessionLogic.swift', 'CreateSession/CreateSessionForm.swift', 'CreateSession/ShareStore.swift'],
}
if args.case:
    if args.case not in checks:
        parser.error(f'Unknown check {args.case}; choose from {", ".join(checks)}')
    checks = {args.case: checks[args.case]}
for files in checks.values():
    if 'Chat/ChatComposerView.swift' in files:
        files.append('Chat/ChatQuickReplies.swift')
    if 'Chat/ChatTranscript.swift' in files:
        files.append('Chat/ChatPendingSend.swift')
    if 'Chat/ChatSendHandoff.swift' in files or 'Chat/ChatMentionPanel.swift' in files:
        files.insert(0, 'LodyUIVerify.swift')
if 'markdown-repair' in checks:
    subprocess.run(['node', str(root / 'apps/mobile/scripts/build-decoder.mjs')], cwd=root, check=True, timeout=120)
with tempfile.TemporaryDirectory(prefix='lody-native-verify-') as output:
    shader_bundle = Path(output) / 'LodyKitShaders.bundle'
    shader_bundle.mkdir()
    air = str(Path(output) / 'ChatEffortHeat.air')
    subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'metal', '-c', '-target', 'air64-apple-ios26.0-simulator', '-isysroot', sdk, str(kit / 'ios/Chat/Shaders/ChatEffortHeat.metal'), '-o', air], check=True, timeout=120)
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
                (sources / Path(file).name).symlink_to(kit / 'ios' / file)
            (sources / 'main.swift').symlink_to(kit / 'verification' / name / 'main.swift')
            (package / 'Package.swift').symlink_to(kit / 'verification' / name / 'Package.swift')
            subprocess.run(['swift', 'run', '--package-path', str(package), '--scratch-path', str(root / '.artifacts/native-local-store')], check=True, timeout=600)
            continue
        binary = str(Path(output) / name)
        simulator = name in ['simulator-transport', 'share-ingest', 'chat-kit', 'scroll-edges', 'glass-transition', 'model-panel', 'chat-render', 'composer', 'context-chip', 'attachments', 'inline-diff', 'list', 'banner', 'chat-title', 'live-activity', 'chat-chrome']
        command = ['xcrun', '--sdk', 'iphonesimulator', 'swiftc'] if simulator else ['xcrun', 'swiftc']
        command += ['-swift-version', '6']
        if name == 'simulator-transport':
            subprocess.run(['/bin/bash', str(kit / 'datachannel/build.sh')], check=True)
            command += ['-F', str(kit / 'ios/Vendor/LodyDataChannel.xcframework/ios-arm64-simulator'),
                        '-framework', 'LodyDataChannel']
        if simulator:
            arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
            ios = '26.0'
            command += ['-sdk', sdk, '-target', f'{arch}-apple-ios{ios}-simulator']
        if name == 'composer':
            manifest = subprocess.check_output([
                'node', '-p', 'require.resolve("@rien7/anchored-overlay-kit/package.json")',
            ], cwd=root / 'apps/mobile', text=True).strip()
            sources = sorted((Path(manifest).parent / 'Sources/AnchoredOverlayKit').glob('*.swift'))
            subprocess.run([
                *command, '-emit-library', '-static', '-emit-module',
                '-module-name', 'AnchoredOverlayKit',
                '-emit-module-path', str(Path(output) / 'AnchoredOverlayKit.swiftmodule'),
                *map(str, sources), '-o', str(Path(output) / 'libAnchoredOverlayKit.a'),
            ], check=True, timeout=120)
            command += ['-I', output, '-L', output, '-lAnchoredOverlayKit']
        if name in ['attachments', 'github-mentions', 'github-pr', 'session-sharing']:
            command += ['-parse-as-library']
        if name == 'inline-diff':
            command += ['-framework', 'UIKit']
        if name in ['chat-render', 'composer', 'context-chip', 'chat-title']:
            command += ['-framework', 'SwiftUI']
        main = kit / 'verification' / name / 'main.swift'
        package_sources = [kit / 'ios' / file for file in files] + [main]
        if any('import ChatKit' in source.read_text() for source in package_sources):
            modules = chat_modules(simulator)
            command += ['-I', str(modules), '-L', str(modules), '-lChatKitCore']
            if simulator:
                command += ['-lChatKit']
        if any('import Lexical' in source.read_text() for source in package_sources):
            modules = lexical_package()
            command += ['-I', str(modules), '-L', str(modules)] + [f'-l{module}' for module, _ in lexical_modules]
        command += [str(kit / 'ios' / file) for file in files]
        command += [str(main), '-o', binary]
        # Xcode 27 CI compiles the larger chat/composer graphs much slower than a local Mac.
        subprocess.run(command, check=True, timeout=240)
        # A cold CI Simulator draws its first text far slower than a warm local one.
        command = ['xcrun', 'simctl', 'spawn', args.udid, binary] if simulator else [binary]
        if name == 'simulator-transport':
            subprocess.run(['codesign', '--force', '--sign', '-', binary], check=True)
            with subprocess.Popen(['node', str(kit / 'verification/simulator-transport/server.mjs')], stdout=subprocess.PIPE, text=True) as server:
                try:
                    endpoint = server.stdout.readline().strip()
                    if not endpoint.startswith('http://127.0.0.1:'):
                        raise RuntimeError('Simulator transport fixture server did not start')
                    subprocess.run(command, check=True, timeout=90, env={**os.environ, 'SIMCTL_CHILD_LODY_SIMULATOR_TEST_URL': endpoint})
                finally:
                    server.terminate()
        elif name == 'attachments':
            with subprocess.Popen([sys.executable, str(kit / 'verification/attachments/progress-server.py')], stdout=subprocess.PIPE, text=True) as server:
                try:
                    endpoint = server.stdout.readline().strip()
                    subprocess.run(command, check=True, timeout=300, env={**os.environ, 'SIMCTL_CHILD_LODY_UPLOAD_TEST_URL': endpoint})
                finally:
                    server.terminate()
        else:
            subprocess.run(command, check=True, timeout=300)
