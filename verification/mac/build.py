"""Build the Lody Mac app (Debug by default) and print the .app path."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / 'Lody.xcodeproj'
LOG = ROOT / '.artifacts/mac-build/build.log'

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--configuration', default='Debug')
parser.add_argument('--adhoc', action='store_true', help='Sign ad hoc, for CI runners without a development certificate')
args = parser.parse_args()

if not PROJECT.is_dir():
    subprocess.run(['pnpm', 'prebuild'], cwd=ROOT, check=True)
command = ['xcodebuild', '-project', str(PROJECT), '-scheme', 'LodyMac', '-configuration', args.configuration,
           '-destination', 'platform=macOS']
if args.adhoc:
    command += ['CODE_SIGN_STYLE=Manual', 'CODE_SIGN_IDENTITY=-', 'DEVELOPMENT_TEAM=']
LOG.parent.mkdir(parents=True, exist_ok=True)
with LOG.open('w') as log:
    result = subprocess.run(command + ['build'], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    errors = [line for line in LOG.read_text().splitlines() if 'error:' in line]
    sys.stderr.write('\n'.join(errors[-20:]) + f'\nMac build failed; log {LOG}\n')
    raise SystemExit(result.returncode)
settings = subprocess.run(command + ['-showBuildSettings'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
values = dict(line.strip().partition(' = ')[::2] for line in settings.splitlines() if ' = ' in line)
print(Path(values['BUILT_PRODUCTS_DIR']) / values['FULL_PRODUCT_NAME'])
