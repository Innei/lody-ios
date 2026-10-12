# Send recovery and queue controls

Scope: #53, #63 and #28. Protocol baseline: official Lody OSS
`987962e77022df6a800f4e889f124b51f6eb8056`.

The existing native-owned session replica and durable outbox remain the owners.
Recovery reads a fresh bounded Streams document, excluding unsent local edits.
It recognizes a queued turn or authoritative history by the same `userTurnId`;
it never appends history, publishes a dispatch pointer or repeats Machine RPC.
Unknown receipt controls offer a read-only check and an explicit way to release
the local confirmation lock. Releasing it does not cancel remote execution or
resend the draft.

Queue commands resolve the stable `userTurnId` against the fresh `mq` movable
list. Editing writes the official `isEditing` and `editingStartedAt` fields with
the CLI's five-minute lease. Only the editor that acquired that timestamp may
save or release it. Saving changes task/prompt/text input blocks and preserves
attachments and run configuration. Moves use the movable list; deletion changes
only the selected container. Each change publishes the existing queue watermark.

The OSS queue has no atomic remove-if-unclaimed RPC. An absent queue row alone
cannot prove that the machine did not already take it. Deletion therefore keeps
an execution-unconfirmed receipt until a read shows authoritative history, and
offers a check/dismiss path. A claimed turn is reported as started; deletion never
calls Stop or Steer. An uncertain append is reconciled rather than replayed.

Native preparation/upload cancellation is scoped to the exact send ID and stops
before the runtime write boundary. Its task retains cancellation through billing
and upload, aborts any owned multipart upload, and releases only owned temporary
resources. Once handed to the session runtime, cancellation cannot claim success.

Callers: `sendTurn`, foreground/background outbox dispatch, `useSessionSend`, a
queue hook, native composer queue rows, SessionScreen, typed LodyKit commands and
events, and offline send fixtures. Behavioral tests cover read-only recovery,
identity/order/attachment preservation, lease expiry/conflict, claimed-message
races, unknown append reconciliation, and cancellation preventing a late queue
write. UI checks cover native edit/save/cancel, move/delete, recovery actions,
and unchanged Steer/Stop animation semantics.
