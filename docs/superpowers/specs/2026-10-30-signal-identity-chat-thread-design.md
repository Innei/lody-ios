# Lody Design Language, Round 3: Signal Identity and the Chat Thread

Artboard `artboard/lody-identity` (Ryugi): https://ryugi.innei.dev/a/kAyXBRybNnSwuVarLqor. The local copy is at `.ryugi/artifacts/artboard/lody-identity/`, which may not be committed. Every decision made on the artboard is restated in this document.

## Intent

Rounds 1 and 2 ([home](2026-10-29-design-language-home-design.md), [forms and chat](2026-10-30-design-language-forms-chat-design.md)) gave Lody a neutral, compact rail language. The user still finds it lacks identity: it reads as a well-made generic list. They want the app to look like Lody without becoming busy. Two requirements carry over: "not flashy" and "modern".

They also find the chat thread "too loose": gaps have no system. Measured in code, each row kind brings its own padding:

- process rows have a 44 pt minimum;
- sub-agent rows have a 52 pt minimum;
- the user row adds 44 pt;
- text rows add 6 + 6;
- the meta row has a 44 pt minimum;
- the file-change block is a 44 pt header plus 44 pt per file, with no fold.

A five-step turn fills half the screen.

The identity comes from the app icon, a blue-to-teal jellyfish. The jellyfish gives the app two things:

- **The Signal hue**, Lody indigo, used sparingly.
- **The tentacle shape.** Sub-agent tree lines become soft curves hanging from the parent: one agent carrying the others.

## Decisions (all by the user on the artboard)

| Group | Question                    | Chosen                                                                                |
| ----- | --------------------------- | ------------------------------------------------------------------------------------- |
| q1    | Where identity comes from   | **A · Signal**: logo indigo in a few places, plus tentacle tree lines                 |
| q2    | Process row density in chat | **a · Compact 30 pt rows**                                                            |
| q3    | Spacing rhythm in chat      | **c · A divider between turns, with the turn's time**; tiered spacing inside the turn |
| q4    | User message form           | **a · Keep the bubble**                                                               |
| q5    | Bubble style                | **d · Neutral fill with a 6 pt bottom-trailing corner**                               |
| q6    | File-change block           | **b · Collapsed to one summary line by default; tap to expand**                       |

Rejected boards stay on the artboard as history:

- q1: B Editorial, C Console, D Presence;
- q2: b fold-completed, c 44 pt;
- q3: a uniform 16, b tiered without a divider;
- q4: b prompt head on the rail;
- q5: a, b (indigo tint), c (outline);
- q6: a (first 4 + "Show more"), c (directory groups), d (horizontal chips).

Reference boards:

- `q1-a`: Home and Chat in Signal (has a dark parameter).
- `f-light`, `f-dark`, `f-open` (group `final`, Round 3): the chat thread with every decision applied, the file block collapsed and expanded.
- `real-01`, `real-04`: simulator screenshots of the current thread, for comparison.

## Goals

- A Signal token set in `LodyDesign`, and a new default accent that resolves to it.
- Home, the iPad sidebar, and the chat transcript adopt Signal where `q1-a` shows it.
- The chat transcript adopts boards `f-light` / `f-open`: compact process rows, a fixed spacing scale, turn dividers, the corner bubble, and the collapsible file summary.
- Light mode, dark mode (`soft` / `black`) and increased contrast all work.

## Non-goals

- The composer (`ChatComposerView`, quick replies, model panel, attachments, chips). It is unchanged, except that its send button follows the accent as it does today.
- The Mac client (`LodyMacKit`). It shares LodyData transcript rows, so any new LodyData row kind must be ignored or rendered harmlessly there (see Left to the builder).
- Settings, forms, the create-session form, and the Share Extension. They pick up the new default accent automatically and change nothing else.
- Chat row kinds not drawn on the boards: plan, error, image, attachments, delivery and thought. They keep their layout and take only the spacing scale below.
- New behavior beyond folding the file block. Navigation, taps, selection, context menus, find and scroll-follow logic are unchanged.

## Anti-goals

- Indigo washes, gradients on surfaces, a tinted user bubble, or tinted section bands. Indigo appears only in the places listed under Signal.
- Cards: the file block remains the existing grouped `lodyInset` block, with no shadow.
- Green as an accent; diff counts stay `systemGreen` / `systemRed`. Teal appears only as the far end of the live-glyph and tentacle gradients, never as a fill or as text.
- Nested ternaries (AGENTS.md).

## Signal (q1 → A)

### Tokens

Add these to `packages/LodyiOSKit/Sources/Appearance/LodyDesign.swift`, with light, dark and increased-contrast variants:

| Token                | Light     | Dark      | Use                                                    |
| -------------------- | --------- | --------- | ------------------------------------------------------ |
| `lodySignal`         | `#3550D4` | `#8195FF` | live arc start, unread dot, tentacle start, accent     |
| `lodySignalTail`     | `#1FA797` | `#39C6AE` | live arc and tentacle gradient end only                |
| `lodySignalOnAccent` | `#FFFFFF` | `#0C0F24` | label or icon on a Signal fill (Review, compose, send) |

The builder audits contrast. Under increased contrast, `lodySignal` must reach 4.5:1 against `lodyGround` when it is used as text (live verbs in chat), and 3:1 as a glyph.

### Accent

- Add `LodyAccentChoice.lody` (raw value `"lody"`). It resolves to `lodySignal`, with `lodySignalOnAccent` as its foreground.
- `.lody` is the default for installs with no stored value (user decision; see Answered after the builder check).
- The Appearance picker lists Lody first, then Ink and the existing presets. Stored choices are kept, and there is no migration, the same rule as in Round 1. The Share Extension mirror carries `"lody"` like any other value.
- Round 1's exceptions stand: chat links are `systemBlue`, switches use the system default, and the user bubble is neutral.

### Where Signal appears (fixed colors that never follow the accent)

The status glyph colors are fixed, as Round 1 ruled for glyphs:

| Element                                                                                     | Today                              | Signal                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `live` glyph arc (`LodyStatusGlyph`)                                                        | `ink` arc on a `line2` track       | A gradient arc from `lodySignal` to `lodySignalTail` on the same track. It keeps the same rotation, Reduce Motion stop and offscreen stop.                                                             |
| `unread` dot                                                                                | `ink`                              | `lodySignal`                                                                                                                                                                                           |
| Tree lines (`LodySessionRowView`, `ChatSubagentCell`, chat process children)                | 1 pt `lodyRail` elbow, 7 pt radius | **Tentacle**, a cubic curve (see below). When the parent is live, the stroke is a vertical gradient from `lodySignal` at 75% to `lodySignalTail` at 60%, 1.5 pt wide. Otherwise it is 1 pt `lodyRail`. |
| Live process verb in chat (`Running`, `Editing`, the `Sub-agent` label of a live sub-agent) | `ink` semibold                     | The accent color (`lodyAccent`), so it follows the user's accent.                                                                                                                                      |

The **tentacle** replaces today's elbow. My call, since the parent and each child are separate cells: every cell draws only its own segment, as it does today.

- The vertical trunk still passes through the cells in between (`treeDown` and the continuation).
- The elbow, a horizontal run with a 7 pt quad corner, becomes a soft S-branch. It is a cubic curve from the trunk at `childCenterY - 14` to `(childGlyphMinX - 1, childCenterY)`, with control points `(railX - 2, childCenterY - 6)` and `(railX + 4, childCenterY)`.
- On the last child the trunk ends where the branch starts.

This reads as the bundled curves of boards `q1-a` and `f-light` without drawing across cells. The builder may tune the control points, especially at compact density.

**Live parent (my call).** In Home, `SessionRows.treeRows` sets a new `parentLive` flag on child rows. In chat, the parent is the process group, and it counts as live while that group is running (the `duration` row's `running`, or the group's live state). Children read the flag to choose the gradient stroke or `lodyRail`.

Accent-driven elements also turn Signal by default:

- the Review capsule;
- the new-session button;
- the workspace monogram square;
- the composer send button;
- the "Review all changes" link.

## Chat thread

All values are at the default text size. Fonts keep their current text styles and `UIFontMetrics` scaling.

### Spacing scale (q3 → c)

This replaces per-kind padding with three named gaps, set on `ChatReadingColumn` or `ChatRowPadding`:

| Gap         | Value             | Between                                                                                                                             |
| ----------- | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `afterUser` | 10                | a user bubble and whatever follows it in the same turn                                                                              |
| `block`     | 12                | blocks inside a turn: process group ↔ answer, answer ↔ file block, answer paragraphs and code (markdown paragraph spacing stays 10) |
| `meta`      | 4                 | the file block or answer ↔ the meta row                                                                                             |
| turn        | 16 + divider + 16 | the last row of one turn ↔ the next user bubble                                                                                     |

Consecutive process rows stack with no gap. The user row's `rowExtra` of 44 goes away: the bubble keeps its own internal padding of 10 × 14, and the gaps above apply outside it.

### Turn divider

- **What counts as a turn (my call):** only the user message that starts a new run gets a divider, meaning the first user row of an execution group (`userTurnId`). These never get a divider: steers inside a run, queued `delivery` rows, and the first turn in the loaded transcript. The optimistic `pending` row starts a new turn, so its divider appears with it at send time, using the send time, so that the layout doesn't jump when the server copy replaces it.
- The divider is a row placed before each such turn: a 0.5 pt `lodyLine2` hairline on each side of a centered label, with 16 pt side margins.
- The label is the user turn's time in mono 11 `lodyTertiary`, for example `10:46`.
- My call on the label format: time only for today; `Yesterday 10:46` for yesterday; for older turns, a short date plus the time, using the system formatter (as `ChatMetaTime` does).
- The row is 20 pt tall, with 16 pt above and below. It is not interactive and is hidden from VoiceOver (`isAccessibilityElement = false`).

### Process rows (q2 → a)

- Process, summary and tool rows (`ChatCell.processHeight`): the minimum height drops from 44 / 52 to **30 pt** for one line and **40 pt** with a detail line.
- Title: 14 pt (the subheadline metrics scaled from 14). Detail: 12 pt.
- Sub-agent rows (`ChatSubagentCell`), parent or child: **40 pt** with a detail line, **30 pt** without. Child rows keep their detail line when they have one (my call).
- The glyph stays centered on the title's first line at the rail center.
- **Collapsed process summary row** (the 8 pt dot plus "Thought · Read 1 file"; user, after review on device: "this gap must be compact too"): the dot's left edge aligns with the answer text's 16 pt margin (dot center x = 20), and the title starts 6 pt after the dot (x = 30) instead of the 46 pt rail column. The row is 30 pt tall.
- **Touch targets:** a documented exception, with full-width rows that can each be tapped (see Answered after the builder check).

### User bubble (q4 → a, q5 → d)

- Neutral `lodyInset` fill, as today.
- Corner radii: 20 pt continuous on three corners, and **6 pt on the bottom-trailing corner** (bottom-right in left-to-right layouts).
- Text 16 pt, and padding of 10 vertical × 14 horizontal.
- The bubble keeps its current leading inset: it is trailing-aligned and at most 84% of the column width.

### File-change block (q6 → b)

- **Collapsed by default.** One 42 pt row in the existing grouped `lodyInset` block (12 pt continuous radius), containing:
  1. a file-diff glyph;
  2. "N files changed" (the existing `native.chat.transcript.fileCount` string) at 14 pt semibold;
  3. a 5-square diffstat: 7 pt squares, 2 pt radius, 2 pt gap, with green squares equal to `round(5 × add / (add + del))` and the rest red;
  4. the totals `+add −del` in mono 12;
  5. a trailing chevron in `lodyTertiary`, which rotates down when expanded.
- **Expanded.** Tapping the summary row expands the block in place, animated with the list's usual row insertion. The rows:
  - Each file is a **40 pt** row: an icon, then the **file name** in mono 12.5 medium `lodyInk`, then its **directory** in 11.5 `lodyTertiary` truncated at the head, then `+add −del` trailing.
  - A hairline runs under the text column.
  - A last row reads "Review all changes ›" in the accent color. My call: it opens the session-level `WorkspaceChangesController` through the existing `openWorkspaceChanges()`, and it is **hidden when the session is not reviewable** (the same `reviewable` gate). There is no per-turn changes page. The label says "all changes", which matches the session-level page.
  - Tapping a file opens its diff, as today.
- **Expansion state** is per entry and kept for the life of the chat view, like `expandedAttachments`. It is not persisted.
- **Single file (my call):** with exactly one file, skip the summary and show that file as one row (name, directory, stat) that opens its diff directly. A summary that hides one name saves nothing.
- **Order (my call, following the boards):** the file block sits directly under the answer, and the meta row follows it. Today the projection emits `meta` before `changesHeader`. Swap them in `ChatTranscript.entryRows`.
- **Accessibility:** the summary row is a button. Its label is "9 files changed, 155 additions, 36 deletions". Its value is expanded or collapsed, and it follows the existing accessibility strings pattern. Add catalog strings for "Review all changes" and for the accessibility label/value, through `Localizable.xcstrings` with plural variations.

### Meta row

32 pt tall, down from a 44 pt minimum. Content is unchanged. Its action buttons keep 44 pt hit areas by extending outside the row (`point(inside:)`), because the row has empty space above and below.

## Home and the iPad sidebar

These change only through Signal, as board `q1-a` shows:

- the accent default;
- the live glyph gradient;
- the indigo unread dot;
- tentacle tree lines in `LodySessionRowView`, at both densities.

Row geometry, bands and the header are unchanged.

## Answered after the builder check (user)

1. **Default accent:** `.lody` replaces Ink as the default when nothing is stored (`LodyAccentChoice.current` falls back to `.lody`). Stored choices, Ink included, are kept, and there is no migration.
2. **Touch targets:** the chat transcript is a documented exception. Process rows (30 / 40 pt), file rows (40 pt) and the file summary row (42 pt) are full-width rows that can each be tapped. Update AGENTS.md's UI baseline to say that stacked full-width transcript rows in chat may be shorter than 44 pt, and that every other control keeps the 44 pt minimum.

## Left to the builder

- How the turn divider enters the row list. One option is a new `turn` row kind emitted by `ChatTranscript` in LodyData. If so, `LodyMacKit`'s transcript must skip or render it, and the Mac UI must not change. Another option is iOS-only insertion in `LodyChatView+Transcript`.
- How collapse and expand are modeled: a header row plus conditional file rows in the diffable snapshot, or a single cell. Keep selection-retention behavior (AGENTS.md) for file rows that navigate.
- The gradient mechanism for the live arc and the tentacles: a `CAGradientLayer` masked by the shape layer, or similar. Keep the arc's rotation on the existing layer.
- The `UIFontMetrics` mapping for the new 14 / 12 pt process fonts.
- The exact increased-contrast values for the Signal tokens, within the contrast targets above.

## Sequencing

Build this after the bug fixes from the same session land. The `session-preview-tasks` scene and the `session-taps` case are the baseline, and the temporary `LODYDBG` logging must be removed first. Capture the baselines from that committed state.

## Verification

- `pnpm check`, `pnpm bundle`, and an iOS simulator build with signing (AGENTS.md).
- Before changing shared code, capture baselines with the existing cases. Cover Home, the iPad sidebar, and the chat transcript (`session-preview-tasks`, added by the bug fix in this session, has file links, a code block and a running sub-agent).
- Update or add checks in `verification/ui`:
  - default accent when none is stored;
  - stored accents persist;
  - the file block starts collapsed, expands on tap, opens a diff from a file row, and opens the changes page from "Review all changes";
  - the single-file case;
  - a turn divider appears between turns and not before the first;
  - process rows and file rows can each be tapped across their full width;
  - live glyphs are colored, with Reduce Motion stopping the arc.
- Update the native checks in `verification/kit/design`, `chat-render`, `chat-files` and `chat-subagent` for the new heights and the meta/changes order.
- Screenshots in light, dark, and dark + `black`, English only. Compare against boards `f-light`, `f-dark` and `f-open`, and `q1-a` for Home.
