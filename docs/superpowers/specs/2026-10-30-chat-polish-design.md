# Chat Polish: Transcript, Shine, Header and Sub-agent Page

Artboard `artboard/chat-polish` (Ryugi): https://ryugi.innei.dev/a/MbbobLnjkYyY6I_6nilr. The local copy is at `.ryugi/artifacts/artboard/chat-polish/`, which may not be committed. Every decision made on the artboard is restated in this document.

## Intent

[Round 3](2026-10-30-signal-identity-chat-thread-design.md) tightened the chat thread and introduced Signal. The user now finds the chat "getting uglier with every change". The cause is not one big mistake. Each round added its own type style, trailing mark and spacing, and nothing reconciled them:

- The reply text sits about 4 pt under the sub-agent row and reads as part of it.
- The process row mixes semibold text with a monospaced duration.
- The file block carries a five-square diffstat, 15 pt monospaced names and chevrons. The meta row under it has its own ⓘ and a `…` that line up with nothing.
- The turn divider sets the time in letter-spaced monospace.
- The header squeezes the title to "Native session pr…" because of a separate PR button tinted orange or blue.

The shine on running rows is the second complaint. Running process text uses the accent color, and the highlight mixes the accent with 64 % white (`ChatNumericText.swift:20`). Text labels use a different shine: they redraw a band at 32 % alpha (`ChatFadeLabelView.swift:31`, `CKTextView.swift:219`). Under the Ink accent, light mode shows a grey smear moving over black text. Dark mode mixes near-white with white, so the sweep is invisible.

This round is a polish pass on what already exists. It changes no behavior beyond what is listed.

## Decisions

The user chose "all recommended". q4 and q8 were settled by artboard comments, and q6 was replaced by q6b after a comment.

| Group | Question                    | Chosen                                                                                                                                                   |
| ----- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| q1    | Spacing between blocks      | **A · Even 8 pt rhythm**                                                                                                                                 |
| q2    | Process row type            | **A · Quiet: one face, secondary**                                                                                                                       |
| q3    | Shine on running rows       | **B · Neutral: secondary text, the band lifts to ink**                                                                                                   |
| q4    | Turn divider                | **Removed** (comment: "这行还是不要了，去掉吧", "drop this row, take it out"). Turns are separated by the user bubble and spacing alone.                 |
| q5    | File changes block          | **A · Quiet block: smaller monospace, plain diffstat**                                                                                                   |
| q6b   | Navigation header (round 2) | **D · PR beside the branch in the caption; the title menu opens it.** This replaces q6 A–C after the comment that the PR button squeezes the title view. |
| q7    | Meta row under a reply      | **A · Text row, ••• in a 44 pt slot on the trailing content column**                                                                                     |
| q8    | Rows that open a sheet      | **A · Summary dot, no trailing mark** (comment: the chevron implies push or expansion, but these rows open a sheet; earlier UI used a dot)               |
| q9    | Sub-agent page              | **A · Same transcript language**                                                                                                                         |

Rejected boards stay on the artboard:

- q1 B (tight within a turn, wide between turns);
- q2 B (ink title) and C (semibold without the mono duration);
- q3 A (current) and C (a pulse instead of a sweep);
- q4 A–C (divider styles);
- q5 B (file icons, proportional names);
- q6 A–C;
- q6b E (PR in the ••• menu) and F (PR chip above the composer);
- q7 B (leading action icons);
- q8 B (trailing •••);
- q9 B (header card) and C (grouped list).

Reference boards:

- `now`: the current thread with the Ink accent, light and dark.
- `sa-light`, `sa-dark` (group `sa-now`): simulator screenshots of the current sub-agent page.

## Goals

- One spacing scale for the chat transcript, and one type treatment for process rows.
- A shine that reads as a highlight under every accent (Lody, Ink, system colors, custom), in light and dark.
- No turn dividers.
- A quieter file block and meta row whose trailing edges line up.
- No chevrons on rows that open a sheet.
- A header with one trailing button, and the PR next to the branch.
- A sub-agent page that matches the chat thread.

## Non-goals

- Home, the iPad sidebar, `lodyBand`, rail glyphs and tentacle tree lines outside chat.
- The composer, quick-reply chips and the model panel.
- The Mac client (`LodyMacKit`). It already filters `turn` rows out (`ChatTranscript.swift:407`). It must keep compiling and keep its current look.
- Row kinds not drawn on the boards: plan, error, image, attachments, delivery and thought. They take the new spacing scale only.
- User bubble shape, colors and accent tokens. Round 3 settled these.
- New behavior. Taps, selection, context menus, find, folding and scroll-follow are unchanged, except where a change is listed below.

## Anti-goals

- Indigo or accent tint on resting text. Signal stays on status glyphs only.
- A shine that dims text, a shine that depends on the accent's luminance, or a shine that differs between process rows and text labels.
- Chevrons or disclosure arrows on rows that present a sheet.
- A second PR control anywhere in the bar.
- Nested ternaries (AGENTS.md).

## Spacing (q1 → A)

One scale, in points. The value is the gap between the visible edges of two blocks, not a per-cell padding:

| From → to                                                                           | Gap                             |
| ----------------------------------------------------------------------------------- | ------------------------------- |
| User bubble → first block of its run                                                | 16                              |
| Last process / sub-agent row → reply text                                           | 16                              |
| Reply text → file block                                                             | 12                              |
| File block → meta row                                                               | 8                               |
| Any non-user row → user bubble (new turn, steer, retry; with or without a meta row) | 24                              |
| User bubble → user bubble (stacked sends / queued steers)                           | 8                               |
| Between consecutive process / sub-agent rows                                        | 0 (row heights stay 30 / 40 pt) |
| Between paragraphs or blocks inside one reply                                       | unchanged                       |

Today the gaps come from `ChatRowPadding` (`ChatCell.swift:4`), from `rowExtra` (`ChatCell.swift:472`) and from fixed cell heights. Express the table through those, or through one small gap function keyed by `(previousKind, kind)`. Do not add per-cell magic numbers. The 24 pt between turns replaces the space the divider used to take.

## Process row type (q2 → A)

This applies to the `duration` row, which reads "Processed for 1m 04s" or "Working for 12s" while running:

- Title: 14 pt regular, `lodySecondary`. The duration uses the same face with tabular digits (`.monospacedDigit()`), not `LodyDesign.mono`.
- Detail line ("Edited 3 files"): 12 pt, `lodyTertiary`.
- Leading mark: see q8.

`summary` rows (later process groups and executions) take the same quiet type: 14 pt regular `lodySecondary`, with tabular digits. This is my call, for consistency, so the two process-row kinds don't diverge again. Sub-agent rows keep their current type.

## Shine (q3 → B)

Which rows shine:

- **Status rows only.** Running `summary` rows, drawn through `ChatNumericText`, whose running color comes from `LodyChatView+Transcript.swift:481`. Running `thought` rows, drawn through `CKTextView`.
- **Streaming reply text (`text` items) does not shine** (the user's answer). It stays `lodyInk` and keeps only the existing per-character fade-in. Remove the reply path from `shines`: the markdown `ChatFadeLabelView` shine and `text` rows in `ChatTranscript.swift:226`.
- **The `duration` row keeps not shining**, as today. It is drawn by a plain label and excluded from `shines`. The board drew "Working for 12s" sweeping, which was the board's mistake, not a decision. Do not move it onto `ChatNumericText`.

How a status row shines:

- Base text color while running: `lodySecondary`. It no longer uses the accent: `ChatCell.swift:334` and `LodyChatView+Transcript.swift:481` currently use `.lodyAccent` while running.
- The gradient applies to every glyph in the row, including any colored runs. These rows carry no links or inline code.
- The highlight band is `lodyInk`, resolved for the current trait. It is a soft linear gradient, about 20 % of the text width at full strength, sweeping leading → trailing every 1.5 s (the current period). Match the board `q3-b`: secondary to ink at 50 % to secondary.
- The band brightens toward ink. It never lowers alpha and never mixes with white or black.
- With Reduce Motion: static `lodySecondary` text and no animation, as today.
- The live arc glyph is unchanged and keeps its Signal color.

`CKTextShine` lives in the ChatKit submodule (`packages/chat-kit`). Change it there, so ChatKit draws the gradient highlight instead of the dim band, and commit it in ChatKit. ChatKit `main` already holds the unpushed commit `dcad0a5`, which blocks CI. Both must be pushed before the lody-ios commit that bumps the submodule; ask the user before pushing.

## Turn divider (q4 → removed)

- Remove `turn` rows from the projection: `ChatTranscript.dividingTurns` / `turnRow` in LodyData, and their callers.
- Remove `ChatTurnCell` and its registration and height path (`LodyChatView.swift:352,384`, `LodyChatView+Scroll.swift:457`).
- Remove the pending-send turn row added in Round 3.
- Remove the Mac and iOS filters for `turn` that become dead.
- Remove the `native.chat.turn.yesterday` string if nothing else uses it.
- Update `verification/ui/chat-thread.py` and the native checks that assert dividers, so they assert their absence instead.

## File changes block (q5 → A)

`ChatFileCell`:

- **Header.** Drop the five-square diffstat. "3 files" is 14 pt medium. The total `+33 −7` is 13 pt system with tabular digits (not mono), in systemGreen / systemRed. The fold glyph is `lodyTertiary`.
- **File rows.** The name is 13 pt `LodyDesign.mono`. The path is 12.5 pt proportional `lodyTertiary`, truncated in the middle as today. The diffstat is 12 pt system tabular. There is no trailing chevron (q8).
- **Unchanged.** The block keeps its fill, radius, 42 pt header, 40 pt rows, folding rules, and the "Review all changes" row.

## Navigation header (q6b → D)

- **Trailing bar items.** Only the ••• menu. Remove the PR bar item (`SessionController+Tools.swift:67`, `SessionController.swift:259`).
- **Caption** (`ChatNavigationTitle.attributedSubtitle`):
  - Branch symbol and branch name, followed by a PR chip: a small `lodyInset` capsule with the pull-request symbol and `#31`, in `lodyInk`.
  - When any PR's CI is failing or errored (`ci` is `f` or `e`, the current orange condition), the chip ends with a 6 pt `lodyAttention` dot.
  - Project and machine leave the caption. They are already in the title menu.
  - No branch (chat-only sessions, non-git projects): the caption falls back to the project name, with the folder symbol, so the header keeps two lines. This is my call.
  - When the machine is offline, the caption still says so: "⎇ branch · Offline". This keeps the connection state actionable, as AGENTS.md requires.
- **Title menu** (`SessionController.titleMenu`): add one item per PR in its own first group, titled "Open PR #31". Its subtitle is the PR state from the existing `pr.state.*` string, plus "Checks failed" when CI fails. Choosing it calls the existing `openPullRequest`. Keep the existing files, branch, machine and rename items.
- **Title affordance.** A small `chevron.down` after the title, in `lodyTertiary`, marks that the title opens a menu. Show it only when the menu is non-empty.
- **No PR.** No chip and no menu item.

## Meta row (q7 → A)

`ChatMetaCell` (in `ChatCell.swift`):

- Remove the ⓘ glyph. The whole text stays the details button, as today.
- Text: 12 pt `lodyTertiary`, tabular digits.
- The ••• sits in a 44 × 32 pt slot. Its glyph's trailing edge lines up with the file block's inner trailing content edge: screen trailing margin 16 plus the block's 14 inset. So the ••• lines up with the diffstat numbers above it. When the block is absent, keep the same position.

## Rows that open a sheet (q8 → A)

- **Finished `duration` row.** Replace the leading check glyph with an 8 pt dot (`lodyTertiary`), centered on the rail center (x = 24), not at `summaryDot`'s x = 20. The tentacle line to its sub-agent children must still start from the dot. Use medium weight only if q2 type would otherwise read too faint; that is the builder's call, checked against board `q8-a`. The running `duration` row keeps the live arc.
- **Remove `processChevron`** (`ChatCell.swift:241–246`) and its `chevronSlot` text-width reservation. Also remove the trailing chevron from `summary` rows (`ChatCell.swift:508`), from file rows, and from the "Review all changes" row, which drops `.disclosureIndicator()`. That row also opens the detail sheet, so it follows the same rule.
- **Unchanged.** Sub-agent rows keep their check / live glyphs. Whole-row taps, their accessibility traits and hints, and pressed states stay as they are.

## Sub-agent page (q9 → A)

`SubagentTaskController`:

- **Navigation.** The title is the task description; the caption is "actor · status". The status words are the existing `native.chat.subagent.*` strings, plus "Background" when backgrounded. While running, a 6 pt Signal dot precedes the caption.
- **Copy result.** A trailing bar button (`doc.on.doc`) replaces the `Copy result` list row. It appears only when the result is non-empty, with the same toast and the same `subagent-detail-copy` accessibility identifier.
- **With `run` data.** Keep the chat transcript. Drop the synthetic header text item (`itemId + ":header"`), because the bar now carries it. The result item is unchanged.
- **Without `run` data.** Replace the `LodyGroupedList` with the chat transcript language:
  - a summary-dot row reading "Finished · last tool Bash" (or the status word when not finished; omit "last tool" when it is unknown);
  - then the result as selectable 16 pt body text with markdown, as the reply text renders it.
  - Keep `subagent-detail-result` as the result element's accessibility identifier.
  - The simplest route is feeding these rows to the existing `LodyChatView`, which is already embedded.
- **Failed.** The caption reads "actor · Failed"; the body shows the error text where the result goes.
- **Toast.** The "Copied" toast must not cover the sheet's grabber or navigation bar. Add an optional top anchor to `LodyToastOverlay.show`, such as a view whose bottom edge the toast sits 8 pt below. Pass the sub-agent page's navigation bar. Other toasts keep their placement; this round makes no global change. This is my call.

## Constraints

- Light, dark (`soft` / `black`), increased contrast, and every accent choice (Lody, Ink, system colors, custom).
- Default text size is the acceptance size. Keep Dynamic Type scaling through `LodyDesign.font` / `UIFontMetrics`.
- Strings go in `packages/LodyData/Sources/Resources/Localizable.xcstrings`: "Open PR #%lld", "Checks failed", "Finished", "last tool %@" or the equivalent.
- Keep `pnpm verify:ui` English-only. Add or update behavior checks in `verification/ui` for:
  - `chat-thread`: no dividers, no chevrons, the file block and the meta row;
  - `session-native` / `session-taps`: the header caption chip, the title menu PR item, no PR bar item, and the sub-agent page;
  - plus the native kit checks under `verification/kit/chat*` that assert the changed metrics.

## Left to the builder

- How the spacing table maps onto `ChatRowPadding` / `rowExtra`, provided the visible gaps match it within 1 pt.
- The exact gradient stops of the shine, within "secondary → ink → secondary, about 20 % band, 1.5 s".
- Whether the PR chip is an attributed-string attachment or a small view in the title view.
- With several PRs, the chip shows the first PR's number followed by "+N" (my call).

## My calls (from the builder check)

The user should check these while reading:

- `summary` rows take q2's quiet type.
- Spacing before any user bubble is 24 pt, and 8 pt between stacked user bubbles.
- When there is no branch, the caption falls back to the project name.
- "Review all changes" loses its chevron.
- The toast anchor applies only to the sub-agent page.
- The finished `duration` dot sits on the rail center at x = 24.
- The `duration` row does not start shining.

## Verification

- `pnpm check`, `pnpm verify:native`, `swift test --package-path packages/lody-core`.
- `pnpm verify:ui --case chat-thread`, `--case session-native` and `--case session-taps`, light and dark.
- Compare the screenshots with boards `q1-a`, `q2-a`, `q3-b`, `q5-a`, `q6-d`, `q7-a`, `q8-a` and `q9-a`. Capture a short video of the shine with the Ink accent in light and dark.
- Keep iPad / wide UI Verify deferred, per the current migration practice.
