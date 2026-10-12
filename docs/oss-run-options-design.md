# MCP, Agent Role and session worktree selection

Issues: #12, #19 and #14. Protocol baseline: LodyAI/Lody `987962e77022df6a800f4e889f124b51f6eb8056`.

## Product contract

The app selects existing Roles created on desktop. It does not add another Role editor. Each row shows the Role name, bound assistant and pinned model / permission values. Unavailable bindings stay visible with a reason. Existing sessions offer only Roles bound to their exact machine and agent configuration; new sessions may choose another assistant on the selected machine.

Selecting a Role applies its pinned run configuration. Changing a pinned model, permission or other option explicitly clears Role provenance; clearing the Role itself preserves the user's current run values. Selection freezes the safe projected run values and id/revision in the local draft. Runtime verifies the fresh Role's revision, visibility and exact binding before a write. An edited or deleted Role fails before durable dispatch and leaves the draft available. Continuing an existing Role conversation inherits its durable input configuration and does not reread or replay a Role instruction.

Supported Roles contain at most 64 safe options with nonempty string values. Complete selections may combine these pins with ordinary values up to 128 options. The RN picker, shared native form, creation and final send configuration share these key/value checks; an unsupported selection preserves its fields for correction and cannot create a session or dispatch a turn. Malformed Role ids longer than 256 characters and revisions that are not safe positive integers never enter the selectable catalog. Reasoning effort values use the same 512-character bound as their underlying option.

The Role prompt prefix is resolved inside the owned runtime and enters only the initial turn of a newly created session. It is never replayed when a Role is selected in an existing conversation. MCP uses the workspace catalog's stable ids; undefined inherits the previous selection and an explicit empty array turns all servers off. New-session defaults are copied from the workspace catalog once and later settings edits cannot alter an already frozen turn. The picker omits an empty catalog and rejects invalid or deleted explicit ids before writing; MCP commands, headers and credentials never enter UI or the App Group snapshot.

Local project worktrees use the official `local-project/git-state` RPC and OSS availability rule (`git == true` and at least one branch). The grouped row offers Current directory / New worktree only when the selected remote project qualifies. Creation persists `ProjectRef.useWorktree: true` and `isWorktree: true`; the remote machine owns Git operations. GitHub projects retain the required base branch and their existing worktree behavior. Chat has no worktree control.

## Data and ownership

```
┌─────────────────────┐
│ Workspace Role / MCP│
│ and machine catalogs│
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ Native run pickers  │
│ Chat / Create / Share│
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ Local draft/outbox  │
│ frozen selection    │
└──────────┬──────────┘
           ▼
      ◆ Fresh valid? ◆
       /            \\
      ▼              ▼
┌───────────┐  ┌──────────────┐
│ Persist   │  │ Keep draft / │
│ then RPC  │  │ show reason  │
└───────────┘  └──────────────┘
```

`runtime/agent-roles.ts` is the shared visibility/normalization owner for mention, picker and schedule consumers. `runtime/run-options.ts` projects safe catalogs and validates explicit turn selections. `models/run-options.ts` defines the wire shapes. The existing create models, preference logic and shared native CreateSession form carry MCP / Role / worktree state. Project preferences own Role/MCP/worktree choices; the cross-project model cache contains only ordinary model settings. Account and workspace keys remain isolated.

Callers requiring updates are SessionScreen's composer and send choice, native ChatComposerModelPanel and CreateSession form, CreateSessionScreen option loading, createDraft, foreground/outbox dispatch, ShareSnapshot/ShareCoordinator stale-selection checks and creation metadata. The native form and picker implementations are reused by the Share Extension without network or Keychain access. No new dependency, bridge package, local Git execution or credential projection is introduced.

A failed optional Role/MCP directory lookup preserves ordinary assistant creation. The shared form shows a retry row, while existing chat shows a composer notice and a Retry run options action under More. Chosen Role provenance, frozen values and MCP ids stay in the draft during failure; unresolved explicit selections still fail validation. The chat hook discards late results after an account, workspace or session change.

## Verification

Behavior checks cover workspace/private Role visibility, exact provider binding, revision rejection, frozen values and explicit None, prompt-prefix first-turn behavior, MCP inherit/clear/deleted ids, remote worktree metadata and isolation of project preferences. Offline native fixtures exercise the composer panel and shared new-session form (project and Chat); light/dark screenshots and temporal interaction evidence use the existing UI Verify runner. Capture the previous-build create-parity baseline before changing the shared form, then compare it with parity-diff.py.

`run-options.py` also injects catalog failure and successful retry at the real service boundary in chat and creation. `share-probe.py --run-options` separately opens the actual Share Extension from a system share sheet with the containing app stopped. It checks cached Role apply/clear/reselect, MCP toggles and local worktree, then validates the inbox manifest and app handoff. Native ShareStore checks supplement this extension UI evidence.

Boundary regressions retain complete 64-option Unicode Role configurations through creation and send, reject unsupported Roles and 129-option combined selections before writes, and exercise a supported escaped 128-option map plus 64 frozen pins below the finite 2 MiB native transport ceiling. The native create/share/composer checks cover the same full-choice boundary in production Swift. The creation fixture includes both the current assistant and a legacy Claude assistant for actual picker switching.
