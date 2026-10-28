"""Reproduce the native Xcode project without Expo or React Native."""
from pathlib import Path
import json
import os
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
ios = root / 'ios'
ios.mkdir(exist_ok=True)
# Extensions and release signing read the generated plist beside the project.
(ios / 'Lody').mkdir(exist_ok=True)
info = plistlib.loads((root / 'native/Lody/Info.plist').read_bytes())
info['CFBundleShortVersionString'] = json.loads((root / 'package.json').read_text())['version']
info['CFBundleVersion'] = os.environ.get('BUILD_NUMBER', info['CFBundleVersion'])
if 'LODY_ONESIGNAL_APP_ID' in os.environ:
    info['LodyOneSignalAppId'] = os.environ['LODY_ONESIGNAL_APP_ID']
(ios / 'Lody/Info.plist').write_bytes(plistlib.dumps(info))

shutil.copy2(root / 'native/Lody/Localizable.xcstrings', ios / 'Lody/Localizable.xcstrings')
shutil.copy2(root / 'native/Podfile', ios / 'Podfile')
subprocess.run(['xcodegen', 'generate', '--spec', str(root / 'native/project.yml'), '--project', str(ios)], check=True)
