# iOS OSS feature completion

Date: 2026-10-12. Protocol reference: LodyAI/Lody desktop `987962e77022df6a800f4e889f124b51f6eb8056`.

## Delivery scope

Complete the open product features and reported send, preview and assistant-selection failures. Existing rename, history editing, search, pinned grouping, PR/CI and proposed-plan implementations are retained and verified against their acceptance criteria. Parent tracking issues are not separate implementations.

Independent feature owners work in the current checkout. Shared files have one writer; an overlapping change waits for handoff. The existing macOS application, experiments and pre-existing edits remain user-owned. No worktrees are created.

| Surface           | Product outcome                                                                               | Existing ownership boundary                                             |
| ----------------- | --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Feedback          | User reviews a private-data-free report before opening a public issue or sharing it           | Settings, native image picker and report domain                         |
| Preview           | Visible close action; failed revoke leaves a retry path                                       | Shared native chip and existing preview control                         |
| Creation          | All valid desktop assistants; MCP/Role picks and worktree context survive first-turn dispatch | Runtime catalogs, native composer and shared CreateSession form         |
| Sending and queue | Uncertain delivery can be inspected; queued text can be deleted, edited and reordered safely  | Single owned outbox, session Loro document and machine dispatch pointer |
| Transcript        | Reported usage, goal, schedule, file and author data remain distinguishable from absent data  | Native transcript and sanitized runtime projections                     |
| Subtasks          | Full run history remains bound to its parent/task/run and releases readers on exit            | Existing session replica, read-only native transcript                   |
| Session tools     | Fork, history pin, unread and archive preferences follow desktop semantics                    | Metadata and authoritative session control                              |
| Shortcuts         | Workspace templates preserve stable references and use one expansion path                     | Official shortcut catalog/body streams and mention compiler             |
| Schedules         | Tasks use the upstream rules, destinations, registry and history                              | Machine-executed schedules; no iOS background scheduler                 |
| Projects          | Remote cleanup preserves dirty worktrees and original projects                                | Official project lifecycle protocol and native credential broker        |
| Providers         | Config, authentication and runtime operations use the actual machine contracts                | Machine permissions and encrypted secret envelopes                      |
| Teams             | Every member/invitation action is scoped to the fresh account, workspace and role             | Official Cloud API and Keychain-native request boundary                 |

## Shared integration

Cloud protocol stays in `packages/cloud-runtime`; RN receives sanitized models. Native capabilities remain in LodyKit. Each management domain exposes a typed request and one registered native command. Swift replaces caller-supplied user identity with the active runtime identity, and runtime dispatch checks the workspace again. Account operations use a fixed native API allowlist and fresh Keychain/session fencing.

No protocol name is inferred from a desktop IPC name. Schedule and queue operations that use shared documents continue to use those documents. Shortcuts obtain their own authorized body-stream grants. A lost write acknowledgement stays uncertain until an authoritative read proves its result; recovery never automatically replays a write.

Native preparation ownership is installed before billing or upload awaits and ends before the runtime send command begins. Cancellation after that boundary requires authoritative reconciliation. Every replaced native view advances its generation. Native send, edit, schedule, project and shortcut deadlines are 130 seconds around runtime operations bounded at 120 seconds; other managed commands allow 90 seconds around the existing 65-second request bound.

## Verification

Capture CreateSession parity from the previous signed build before changing its native form. Add independently resettable English offline scenes at the production boundary, cover light/dark and every changed shared host, and record both screenshots and temporal behavior. After integration, run `pnpm check`, `pnpm test`, `pnpm bundle`, signed `pnpm verify:build`, native checks and affected UI cases through the managed Simulator leases. Compare the new CreateSession capture with the saved baseline. Publish product-outcome evidence through the existing acceptance exporter; automated gates are supporting checks.

Simulator evidence establishes UI and deterministic protocol behavior. It cannot establish production machine interoperability, physical haptics or the absence of a TestFlight-only crash; those limits remain explicit in the delivery report.
