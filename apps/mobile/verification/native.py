"""Compile and run existing production Swift behavior checks without credentials."""
import argparse
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
kit = root / 'apps/mobile/modules/lody-kit'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--udid', required=True)
args = parser.parse_args()
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
checks = {
    'strings': ['LodyStrings.swift'],
    'chat': ['LodyStrings.swift', 'Chat/ChatTranscript.swift', 'Chat/ChatStream.swift', 'Chat/ChatTextFade.swift'],
    'watchdog': ['Cloud/RuntimeHealth.swift'],
    'local-store': ['Cloud/LocalStore.swift'],
    'content-store': ['Cloud/ContentStore.swift'],
    'chat-render': ['Chat/ChatTextView.swift', 'Chat/ChatTextFade.swift'],
    'composer': ['LodyStrings.swift', 'UIFont+Dynamic.swift', 'Chat/ChatAttachments.swift', 'Chat/ChatAttachmentSheet.swift', 'Chat/ChatComposerView.swift', 'Chat/ChatTranscript.swift', 'Chat/ChatSendHandoff.swift', 'Chat/ChatTextView.swift', 'Chat/ChatTextFade.swift', 'LodyTint.swift'],
    'attachments': ['LodyStrings.swift', 'Cloud/SessionAttachments.swift'],
    'diff-font': ['Diff/DiffWebTypography.swift'],
}
with tempfile.TemporaryDirectory(prefix='lody-native-verify-') as output:
    for name, files in checks.items():
        binary = str(Path(output) / name)
        simulator = name in ['chat-render', 'composer', 'attachments', 'diff-font']
        command = ['xcrun', '--sdk', 'iphonesimulator', 'swiftc'] if simulator else ['xcrun', 'swiftc']
        if simulator:
            arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
            command += ['-sdk', sdk, '-target', f'{arch}-apple-ios18.0-simulator']
        if name == 'attachments':
            command += ['-parse-as-library']
        if name == 'diff-font':
            command += ['-framework', 'WebKit']
        if name == 'local-store':
            command += ['-lsqlite3']
        command += [str(kit / 'ios' / file) for file in files]
        command += [str(kit / 'verification' / name / 'main.swift'), '-o', binary]
        subprocess.run(command, check=True, timeout=120)
        subprocess.run(['xcrun', 'simctl', 'spawn', args.udid, binary] if simulator else [binary], check=True, timeout=120)
