# iPhone Duo: UIKit and React Native notes

What we verified while adapting Lody to iPhone Duo (iOS 27.1 / 27.2 SDK, simulator
`iPhone Duo`). Shipped in `5333e6a`. Re-verify on newer SDKs before relying on details
marked as simulator behavior.

## Device facts

| Posture                | Window       | Size class | Lody layout      |
| ---------------------- | ------------ | ---------- | ---------------- |
| Folded (outer display) | 466 × 678 pt | compact    | compact (iPhone) |
| Unfolded, landscape    | 951 × 669 pt | regular    | wide             |
| Unfolded, portrait     | 669 × 951 pt | regular    | tall             |

- The idiom stays `.phone` on every display. Pick layouts by size class or width,
  never by `Platform.isPad` / `userInterfaceIdiom`.
- Unfolded landscape has a vertical fold at x 455.5–495.5 (40 pt including margins).

## Vertical bar

On the outer display, and on the inner display in landscape, iOS moves bar items into
a vertical bar on the trailing edge. The status bar becomes vertical too.

- The window's safe area includes the bar (right inset 84 pt in landscape). Anything
  pinned to the view edges instead of `safeAreaLayoutGuide` runs under it. Ordinary
  iPhones have zero horizontal insets, so this never shows up there.
- In a `UISplitViewController`, only the detail column uses the vertical bar, and an
  expanded inspector keeps horizontal bars (Apple tech talk "Raise the bar with iPhone
  Duo"). This works natively, including when the split is nested under a plain VC.
- The vertical bar collects trailing items from every navigation bar in the window,
  **including hidden ones**. Items that land on a hidden bar still render in the
  vertical bar and overlap real ones.
- `preferredVerticalBarBehavior = .disabled` opts a screen out, but Apple meant it for
  control-heavy screens. It doesn't fix multi-column layouts.

## Fold detection

- `window.reservedRegions(kind: .division, options: .includeInactive)` returns the
  fold (`{455.5, 0, 40, 669}`). It reports `active == false` while the device is fully
  open, so the option is required.
- The regions are empty during early layout, and nothing notifies when they appear.
  Don't drive layout from them at mount time.
- `UIHingeInteraction` is event-driven: its handler fires with the initial state and on
  every change (`status` 3 = fully open). Use it to decide whether a fold exists, and
  combine it with the layout mode, since portrait has a horizontal fold.
- `UIView.reservedRegions(kind: .occlusion)` includes the status-bar column of the
  vertical bar. The safe area already covers it.

## Two panes at the fold

`UIArrangementViewController` with `updateArrangement(.split)` and two
`setViewController(_:for: .primary / .secondary)` calls splits exactly at the hinge
(475.67 | 475.33 pt). The trailing pane gets the vertical bar; the leading pane keeps
its own horizontal bar.

Lody's `LodySplitView` uses it only when the layout is wide and the hinge is open. iPad
keeps `UISplitViewController`.

- The arrangement has only two slots, so the wide layout maps list | chat, or chat |
  panel once a panel is open.
- The hidden third column is parked under a hidden child VC. A react-native-screens
  navigation controller with no parent gets re-adopted by its RN stack into the outer
  Router controller.

## SDK guard

The arrangement, hinge and reserved-region APIs exist only in the Xcode-beta 27.2
SDK. `canImport(UIKit.UIArrangementViewController)` is false on both SDKs (it is not a
separate Clang submodule). Guard with the toolchain version instead:

```swift
#if compiler(>=6.4.2)
if #available(iOS 27.1, *) { … }
#endif
```

Xcode 27.0 builds compile the guarded code out and keep the plain split. Swift 6:
don't capture a `@convention(c)` pointer inside `MainActor.assumeIsolated`.

## React Native pitfalls

These showed up on the Duo, but most are host or layout bugs that ordinary iPhones hid.

- **expo-router composition options are route-scoped.** `Stack.Toolbar
placement="left" | "right"`, `Stack.SearchBar` and `Stack.Screen` options register on
  `useRoute().key`. In a host that isn't a route (the side panel), they attach to the
  enclosing route, usually a hidden index screen, and the vertical bar then shows them.
  In such hosts, use LodyKit's `NativeNavigationHeader`. It writes to the screen's own
  `UINavigationItem`.
- **Bottom `Stack.Toolbar`** finds its controller through the view tree, so it works in
  any host.
- **react-native-screens root replacement animates as a pop by default.** Set
  `replaceAnimation="push"` on `ScreenStackItem`s whose root gets replaced (panel
  content, first chat after the placeholder).
- **A hidden header keeps a stale search controller.** `RNSScreenStackHeaderConfig`
  returns early when the header is hidden, before clearing `navitem.searchController`.
  After the compact inbox's integrated search hands the route to the wide layout, the
  search stays in the bottom bar. Fixed in `patches/react-native-screens@4.30.0.patch`.
- **RN views hosted in bar items drift.** `Stack.Toolbar.View` wraps an RN view as a
  `UIBarButtonItem.customView`. On the Duo its frame landed about 10 pt off and the
  button stopped receiving taps. Prefer native `Stack.Toolbar.Button`.
- **Overlay windows.** Lody's toast window used to set its canvas frame from the window
  bounds and then rely on autoresizing. When the window was first created on another
  display size, the difference stayed baked in (canvas 1436 pt wide in a 951 pt
  window). Pin overlay content with Auto Layout.
- **Toast placement:** center within the safe area, and on an open fold, over the
  trailing pane rather than across the hinge.

## Where it lives

| Concern                              | File                                                                                                  |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| Layout mode (compact / wide / tall)  | `apps/mobile/src/lib/presentation/layoutMode.ts`, `modules/lody-kit/ios/Chrome/LodyLayoutProbe.swift` |
| Split shell, fold switching, parking | `modules/lody-kit/ios/Chrome/LodySplitView.swift`                                                     |
| Arrangement and hinge (SDK-guarded)  | `modules/lody-kit/ios/Chrome/LodyFoldHost.swift`                                                      |
| Panel stack and store                | `apps/mobile/src/lib/presentation/PanelStack.tsx`, `panelStore.ts`                                    |
| Chat horizontal safe area            | `modules/lody-kit/ios/Chat/LodyChatView.swift`                                                        |
| Toast band and canvas                | `modules/lody-kit/ios/Toast/LodyToastOverlay.swift`                                                   |
| Design decisions                     | `docs/superpowers/specs/2026-10-17-wide-layout-design.md`                                             |

## Testing on the Duo simulator

- Build with Xcode-beta and the 27.2 SDK (`DEVELOPER_DIR=/Applications/Xcode-beta.app/…`,
  `-sdk iphonesimulator27.2`) to compile the fold code. Default Xcode builds run but
  never fold.
- Screenshots: `xcrun simctl io <udid> screenshot --display 3` (inner) or `--display 1`
  (outer). A black image means that display is off in the current posture.
- `axe` taps land transposed on the Duo, and `axe` has no display option. Folding,
  rotating and most taps have to be done by hand in DeviceHub.
- Open a session without taps: `xcrun simctl openurl <udid>
lody://<workspace>/sessions/<sessionId>`.
- To read runtime values, log with a unique prefix and stream
  `xcrun simctl spawn <udid> log stream --predicate 'eventMessage CONTAINS "PREFIX"'`.
  Don't attach LLDB to the simulator app: it waited on authorization and left the
  simulator wedged until a reboot.
- A standalone xcodegen spike under `/tmp` (plain UIKit, no RN) separated UIKit
  behavior from RN-host bugs quickly. Compare root vs nested under a plain VC.
- On iOS 27 runtimes, `axe swipe` doesn't trigger UIKit's interactive pop; use
  `axe drag` for edge-swipe back in verify scripts.
