# Session tools

Reference: official Lody OSS `987962e77022df6a800f4e889f124b51f6eb8056`,
`message-schemas.ts`, `schema.ts`, `session-fork-service.ts`,
`use-session-actions.ts`, `session-pin.tsx`, and `auto-archive-pr.ts`.

Fork sends `session/fork` once, with the assistant history entry ID, a stable
target session ID, the requesting user, and `targetContext.kind` (`shared` or
`new-worktree`). The machine clones the source history and frozen input config,
including its Role and MCP selection. iOS never copies history or runs Git.
New-worktree is offered only when the authoritative agent capability advertises
`sessionForkWorktree`. A dirty-source confirmation resubmits the same target ID
with `acknowledgeDirtySource: true`; it does not make a second destination.

```text
┌──────────────────────────┐
│ One explicit fork RPC    │
└────────────┬─────────────┘
             ▼
      ◆ Response received? ◆
         /              \
        ▼                ▼
┌────────────────┐ ┌───────────────────────┐
│ Accepted       │ │ Unknown delivery      │
│ Read target    │ │ Check target; no replay│
└───────┬────────┘ └───────────┬───────────┘
        └─────────┬───────────┘
                  ▼
      ◆ Target document state? ◆
           /          |          \
          ▼           ▼           ▼
┌─────────────┐ ┌────────────┐ ┌────────────────────┐
│ preparing   │ │ failed     │ │ Origin notice and  │
│ Wait/check  │ │ User retry │ │ no forkOperation   │
└─────────────┘ └────────────┘ │ Open target session│
                              └────────────────────┘
```

The target `forkOperation` uses the OSS `preparing`/`failed` shape. Successful
completion requires the operation to be cleared and the cloned history to have
the target's own `session-fork-origin:<target>` notice with its matching source.
An origin copied from a previously forked source is not completion evidence.
A lost RPC response is an unknown outcome,
never a reason to replay automatically. Closing the sheet stops polling only;
the machine owns the accepted operation. Explicit retry is offered only after a
known rejection/failure. Archived sources are rejected before RPC.

Content pin remains available on readable archived conversations. It writes the
source session metadata's `pinnedHistoryId`, with an empty
string to clear it. Only an actual user history entry can be pinned. The native
chat holds its preview above the transcript and scrolls to that entry; it does
not change list `isPinned`, ordering, or create a duplicate history entry.

Mark unread writes `lastReadAt = lastMessageAt - 1` and leaves activity time
alone. This is a separate operation from the monotonic mark-read helper. After
acknowledgement, clear the current user's local viewed watermark so Inbox can
show the unread emphasis immediately.

Automatic archive settings default off and are local per account, matching OSS.
The watcher acts only on that user's sessions in the selected workspace, only
after a PR URL already observed here changes to the enabled terminal status.
It keeps archived sessions in its baseline, resets on account/workspace change,
and never retroactively archives on startup, restore, or preference enablement.
Archive uses the existing protocol and machine cleanup, with its existing
worktree cleanup consequences stated beside the settings.

Audit existing rename, edit-and-resend, transcript find, and list pin rather than
replacing them. Rename must keep the current title on append failure, and an
empty edited title resolves to the locale's untitled label. Queue/guide settings
already use the shared submit routing and stay in that existing path.

Validation: isolated protocol tests for fork completion/unknown outcomes, content
pin, unread and failed rename writes; local state and PR transition tests;
English offline native fixtures exercise Fork, pin/unpin, unread and settings.
Full builds and combined verification run once after the parallel modules merge.
