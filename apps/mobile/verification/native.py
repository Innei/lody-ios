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
    'notifications': ['Notifications/PushPermissionLaunchRequest.swift', 'Notifications/PushClickBuffer.swift'],
    'file-link': ['Chat/ChatFileLink.swift'],
    'strings': ['LodyStrings.swift'],
    'chat': ['LodyStrings.swift', 'Chat/ChatTranscript.swift', 'Chat/ChatStream.swift', 'Chat/ChatTextFade.swift', 'Chat/ChatHaptics.swift'],
    'watchdog': ['Cloud/RuntimeHealth.swift'],
    'local-store': ['Cloud/LocalStore.swift'],
    'content-store': ['Cloud/ContentStore.swift'],
    'chat-render': ['LodyStrings.swift', 'LodyTint.swift', 'UIFont+Dynamic.swift', 'Chat/ChatTranscript.swift', 'Chat/ChatTextView.swift', 'Chat/ChatTextFade.swift', 'Chat/ChatThrowCurve.swift', 'Chat/ChatAttachments.swift', 'Chat/ChatSendHandoff.swift', 'Chat/ChatCell.swift'],
    'model-panel': ['LodyStrings.swift', 'UIFont+Dynamic.swift', 'Chat/ChatComposerModelPanel.swift'],
    'composer': ['LodyStrings.swift', 'UIFont+Dynamic.swift', 'Chat/ChatAttachments.swift', 'Chat/ChatAttachmentSheet.swift', 'Chat/ChatComposerSurfaceLayout.swift', 'Chat/ChatComposerLegacySurfaceLayout.swift', 'Chat/ChatComposerLiquidGlassSurfaceLayout.swift', 'Chat/ChatMentionPanel.swift', 'Chat/ChatComposerModelPanel.swift', 'Chat/ChatComposerView.swift', 'Chat/ChatTranscript.swift', 'Chat/ChatSendHandoff.swift', 'Chat/ChatTextView.swift', 'Chat/ChatTextFade.swift', 'Chat/ChatThrowCurve.swift', 'LodyTint.swift'],
    'attachments': ['LodyStrings.swift', 'Cloud/SessionAttachments.swift'],
    'inline-diff': ['UIFont+Dynamic.swift', 'Diff/InlineDiffModel.swift', 'Diff/InlineDiffRenderer.swift'],
    'list': [
        'Chrome/LodyMenuButtonStyle.swift',
        'List/LodyListCellBackground.swift',
        'List/LodyListPhoto.swift',
        'List/LodySessionRowView.swift',
    ],
    'banner': [
        'LodyStrings.swift',
        'Toast/LodySessionBannerView.swift',
    ],
    'chat-title': ['Chat/ChatNavigationTitle.swift'],
    'live-activity': ['../live-activity/LodyActivityAttributes.swift', '../live-activity/LiveActivityCatalog.swift'],
    'page-progress': ['List/LodyPageProgress.swift'],
}
with tempfile.TemporaryDirectory(prefix='lody-native-verify-') as output:
    shader_bundle = Path(output) / 'LodyKitShaders.bundle'
    shader_bundle.mkdir()
    air = str(Path(output) / 'ChatEffortParticles.air')
    subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'metal', '-c', '-target', 'air64-apple-ios16.4-simulator', '-isysroot', sdk, str(kit / 'ios/Chat/Shaders/ChatEffortParticles.metal'), '-o', air], check=True, timeout=120)
    subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'metallib', air, '-o', str(shader_bundle / 'default.metallib')], check=True, timeout=120)
    for name, files in checks.items():
        binary = str(Path(output) / name)
        simulator = name in ['model-panel', 'chat-render', 'composer', 'attachments', 'inline-diff', 'list', 'banner', 'chat-title', 'live-activity']
        command = ['xcrun', '--sdk', 'iphonesimulator', 'swiftc'] if simulator else ['xcrun', 'swiftc']
        command += ['-swift-version', '6']
        if simulator:
            arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
            ios = '26.0' if name == 'chat-title' else '18.0'
            command += ['-sdk', sdk, '-target', f'{arch}-apple-ios{ios}-simulator']
        if name == 'attachments':
            command += ['-parse-as-library']
        if name == 'inline-diff':
            command += ['-framework', 'UIKit']
        if name == 'local-store':
            command += ['-lsqlite3']
        command += [str(kit / 'ios' / file) for file in files]
        command += [str(kit / 'verification' / name / 'main.swift'), '-o', binary]
        subprocess.run(command, check=True, timeout=120)
        # A cold CI Simulator draws its first text far slower than a warm local one.
        subprocess.run(['xcrun', 'simctl', 'spawn', args.udid, binary] if simulator else [binary], check=True, timeout=300)
