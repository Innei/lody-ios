#!/usr/bin/env python3
import os
from pathlib import Path
import sys

COMPILE_MARK = ' in Sources */'
RESOURCE_MARK = ' in Resources */'

PODS = (
    {
        'name': 'LodyKit',
        'root': Path('apps/mobile/modules/lody-kit/ios'),
        'compile': {'.swift', '.m'},
        'resources': {'.metal'},
    },
    {
        'name': 'ExpoDomWebView',
        'root': Path('packages/dom-webview/ios'),
        'compile': {'.swift', '.m'},
        'resources': set(),
    },
)


def repo_root() -> Path:
    start = Path(os.environ.get('PODS_TARGET_SRCROOT') or os.getcwd()).resolve()
    for candidate in [start, *start.parents]:
        if (candidate / 'pnpm-workspace.yaml').is_file():
            return candidate
    sys.stderr.write('Could not find the lody-ios workspace root.\n')
    sys.exit(2)


def project_path(root: Path) -> Path:
    env = os.environ.get('PROJECT_FILE_PATH')
    if env:
        return Path(env)
    return root / 'apps/mobile/ios/Pods/Pods.xcodeproj/project.pbxproj'


def sources(directory: Path, suffixes: set[str]) -> list[Path]:
    if not suffixes:
        return []
    return sorted(
        path
        for path in directory.rglob('*')
        if path.is_file() and path.suffix in suffixes
    )


def linked(project: str, filename: str, mark: str) -> bool:
    return f'{filename}{mark}' in project


def main() -> int:
    root = repo_root()
    project_file = project_path(root)
    if not project_file.is_file():
        return 0
    project = project_file.read_text()
    missing: list[str] = []
    for pod in PODS:
        directory = root / pod['root']
        if not directory.is_dir():
            missing.append(f"{pod['name']}: source directory {pod['root']} is missing")
            continue
        for path in sources(directory, pod['compile']):
            if not linked(project, path.name, COMPILE_MARK):
                missing.append(f"{pod['name']} compile: {path.relative_to(directory)}")
        for path in sources(directory, pod['resources']):
            if not linked(project, path.name, RESOURCE_MARK):
                missing.append(f"{pod['name']} resources: {path.relative_to(directory)}")
    if not missing:
        return 0
    sys.stderr.write(
        'Native sources are missing from Pods.xcodeproj. Run: pnpm --filter @lody-ios/mobile pods\n'
    )
    for item in missing:
        sys.stderr.write(f'  {item}\n')
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
