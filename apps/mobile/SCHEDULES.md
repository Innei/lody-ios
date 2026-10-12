# Scheduled tasks (#66)

The iOS client manages machine-executed schedules in the selected workspace. It
lists/searches definitions, edits their Agent or Role, model, permission options,
machine and project, previews named rules on the machine clock, selects one of
three conversation destinations, and exposes run, pause, resume, delete and result
history. Agent proposals stay proposals until a person reviews the editor and
presses Create.

Protocol reference: Lody OSS commit
`987962e77022df6a800f4e889f124b51f6eb8056`:

- `packages/shared/src/schedule-types.ts`, `schedule-schema.ts` and
  `schedule-registry.ts` define the schedule Loro document and workspace Flock
  registry (`workspace:sr`). Definitions stream through
  `workspace:schedule:scheduleId`.
- `packages/shared/src/schedule-repository.ts` publishes the definition before
  its fingerprinted registry row. A tombstone wins over a stale edit. Manual
  runs are registry keys `manual/scheduleId/requestId` with stable IDs.
- `packages/shared/src/schedule-recurrence.ts` maps named rules onto
  `manual | once | interval | cron`; aligned steps use cron, other steps retain
  an interval anchor. `schedule-time.ts` skips nonexistent DST calendar times
  and uses the first instant of a repeated time. One-off wall input shifts a
  gap forward and selects the earlier repeated instant.
- `packages/components/src/components/schedules/schedules-workspace.tsx` uses
  `ScheduleRepository` directly. `apps/cli/src/lib/schedules/schedule-command-client.ts`
  uses local IPC; there is no remote Schedule Machine RPC to invent.
- `schedule-proposal-notice.tsx` creates with `scheduleId = proposalId`, then
  writes a receipt into the source history. `schedule-proposal-target.ts`
  resolves the current conversation configuration and explicit Role overrides.

`scheduleCommand` runs in LodyKit's native-owned data runtime. Short-lived grants
stay there. RN receives display projections only. Mutations check workspace,
account, ownership and machine protocol support; run/resume require known online
presence. The client never runs a background clock. Writes are never retried
automatically; an explicit retry retains the same schedule/request IDs and draft.
An uncertain acknowledgement stays visible until read-back or retry establishes
the result. A run request is not evidence of a completed execution.

Result history uses the ordinary catalog's `scheduleId` provenance, matching the
desktop surface. Machine-local ledger entries without a published conversation
are not exposed by the upstream remote protocol.
