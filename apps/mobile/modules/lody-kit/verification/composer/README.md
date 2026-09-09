# Shared native composer

Run from the repository root with a booted iOS Simulator:

```sh
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios18.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  apps/mobile/modules/lody-kit/ios/UIFont+Dynamic.swift \
  apps/mobile/modules/lody-kit/ios/Chat/ChatAttachments.swift \
  apps/mobile/modules/lody-kit/ios/Chat/ChatAttachmentSheet.swift \
  apps/mobile/modules/lody-kit/ios/Chat/ChatComposerSurfaceLayout.swift \
  apps/mobile/modules/lody-kit/ios/Chat/ChatComposerLegacySurfaceLayout.swift \
  apps/mobile/modules/lody-kit/ios/Chat/ChatComposerLiquidGlassSurfaceLayout.swift \
  apps/mobile/modules/lody-kit/ios/Chat/ChatComposerView.swift \
  apps/mobile/modules/lody-kit/verification/composer/main.swift \
  -o /tmp/lody-composer-test
xcrun simctl spawn booted /tmp/lody-composer-test
```

Exercises the production UIKit input without cloud writes: empty input, duplicate
send suppression, rejected-draft restoration, accepted-draft clearing, multiline
height limiting, and uncertain-result locking.
