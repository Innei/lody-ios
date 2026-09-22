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
    'chat-kit': [],
    'scroll-edges': ['Chrome/LodyScrollEdges.swift'],
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
    'model-panel': ['LodyStrings.swift', 'LodyTint.swift', 'UIFont+Dynamic.swift', 'Chat/ChatComposerModelPanel.swift'],
    'composer': ['Chrome/LodyScrollEdges.swift', 'LodyStrings.swift', 'UIFont+Dynamic.swift', 'Chat/ChatAttachments.swift', 'Chat/ChatAttachmentSheet.swift', 'Chat/ChatAttachmentCamera.swift', 'Chat/ChatComposerSurfaceLayout.swift', 'Chat/ChatComposerLiquidGlassSurfaceLayout.swift', 'Chat/ChatMentionPanel.swift', 'Chat/ChatComposerModelPanel.swift', 'Chat/ChatComposerView.swift', 'Chat/LodyAgentIcon.swift', 'Chat/ChatTranscript.swift', 'Chat/ChatSendHandoff.swift', 'Chat/ChatNumericText.swift', 'Chat/ChatThrowCurve.swift', 'LodyTint.swift', 'Toast/LodyToastOverlay.swift', 'Toast/LodyToastPillView.swift', 'Toast/LodySessionBannerView.swift'],
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
    'chat-title': ['LodyUIVerify.swift', 'Chrome/LodyNavigationHeader.swift', 'Chat/ChatNavigationTitle.swift'],
    'live-activity': ['../live-activity/LodyActivityAttributes.swift', '../live-activity/LiveActivityCatalog.swift'],
    'page-progress': ['List/LodyPageProgress.swift'],
}
if args.case:
    if args.case not in checks:
        parser.error(f'Unknown check {args.case}; choose from {", ".join(checks)}')
    checks = {args.case: checks[args.case]}
for files in checks.values():
    if 'Chat/ChatComposerView.swift' in files:
        files.append('Chat/ChatQuickReplies.swift')
    if 'Chat/ChatSendHandoff.swift' in files or 'Chat/ChatMentionPanel.swift' in files:
        files.insert(0, 'LodyUIVerify.swift')
if 'markdown-repair' in checks:
    subprocess.run(['node', str(root / 'apps/mobile/scripts/build-decoder.mjs')], cwd=root, check=True, timeout=120)
with tempfile.TemporaryDirectory(prefix='lody-native-verify-') as output:
    shader_bundle = Path(output) / 'LodyKitShaders.bundle'
    shader_bundle.mkdir()
    air = str(Path(output) / 'ChatEffortParticles.air')
    subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'metal', '-c', '-target', 'air64-apple-ios26.0-simulator', '-isysroot', sdk, str(kit / 'ios/Chat/Shaders/ChatEffortParticles.metal'), '-o', air], check=True, timeout=120)
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

    for name, files in checks.items():
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
        simulator = name in ['chat-kit', 'scroll-edges', 'glass-transition', 'model-panel', 'chat-render', 'composer', 'attachments', 'inline-diff', 'list', 'banner', 'chat-title', 'live-activity', 'chat-chrome']
        command = ['xcrun', '--sdk', 'iphonesimulator', 'swiftc'] if simulator else ['xcrun', 'swiftc']
        command += ['-swift-version', '6']
        if simulator:
            arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
            ios = '26.0'
            command += ['-sdk', sdk, '-target', f'{arch}-apple-ios{ios}-simulator']
        if name in ['attachments', 'github-mentions', 'github-pr', 'session-sharing']:
            command += ['-parse-as-library']
        if name == 'inline-diff':
            command += ['-framework', 'UIKit']
        if name in ['chat-render', 'composer', 'chat-title']:
            command += ['-framework', 'SwiftUI']
        main = kit / 'verification' / name / 'main.swift'
        if name == 'chat-kit':
            main = root / 'packages/chat-kit/Verification/main.swift'
        package_sources = [kit / 'ios' / file for file in files] + [main]
        if any('import ChatKit' in source.read_text() for source in package_sources):
            modules = chat_modules(simulator)
            command += ['-I', str(modules), '-L', str(modules), '-lChatKitCore']
            if simulator:
                command += ['-lChatKit']
        command += [str(kit / 'ios' / file) for file in files]
        command += [str(main), '-o', binary]
        # Xcode 27 CI compiles the larger chat/composer graphs much slower than a local Mac.
        subprocess.run(command, check=True, timeout=240)
        # A cold CI Simulator draws its first text far slower than a warm local one.
        command = ['xcrun', 'simctl', 'spawn', args.udid, binary] if simulator else [binary]
        if name == 'attachments':
            with subprocess.Popen([sys.executable, str(kit / 'verification/attachments/progress-server.py')], stdout=subprocess.PIPE, text=True) as server:
                try:
                    endpoint = server.stdout.readline().strip()
                    subprocess.run(command, check=True, timeout=300, env={**os.environ, 'SIMCTL_CHILD_LODY_UPLOAD_TEST_URL': endpoint})
                finally:
                    server.terminate()
        else:
            subprocess.run(command, check=True, timeout=300)
