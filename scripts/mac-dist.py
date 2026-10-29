"""Archive the Lody Mac app with Developer ID, package a signed .dmg, and optionally notarize it."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'Lody.xcodeproj'
OUT = ROOT / '.artifacts/mac-dist'
TEAM = 'KAMM5N88X3'
IDENTITY = f'Developer ID Application: Yuhao Jiang ({TEAM})'

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--notary-profile', help='notarytool keychain profile; omit to stop before notarization')
args = parser.parse_args()


def run(command, log=None):
    if log is None:
        subprocess.run(command, cwd=ROOT, check=True)
        return
    with log.open('w') as handle:
        result = subprocess.run(command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT)
    if result.returncode:
        errors = [line for line in log.read_text().splitlines() if 'error:' in line]
        sys.stderr.write('\n'.join(errors[-20:]) + f'\nfailed; log {log}\n')
        raise SystemExit(result.returncode)


# Gatekeeper may be disabled on the build Mac, which makes spctl accept anything; the source line still names the ticket.
def assess(*command):
    result = subprocess.run(['spctl', *command], capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    print(output)
    return result.returncode == 0 and 'source=Notarized Developer ID' in output


if not PROJECT.is_dir():
    run(['pnpm', 'prebuild'])
shutil.rmtree(OUT, ignore_errors=True)
OUT.mkdir(parents=True)
archive = OUT / 'Lody.xcarchive'
run(['xcodebuild', '-project', str(PROJECT), '-scheme', 'LodyMac', '-configuration', 'Release',
     '-destination', 'generic/platform=macOS', '-archivePath', str(archive), 'archive'], OUT / 'archive.log')
options = OUT / 'ExportOptions.plist'
options.write_bytes(plistlib.dumps({'method': 'developer-id', 'teamID': TEAM, 'signingStyle': 'automatic'}))
export = OUT / 'export'
run(['xcodebuild', '-exportArchive', '-archivePath', str(archive), '-exportPath', str(export),
     '-exportOptionsPlist', str(options)], OUT / 'export.log')
app = export / 'Lody.app'
run(['codesign', '--verify', '--deep', '--strict', str(app)])
flags = subprocess.run(['codesign', '-dv', str(app)], capture_output=True, text=True).stderr
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if 'runtime' not in flags or 'CFBundleURLTypes' in info:
    raise SystemExit('Release app must use the hardened runtime and register no URL schemes')

staging = OUT / 'dmg'
staging.mkdir()
shutil.copytree(app, staging / 'Lody.app', symlinks=True)
(staging / 'Applications').symlink_to('/Applications')
dmg = OUT / 'Lody.dmg'
run(['hdiutil', 'create', '-quiet', '-volname', 'Lody', '-srcfolder', str(staging), '-ov', '-format', 'UDZO', str(dmg)])
run(['codesign', '--sign', IDENTITY, '--timestamp', str(dmg)])

print(dmg)
if not args.notary_profile:
    print('signed, not notarized: pass --notary-profile to notarize and staple')
    raise SystemExit(0)
run(['xcrun', 'notarytool', 'submit', str(dmg), '--keychain-profile', args.notary_profile, '--wait'])
run(['xcrun', 'stapler', 'staple', str(dmg)])
run(['xcrun', 'stapler', 'validate', str(dmg)])
raise SystemExit(0 if assess('-a', '-vv', '-t', 'open', '--context', 'context:primary-signature', str(dmg)) else 1)
