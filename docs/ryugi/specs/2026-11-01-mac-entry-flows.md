# Mac New Chat and command palette

Approved for implementation by the user's “开始实现” after the Codex and Raycast Artboard rounds.

Design: `.ryugi/artifacts/artboard/mac-app-shell`, page `entry-flows`. New Chat uses `entry-new-ready`; Search and project selection use the second-round `raycast-search-light`, `raycast-search-dark`, `raycast-project-light` and `raycast-project-dark`. Earlier boards remain history.

## New Chat

Open in the current detail pane and focus the existing native Composer, anchored at the bottom with a 680 pt reading width. Show a quiet central project heading; its project name opens the same selector as the Composer context control. Preserve the account bar, sidebar rows, native split and Composer styling.

A window retains one new-session draft across repeated New Chat and detours to existing sessions. Text, attachments and explicitly chosen context stay together. A fresh draft inherits the current session's project and appropriate owning machine; absent that context, retain the existing default/remembered selection. Keep project-free chat, capability-dependent agents/models and offline send gating. Sending uses the existing outbox/create path; never add a second sender or clear an unsent draft when navigation occurs.

## Search and project selection

Sidebar Search and Cmd-F open a window-owned native transient panel, leaving the sidebar tree and active conversation unchanged while typing. Search the current workspace's unarchived top-level chat titles, project names and branches, using the native catalog only. Empty query shows quick actions and recent chats. The top trailing scope menu offers All, Chats and Projects. Manage projects targets the existing native destination.

Use a native search field and a table with compact 36 pt single-line rows, aligned title/context columns and neutral selected/hover states. The header is approximately 52 pt; footer approximately 44 pt. Fit height to results, capped near 408 pt; accommodate native fitting metrics and narrow parent windows. Use semantic colors and native material, never HTML in the product.

The footer identifies the mode and exposes the selected primary action with Return plus contextual Actions with Cmd-K. Related actions open the chat, start a draft in its project, or manage projects. Up/down changes the current result; Return commits. Escape, Back and outside dismissal retain the underlying page/draft and restore focus. An Actions menu closes before the parent palette. Own and clean up child windows, event monitors and observers per workspace/window.

Project selection reuses this palette with Back, search, existing root paths and an owning-computer filter. Preserve no-project chat. A local project keeps its owning machine; only chat/GitHub contexts use their existing available-machine choices. Confirm before changing project; typing/filtering/cancelling must not mutate draft context.

## Verification

Behavior regressions cover retained draft identity and attachments, fresh context inheritance, workspace/account isolation, search scope/matching and filtering, selection/cancel, project confirmation and offline preservation. Exercise production controllers with deterministic Debug services. Run the signed native checks, pnpm test/check/bundle and signed iOS Simulator build. Run real light/dark UI interaction in the headless macvm runner, retaining actual screenshots and recordings. Present the approved boards beside native evidence in the original Artboard's Verify page; human visual judgment remains required.
