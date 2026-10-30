# TL;DR: Signal identity + chat thread

Full spec: [2026-10-30-signal-identity-chat-thread-design.md](2026-10-30-signal-identity-chat-thread-design.md). Artboard: https://ryugi.innei.dev/a/kAyXBRybNnSwuVarLqor (Round 3 group `final`).

## What gets built

Lody indigo from the jellyfish icon appears in a few places, and sub-agent tree lines become tentacle curves. The chat thread is tightened to fixed gaps, with turn dividers, a corner bubble, and a file block that folds.

## What you'll see

1. Home: running glyphs spin with an indigo→teal arc, unread dots are indigo, and sub-agent lines curve. Review, new session and the workspace mark are indigo by default.
2. Chat: tool steps sit in 30 pt rows instead of 44 pt ones, so a 5-step turn uses about a third of the height it uses today.
3. Chat: a thin line with the time (`10:46`) separates each turn from the next.
4. Chat: your messages are neutral bubbles with a sharp bottom-right corner.
5. Chat: file changes show as one line, "9 files changed ■■■■■ +155 −36". Tap it to expand the file list; tap a file to open its diff.

## Decisions

| #   | Decision                                            | By  |
| --- | --------------------------------------------------- | --- |
| q1  | A · Signal (indigo + tentacles)                     | you |
| q2  | Compact 30 pt process rows                          | you |
| q3  | Turn divider + time; 10 / 12 / 4 gaps inside a turn | you |
| q4  | Keep the bubble                                     | you |
| q5  | Neutral bubble, 6 pt bottom-right corner            | you |
| q6  | File block collapsed to one summary line            | you |

## Answered by you

- Lody indigo replaces Ink as the default for installs that never picked an accent.
- 30 / 40 pt rows in the chat transcript are a documented exception to the 44 pt rule. AGENTS.md is updated to say so.

## Check these (my calls)

- One changed file: no summary; that file shows as a single row.
- The file block sits above the model/meta row (it sits below it today).
- "Review all changes" opens the session's changes page and is hidden when the session isn't reviewable.
- Dividers go only before a new run. Steers and queued messages get none.
- Divider time: `10:46` today, `Yesterday 10:46` yesterday, a date plus time for older turns.
- Tentacles keep their curved shape always and are colored only while the parent is running.
- Sub-agent child rows keep their detail line, at 40 pt.

## Time

About 1.5–2 days of agent work. That breaks down as roughly half a day for Signal tokens, the accent and glyphs, half a day for the chat spacing and divider, half a day for the foldable file block, and half a day for verification cases and light/dark screenshots. It starts after the bug fixes land.
