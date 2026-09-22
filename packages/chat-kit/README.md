# ChatKit

An iOS Swift package extracted from Lody's native chat implementation. Requires
iOS 26 or later and Swift 6. This package is under active migration and its API
is not yet stable.

## Available components

- `CKTextReveal`: presentation pacing for one text block, including
  authoritative text corrections, explicit completion and Unicode input.
- `CKTextView`: attributed-text rendering with streaming fades, shimmer,
  measurement and link actions. This is a TextKit view, not a Markdown parser.
- `CKAttachmentStrip`: display-only attachment pills with preview/remove callbacks,
  stable identity, reordering, removal transitions and per-instance styles.
- `CKGlassSurface`: the reversible native material transition used by the strip
  and Lody's existing native controls.

The complete transcript collection view, Markdown renderer, Composer and
cross-screen send handoff still live in LodyKit. They have not yet been extracted.

## Integration

Add this directory as a local Swift package in Xcode and link the `ChatKit`
product. The product includes the Foundation-only `ChatKitCore` target and
the UIKit target. Neither target depends on Expo or Lody services. Public types use the `CK`
prefix. Import `ChatKit` for UIKit components and `ChatKitCore` for
Foundation presentation state; no compatibility type aliases or re-export files
are provided.

```swift
import ChatKit
import UIKit

var theme = CKTheme.system
theme.textColor = .systemIndigo

var style = CKAttachmentStyle(theme: theme)
style.font = .systemFont(ofSize: 15, weight: .medium)
style.cornerRadius = 10
style.maximumWidth = 240

let attachments = CKAttachmentStrip(style: style)
attachments.onPreview = { id in /* Open the host's preview. */ }
attachments.onRemove = { id in /* Update the host's draft, then render it. */ }
attachments.render([
  CKAttachmentItem(id: "notes", name: "Notes.txt")
])
```

The host supplies a frame or layout constraints for the strip. Its height must
accommodate `style.height`. Attachment IDs must be unique within a strip. Provide
prepared, display-sized thumbnails and localized accessibility labels in each
`CKAttachmentItem`; the package does not read files or initiate downloads.

Assign a new `style` to update an existing strip. Callbacks and item identity are
retained; typography changes rebuild pill measurements. Styles are instance-local
and accept dynamic UIKit colors. Removal is an intent callback: only the host's
next `render` removes an item.

```swift
import ChatKitCore

var reveal = CKTextReveal()
reveal.receive("An incoming reply", animate: true, at: 1)
reveal.advance(at: 1.016)

let text = CKTextView()
text.setText(NSAttributedString(
  string: reveal.shown,
  attributes: [.font: UIFont.preferredFont(forTextStyle: .body)]
), animate: true)
```

Use a monotonic clock for successive receive/advance calls. The host drives
presentation ticks and supplies source text, while the text view owns redraws for
its glyph animation. Call `finish()` when an immediate display flush is required.
This does not mark a server request complete or trigger retries.

## Verification during migration

From the Lody workspace, `pnpm verify:native --case chat-kit` compiles and
executes `Verification/main.swift` as a downstream consumer using public imports.
It covers style isolation, font remeasurement, reordering, callbacks, removal and
stream corrections. Existing chat/Composer checks also link these package sources.
Core Swift Testing cases are in `Tests/ChatKitCoreTests`; use an iOS Simulator
test destination because the package product includes UIKit.

This source retains the repository's AGPL-3.0-only license. A different publication
license has not been selected.
