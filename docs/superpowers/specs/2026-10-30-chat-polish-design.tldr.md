# TL;DR · Chat polish

Spec: `2026-10-30-chat-polish-design.md` · Artboard: https://ryugi.innei.dev/a/MbbobLnjkYyY6I_6nilr

## What gets built

The chat transcript, the session header and the sub-agent page are polished along one line: unified spacing, one type style, no chevrons, no turn dividers, a single trailing button. The shine is fixed for every accent, including Ink.

## What you'll see

1. **Spacing.** The reply text sits 16 pt below the process block, the file block 12 pt below the reply, and the meta row 8 pt below the file block. Turns are 24 pt apart.
2. **Process row.** "Processed for 1m 04s" is one regular face in secondary color, with tabular digits. It drops the bold + monospace mix.
3. **Shine.** Running status rows (process summaries, thinking) use secondary text with a band brightened to ink sweeping across it, visible in light and dark under every accent. Streaming reply text no longer shines; it keeps the per-character fade-in.
4. **Turn divider.** "Yesterday 6:02 PM" is gone.
5. **File block.** No five-square diffstat; names in 13 pt monospace; only `+33 −7` totals; no chevrons.
6. **Header.** Only the ••• button on the right. The PR becomes a small chip next to the branch, `⎇ feature/native-session  #31●`. The first item of the title menu is "Open PR #31".
7. **Meta row.** No ⓘ; the text is 12 pt tertiary; the ••• lines up with the diffstat numbers above it.
8. **Rows that open a sheet.** "Processed for" uses an 8 pt dot instead of a check, and loses its trailing arrow.
9. **Sub-agent page.** The title and status move into the navigation bar, and Copy becomes a bar icon. The body uses the chat thread's rows and reply text, and the toast no longer covers the grabber.

## Decisions

| Group             | Choice                                 |
| ----------------- | -------------------------------------- |
| q1 spacing        | A · even 8 pt                          |
| q2 process row    | A · quiet, one face                    |
| q3 shine          | B · secondary → ink                    |
| q4 turn divider   | removed                                |
| q5 file block     | A · quiet                              |
| q6b header        | D · PR next to the branch + title menu |
| q7 meta row       | A · ••• aligned                        |
| q8 sheet rows     | A · summary dot, no chevron            |
| q9 sub-agent page | A · same language as the chat          |

## Check these (my calls)

- When the machine is offline, the caption still shows "Offline". The board doesn't draw this, but AGENTS.md requires the connection state to be visible.
- With several PRs, the chip shows "#31 +1".
- A small ⌄ after the title signals that it opens a menu.
- On the sub-agent page without run data, the body reads "Finished · last tool Bash", followed by the result text.
- With no branch, the caption falls back to the project name.
- Spacing: 24 pt before any user bubble; 8 pt between consecutive user bubbles.
- "Review all changes" also loses its chevron.
- The toast moves below the navigation bar only on the sub-agent page; other toasts are unchanged.
- The shine change lives in the ChatKit submodule. It must be pushed together with the still-unpushed `dcad0a5`, and I'll ask you before pushing.

## Time

About 3–4 hours of coding plus checks, and about 1 hour of simulator verification (light and dark, three cases).
