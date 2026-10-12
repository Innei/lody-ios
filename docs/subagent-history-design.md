# Subagent execution records

Issue #64 uses Lody OSS `987962e77022df6a800f4e889f124b51f6eb8056`.
`packages/shared/src/ai.ts` defines `subagent_task.run` with the root ACP
`sessionId`, authoritative snapshot, progress and retained text/thought/tool/plan
items. `specs/subagent-events.md` makes `taskId` the opaque execution `runId`;
it explicitly leaves run-addressed output RPCs unavailable. Legacy task rows
therefore keep their summary and explain that individual steps are unavailable.

The existing Swift-owned runtime and session replica remain the only transport
owners. A read-only `subagentHistory` command reads that replica. A detail view
binds the parent Lody session, parent turn, history entry, task item and run ACP
session. It subscribes to document invalidations and refreshes bounded pages;
unmount, run changes and runtime recovery release the old subscription. Cursors
are scoped to that exact identity and never cross runs. Reused legacy task IDs
or explicitly shared spawning tool IDs can offer distinct run selections; names
and descriptions never establish identity.

The sheet keeps its task brief, result and state, and uses `NativeChat` in a
read-only mode for retained execution items. Tool results use the existing detail
blocks. Earlier records load on demand; long text is paged without discarding its
remaining characters. Provider truncation, loading, empty history, unsupported
history, failed reads and lost observation remain separate visible states.
Normalized v1 output contains assistant messages only; the app does not invent
child user messages from the task brief.

Offline Debug fixtures use these production components with synthetic service
outcomes. Behavioral checks cover exact ownership, separate runs, paging, updates,
stale replies after switching and subscription cleanup. UI checks capture English
light/dark states and a recording; no task is created, restarted or cancelled.
