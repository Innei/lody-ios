#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
OUT=.artifacts/inspection-model
mkdir -p "$OUT"
FRAMEWORKS="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
LIBRARY="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib"
xcrun swiftc -I "$LIBRARY" -L "$LIBRARY" -F "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$LIBRARY" macOS/Models/Inspection/MacInspectionState.swift verification/mac/Tests/MacInspectionStateTests.swift verification/kit/inspection/main.swift -o "$OUT/check"
"$OUT/check"
