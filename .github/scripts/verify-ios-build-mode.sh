#!/bin/bash

set -euo pipefail

ios_directory="${1:?Usage: verify-ios-build-mode.sh <ios-directory>}"
pods_directory="$ios_directory/Pods"

if [ ! -d "$pods_directory" ]; then
  echo "::error::CocoaPods directory does not exist: $pods_directory" >&2
  exit 1
fi

expo_precompiled=""
for framework in ExpoModulesCore ExpoModulesWorklets; do
  candidate="$pods_directory/$framework/$framework.xcframework"
  if [ -d "$candidate" ]; then
    expo_precompiled="$candidate"
    break
  fi
done

react_prebuilt="$pods_directory/React-Core-prebuilt/React.xcframework"
if [ -n "$expo_precompiled" ] && [ ! -d "$react_prebuilt" ]; then
  echo "::error::Mixed native build: Expo modules are precompiled, but React Native fell back to a source build." >&2
  echo "::error::Found $expo_precompiled without $react_prebuilt." >&2
  exit 1
fi

if [ -n "$expo_precompiled" ]; then
  echo "Compatible precompiled Expo and React Native build detected."
else
  echo "Expo modules are building from source; no mixed native build detected."
fi
