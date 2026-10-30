# ChatKit shared transcript core (iOS + Mac)

Status: approved design (2026-10-30). Builder: work from this file; the TL;DR beside it is for review only.

## Intent

The Mac client's transcript is an `NSStackView` that builds every row of a session at once, re-places them on every update, and shows images and attachments as a one-line "paperclip + file names" label. Long sessions are slow, there is no "load earlier history", and you cannot attach anything from the Mac composer. iOS already solved paging, anchoring, height caching and attachments, but inside `LodyChatView`, a UIKit monolith (~2,400 lines with `+Transcript` / `+Scroll`) that mixes list mechanics with Lody business.

The user chose to make `ChatKit` (`packages/chat-kit`) the **shared transcript core for both platforms** (option B, not a Mac-only shortcut), so iOS and Mac page, anchor, follow the bottom and cache heights the same way and fixes land once.

Success: on Mac, a 10,000-entry session opens showing its latest page, scrolling to the top loads earlier pages without the reader's position jumping, images show inline, and files can be attached by picker, paste or drag. On iOS nothing visibly changes, and every existing chat UI check still passes, but its list mechanics now come from `ChatKitCore`.

## Goals

1. `ChatKitCore` (Foundation + CoreGraphics only, both platforms) gains the list mechanics, unit-tested:
   - row diff
   - history window
   - height cache
   - follow-bottom state
   - scroll anchor
   - scroll motion
   - offscreen stream deferral
   - prepare-budget loop
   - media-provider protocol
   - attachment model
2. A new AppKit target in the ChatKit package (`ChatAppKit`, named by the user) with:
   - an `NSTableView`-based transcript container driven by the Core
   - a history header
   - an AppKit attachment strip
3. The Mac transcript moves onto `ChatAppKit` and gains:
   - history paging
   - inline message images
   - attachment display
   - composer attachments (pick, paste, drag) sent through the existing upload path
4. iOS `LodyChatView` replaces its hand-rolled mechanics with the same Core types, with behaviour unchanged.

## Non-goals

- Moving Markdown rendering, message cells or the composer into ChatKit. ChatKit does not know what a "plan", "delivery" or "subagent" is.
- Other Mac features from the gap list:
  - stop / steer, `ask_user_question`, plan approval
  - diff and tool detail pages, find in transcript, edit message, @-mentions, quick replies
- A public, stable or published ChatKit API. The package stays internal-grade, with the `CK` prefix and no compatibility aliases.
- Visual redesign of iOS chat. The chat-polish work in `lody-ios-bb` owns iOS chat visuals.

## Anti-goals

- iOS regresses in any measured way, including streaming fades, the reader drifting during sync, history inserts during an active scroll, or send landing. Any red existing check blocks phase 3.
- A shared layer built from `#if canImport(UIKit)` views or a `PlatformView` alias. Shared code is logic only; each platform keeps native views.
- ChatKit importing LodyData, Lody strings or Lody services, or the Core branching on Lody kind strings (`"user"`, `"delivery"`, `"duration"`). Lody passes those decisions in as values or closures.
- Mac paging that still instantiates every row view (the point is that only visible rows plus a small buffer exist).

## Decisions (from the conversation)

| Question | Decision |
|---|---|
| Mac-only shortcut vs shared core | **B: shared core for iOS and Mac** |
| Row model at the ChatKit boundary | **A: ChatKit owns list mechanics only.** A row is an id + version + Lody-supplied neighbour key and grouping; cells are registered by the host. `CKTextView` stays an optional primitive, not a mandated cell. `lody-ios-bb` agreed. |
| Order | **Core first → Mac → iOS** (iOS only after `lody-ios-bb` says its `LodyiOSKit/Sources/Chat` work is done) |
| Mac send landing | **Same as iOS.** The sent message settles near the top of the viewport with reserved space below it (iOS `anchoredUserID` + `updateBottomInset`, S:9-28), and the reply grows into that space. Following uses the eased `CKScrollMotion`, not a jump. Mac composer and transcript checks gain assertions for this. |
| Height cache key | Must include the **previous row's kind** (`ChatRowPadding.above(kind:previousKind:)` adds a gap that depends on it), not only id + version + width. From `lody-ios-bb`. |

No artboards or other artifacts were used for this design; it was decided in chat.

## Constraints

- **`packages/chat-kit` is a git submodule** (`https://github.com/Innei/ChatKit`). ChatKit changes are committed inside the submodule, then the Lody repo commits the new pointer. HEAD of the submodule is `6b5e0c2` (shine highlight) on top of `dcad0a5` (ChatKitCore for macOS). Both are **unpushed**: build on top of them, never rebase or rewrite them. Pushing is the user's call; when it happens, the submodule is pushed before the Lody commit that points at it.
- Another session (`lody-ios-bb`) is editing `packages/LodyiOSKit/Sources/Chat`. Phases 1–2 must not modify that folder or change any existing ChatKit public API that iOS uses. Changes there are **additive only** (new types, new targets). Phase 3 starts only after `lody-ios-bb` confirms it is done; message it first.
- Swift 6, iOS 26 / macOS 26 (already in `chat-kit/Package.swift`). `ChatKitCore` may import Foundation and CoreGraphics, nothing UI.
- Repo rules apply: zero comments unless they explain unexpected behaviour, no nested ternaries, files ≤ 500 lines (UI components ≤ 300), TDD (watch every test fail first), stage only your own paths with a scoped index, never `CODE_SIGNING_ALLOWED=NO`, Mac UI verification never on the host desktop.
- Lody kind strings stay in Lody. Where today's mechanics branch on them, the Core takes a value or closure from the host:
  - section key: `entryID`, split at `"duration"`
  - anchorable row: `"user"`
  - deferrable streaming row: `"text"` / `"thought"`

## Architecture

```
LodyData (both)   ChatEntry → ChatRow projection, ChatStream, ChatScroll, ChatReadingColumn   (unchanged)
ChatKitCore       CKRowDiff · CKHistoryWindow · CKHeightCache · CKFollowState · CKScrollAnchor
                  CKScrollMotion · CKStreamDeferral · CKPrepareBudget · CKMediaProvider · CKAttachment (model)
ChatKit (UIKit)   existing primitives + adapters used by LodyChatView in phase 3
ChatAppKit        CKTranscriptTable (NSTableView container) · CKHistoryHeaderView · CKAttachmentStripView
LodyiOSKit        LodyChatView (keeps cells, projection glue, business events) → uses Core in phase 3
LodyMacKit        MacTranscriptView → hosts CKTranscriptTable; Lody cells; media provider; composer attachments
```

### ChatKitCore types (candidate names; behaviour is binding, names are not)

All are value types or small final classes with no UI imports, each with unit tests in `Tests/ChatKitCoreTests`.

- **`CKRowDiff`.** Given the previous and next ordered rows (id + `Equatable` content) and a neighbour key per row (Lody passes the row's kind), it returns:
  - inserted, deleted and **reconfigured** ids
  - a reconfigure fires when the content changed **or the previous row's neighbour key changed**, matching `LodyChatView+Transcript.swift:391-396`
  - duplicate ids are reported as an error value, not a crash
- **`CKHistoryWindow`.** Paging over ordered group ids (Lody: `entryID`s).
  - Page size is 50 groups by default and configurable (today it is hard-coded twice, T:510/T:520).
  - The boundary is kept by group id, so live appends never move it.
  - States: idle, then preparing a target page, then committed.
  - The page commits only when every row in it is prepared **and** the host reports the scroll is not moving.
  - A width change drops prepared state.
  - Behaviour parity: `prepareHistory`, `loadEarlierHistory`, `prefetchHistoryIfNeeded` (trigger within one viewport of the top, not while following / finding / before first positioning) and `commitPreparedHistory` (T:489-594).
- **`CKHeightCache`.** Height by key = (row id, content version, width, previous-row neighbour key), plus a separate trait/appearance generation that clears everything.
  - It is pruned to retained ids.
  - It stores only heights > 0.5 (today's rule).
  - It replaces the `measurements` dictionary semantics (S:402-410) and the `preparedHistory` bookkeeping.
- **`CKPrepareBudget`.** The sliced preparation loop: measure rows until a time budget (4 ms default) is spent, then yield.
  - It is driven by an injected clock and scheduler so tests are deterministic.
  - Parity: `prepareHistorySlice` (T:565-594) runs on main.
- **`CKFollowState`.** The follow-bottom state machine as events → state.
  - Events: send (non-queued), new anchorable row while awaiting it, jump-to-bottom, drag/deceleration ended within 1 pt of the bottom, live turn started within `resumeDistance` (80) while not gesture-paused, and pause (drag began, scroll-to-top, expand, gallery, find, history load, edited-message scroll).
  - Parity: V:180-210, S:196-202, S:260-265, T:301-306.
  - The motion itself stays in LodyData `ChatScroll`.
- **`CKScrollAnchor`.** Captures `(row id, rowMinY − offset)` for the first surviving visible row before a change, then computes the target offset after layout.
  - It skips the restore while the top is rubber-banding and reports the residual error.
  - Parity: T:320-326, S:354-361, S:413-418.
- **`CKScrollMotion`.** The follow-bottom spring and eased send motion, a copy of LodyData `ChatScroll` (`ChatStream.swift:117-132`, about 15 lines of math).
  - It has to live in the Core: ChatKit cannot import LodyData, because LodyData already depends on ChatKitCore.
  - During phases 1–2 the LodyData copy stays, because the iOS Chat folder uses it and is off-limits. Phase 3 switches iOS to `CKScrollMotion` and deletes `ChatScroll` from LodyData. (My call: about 15 lines duplicated temporarily.)
- **`CKStreamDeferral`.** Decides which streaming groups are frozen while offscreen, given row frames, the viewport and the 80/160 pt hysteresis. The host supplies which rows are deferrable (Lody: `text` / `thought`).
  - Parity: `updateDeferredStreams` (S:205-238); its output feeds `ChatStream.receive(... deferredEntries:)`.
  - Mac uses it so that streaming while scrolled up doesn't move the reader. (My call: a ninth Core type.)
- **`CKMediaProvider`.** An async protocol through which the host returns images:
  - `image(for: CKMediaRef, pixelSize: CGSize) async throws -> CGImage`
  - plus a full-size file URL request for preview
  - ChatKit never builds Lody URLs or touches the network. Lody implements it with `SessionAttachments.imageThumbnailURL` / `download`.
- **`CKAttachment`.** A platform-neutral attachment model (id, name, byte size, type, optional `CGImage` thumbnail, upload progress 0…1 or nil, failed flag).
  - The UIKit `CKAttachmentItem` / `CKAttachmentStrip` keep their API in phases 1–2.
  - Phase 3 may adapt them onto `CKAttachment` without changing behaviour.

### ChatAppKit (AppKit)

- **`CKTranscriptTable`**: a view-based, single-column `NSTableView` in an `NSScrollView` that renders only visible rows.
  - **Rows:**
    - The host registers a cell factory per kind tag and gives each row `(id, kind tag, neighbour key, version, group id)`.
    - Height comes from `CKHeightCache` through a host `measure(row, width) -> CGFloat` closure. Updates use `noteHeightOfRows(withIndexesChanged:)`, not full reloads.
  - **Updates:**
    - `CKRowDiff` drives `insertRows` / `removeRows` / reconfigure-in-place.
    - Re-entrant updates coalesce, like T:180/T:432.
  - **Paging and position:**
    - Paging uses `CKHistoryWindow`, and prepending uses `CKScrollAnchor`, so the first visible row stays put within 1 pt.
    - Follow-bottom uses `CKFollowState`, with `CKScrollMotion` for the motion.
    - Live scroll notifications map to "scroll is moving".
    - Send landing matches iOS: the anchored user row sits near the top, with a reserved bottom inset (the `ChatScroll.bottom` math, moved into `CKScrollMotion`). `CKTranscriptTable` owns that inset.
- **`CKHistoryHeaderView`**: the loading / "load earlier" / start-of-session states, like iOS `ChatHistoryHeader`.
- **`CKAttachmentStripView`**: an AppKit twin of the UIKit strip that renders `[CKAttachment]`.
  - Pills show a thumbnail or file icon, a name and size, and a remove button.
  - It has an upload progress ring and a failed state.
  - Remove is an intent callback (the host re-renders), as on iOS.
  - VoiceOver labels and ≥ 44 pt-equivalent hit areas follow the macOS HIG.

### Lody side

- **Mac (`LodyMacKit`):**
  - `MacTranscriptView` hosts `CKTranscriptTable`.
  - The existing row views become reusable cell views, `MacMarkdownView` included; measuring Markdown height needs an offscreen measuring view at the column width, like iOS `ChatMarkdownStore`.
  - The permission card and failed-send rows stay Lody cells.
  - `MacTranscriptModel` keeps mapping `ChatRow` → items but now exposes kind tag, neighbour key and group id.
  - New:
    - an image cell (`ChatRow` kind `image`) that loads through `CKMediaProvider` and opens Quick Look on click
    - an attachments cell (kind `attachments`) with `CKAttachmentStripView` in display mode; click downloads, then Quick Look
    - a history header
- **Mac composer:**
  - A paperclip button opens an `NSOpenPanel`.
  - ⌘V pastes images or files from `NSPasteboard`, and dropping files onto the composer or transcript adds them. All three feed one draft attachment list shown in `CKAttachmentStripView` above the input.
  - Sending passes attachments through the existing reply/create payload, so `DataRuntime+Sessions` uploads them (`SessionAttachments.upload`).
  - Mirror iOS for progress: the composer clears on send, and progress shows on the pending message's attachments row in the transcript, read from `uploadProgress` in `SessionSender.pendingSendJSON` like `ChatMessageAttachmentsCell.swift:149`.
  - The payload's attachment dictionary shape and the limits (count, size, types) must match iOS `ChatAttachments.swift`. The builder reads it there; do not invent a new shape.
  - On upload or send failure the draft's text **and** attachments come back to that session's reply composer (AGENTS rule).
  - Both the reply composer and the new-session composer accept attachments. A new session opens once the outbox write succeeds, so a later upload failure restores into the new session's reply composer, not the closed new-session form. (My call, matching iOS's first-turn handoff.)
- **iOS (`LodyiOSKit`, phase 3):**
  - `LodyChatView` keeps its cells, projection glue, business events and animations.
  - Its diff / history / height cache / follow / anchor / budget logic is replaced by the Core types.
  - Lody kind decisions move into the closures passed to the Core.
  - No visual or behavioural change.

## Phases (each ends green and committed)

1. **ChatKitCore mechanics.**
   - Write the Core types with unit tests, in the submodule.
   - Seed the tests from today's behaviour, ported cases from `verification/kit/chat/main.swift` where they cover the same logic, and the parity notes above.
   - Commit inside the submodule, then bump the pointer in Lody.
   - iOS untouched.
2. **ChatAppKit + Mac transcript.**
   - Add the AppKit target and move `MacTranscriptView` onto it.
   - Add images, attachments display, composer attachments and history paging.
3. **iOS adoption.** After `lody-ios-bb` confirms it is done (the main session messages it; builders don't):
   - Re-plan this phase from the code as it stands then. Its chat-polish work removes `turn` rows and `ChatTurnCell` and rewrites `ChatRowPadding` into `gap(before:after:)`, so the T:/S:/V: line references above will have moved. The behaviour they describe is still binding.
   - Capture baselines of the iOS checks first.
   - Swap the mechanics onto the Core.
   - Rerun everything against those baselines.

## Verification

- **Phase 1:** `swift test` in `packages/chat-kit` (Core tests) on macOS; the existing `verification/kit/chat-kit` consumer check still builds.
- **Phase 2:**
  - **Unit tests:** `swift test --package-path packages/LodyMacKit`.
  - **In-process (`pnpm verify:mac`):** new cases, keeping all existing ones green:
    - `transcript-history`: a 1,000-entry fixture.
      - Opens on the latest page.
      - The table holds ≤ visible + buffer row views.
      - Scrolling to the top loads the previous page.
      - The first visible row keeps its position within 1 pt.
      - Streaming appends while scrolled up don't move the reader.
      - A send lands the user message near the top with space reserved below, and the reply grows into it.
    - `attachments`: composer pick (scripted panel result), paste, a drop fixture, the strip with remove, a scripted send whose progress shows on the pending message row, failure restoring text + attachments, inline image and attachments rows using a fixture media provider.
  - **VM gate:** `pnpm verify:mac:vm --case transcript-history --case attachments --case transcript`, adding XCUITest flows (real scroll to top, real drag of a file onto the composer, real click on an image → Quick Look).
  - **Performance:** record open time and scroll for 10,000 entries in the fixture and report the numbers. No numeric promise is made.
- **Phase 3:**
  - Before touching iOS, capture baselines with the current build:
    - `verification/ui` `chat-stream-performance`, `smooth-scroll`, `chat-performance`, `send-scroll`
    - `verification/kit/chat`, `chat-render`, `chat-kit`, `tracking.py`
  - After the change, every check passes its own thresholds on the same simulator. Each performance metric uses the median of 3 runs before and 3 after, and a regression of more than 10 % blocks the phase. (My call: run-to-run noise makes "never worse" unusable.)
  - Then run `pnpm check`, `pnpm bundle` and a signed simulator build.
  - English only, light and dark, per AGENTS.

## Left to the builder

- Exact Core type names and signatures, file layout inside `ChatKitCore` / `ChatAppKit`, how cell registration is expressed (protocol vs closure), and buffer sizes.
- Whether Mac cell views are recycled through `NSTableView.makeView(withIdentifier:)` or a small custom pool.
- How Mac measures Markdown height (offscreen `MarkdownTextView` pool vs a TextKit measurement), provided heights are cached in `CKHeightCache`.
- Moving `ChatScroll` / `ChatReadingColumn` from LodyData into ChatKitCore is **not** required. My call: leave them in LodyData during phases 1–2 to avoid touching iOS call sites; phase 3 may move them if it simplifies the adoption.
- Mac attachment limits and accepted types: mirror iOS exactly.
