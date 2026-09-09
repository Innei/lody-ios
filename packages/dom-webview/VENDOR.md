# Vendored from `@expo/dom-webview`

Source: `@expo/dom-webview@57.0.1` from the `expo@57` line (upstream
[`expo/expo`](https://github.com/expo/expo), `packages/@expo/dom-webview`).

`pnpm-workspace.yaml` resolves `@expo/dom-webview` to
`link:./packages/dom-webview` via `overrides`. `expo` still lists the package
as a regular dependency, so without that override Metro would silently use
Expo's nested copy. `DomWebViewModule`'s `vendor` constant and
`assertVendoredDomWebView()` catch a resolution regression.

## Changes vs. upstream 57.0.1

- Android removed (`android/`, `local-maven-repo/`, the `android` block in
  `expo-module.config.json`).
- `SharedDiffWebView` retains one Diff `DomWKWebView` and moves it between the
  root warmer and `FileDiffScreen`. The `shared` prop is opt-in.
- Shared instances use `WKWebsiteDataStore.nonPersistent()`, allow only the
  packaged DOM file URL (plus the current Metro DOM URL in DEBUG), reset source
  on park, discard on parked WebContent death or memory warning, and refuse to
  steal a foreground host.
- `resetupScripts()` rebinds the script message handler only when ownership
  changes. A reused document does not navigate the bundle again.
- Debug probe: anonymous `instanceId` / `navigationCount` on the shared
  WebView. Source text never enters the probe.
- `Constants(["vendor": "lody"])` for the resolution self-check.
- `allowingReadAccessToURL` added to `UnsupportedWebViewProps` so Expo's
  wrapper can pass it.
- Upstream `devDependencies` (`expo`, `expo-module-scripts`) dropped so this
  package cannot install a second `expo`. `test` runs vitest.

Bumping `expo` does not bump this package. Re-diff against a new
`@expo/dom-webview` release and re-apply the changes above. The Expo wrapper
contract test fails if `expo/src/dom/webview-wrapper.tsx` starts passing a
prop or calling a ref method this package does not declare.
