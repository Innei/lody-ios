# Shared native composer

Run from the repository root; the runner leases a verification Simulator:

```sh
pnpm verify:native
```

Exercises the production UIKit input without cloud writes: empty input, duplicate
send suppression, rejected-draft restoration, accepted-draft clearing, multiline
height limiting, and uncertain-result locking.

`pnpm verify:native` also compiles the shared `.metal` source into a temporary `ComposerShaders.bundle` for the native checks. Xcode’s Metal Toolchain is required (`xcodebuild -downloadComponent MetalToolchain` if missing). App builds compile the same source from `iOS/Resources/Shaders` into the App's Metal library. The Share Extension retains its standard control rendering.
