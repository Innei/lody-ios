# Scroll edge ownership

`Shared/UIKit/Chrome/LodyScrollEdges.swift` owns the shared scroll-edge policy.
Controllers register their real UIKit scroll views with `setContentScrollView`.
UIKit renders the effects and owns keyboard geometry and edge shape.

| API                      | Behavior                                                         |
| ------------------------ | ---------------------------------------------------------------- |
| `navigation` / `grouped` | Soft top and bottom effects                                      |
| `chat`                   | Automatic top effect; bottom initially hidden                    |
| `floatingControls`       | Visible, soft bottom effect for an attached floating control     |
| `bind`                   | Publishes a scroll view as the controller's top and bottom owner |
| `unbind`                 | Clears only edges still registered to that exact scroll view     |

`ChatComposerView.attachScrollEdge` applies the floating-control policy to its
current target. `LodyPagedList` publishes the visible page's collection view and
releases matching registrations when it detaches. The `PageContainerController`
forwards its child's scroll ownership to the navigation container when notified.

Controllers live in `iOS/ViewControllers` or `Shared/UIKit/ViewControllers`;
scroll policy stays in the shared UIKit layer. The active source/document scroll
view and grouped lists register directly. Horizontal code/table scrolling,
attachment strips, input scrolling, image zoom and context previews do not own
page navigation chrome. The offscreen data-runtime WebView is outside this policy.

## Verification

`pnpm verify:native --case scroll-edges` exercises nested ownership, replacement
and guarded cleanup. `--case composer` checks floating-control attachment,
replacement and detachment. UI coverage is in `scroll-edge-pages`,
`scroll-edge-diff` and the affected host cases in `verification/ui`.

Use a freshly built signed Simulator app, both appearances and the software
keyboard. Review screenshots and temporal evidence; a style property or a
successful build alone does not establish visual correctness. See
[`verification/ui/README.md`](../verification/ui/README.md) for the runner rules.
