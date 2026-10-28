#!/bin/bash
set -euo pipefail

ios_directory="${1:?Usage: verify-ios-build-mode.sh <ios-directory>}"
pods_directory="$ios_directory/Pods"
if [ ! -d "$pods_directory" ]; then
  echo "::error::CocoaPods directory does not exist: $pods_directory" >&2
  exit 1
fi
for pod in "$pods_directory"/{React*,Expo*,expo-*,hermes*,Yoga,RNScreens,RNReanimated}; do
  if [ -e "$pod" ]; then
    echo "::error::React Native dependency in standalone native build: $pod" >&2
    exit 1
  fi
done
echo 'Standalone native CocoaPods dependencies verified.'
