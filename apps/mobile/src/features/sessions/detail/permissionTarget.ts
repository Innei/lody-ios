// Relative on purpose: this module is imported directly by node --test, which
// does not resolve the `@/` alias. Keep it free of aliased value imports.
import type {
  EntrySummary,
  PermissionResult,
  PermissionTarget,
  PermissionTargetState,
} from '../../../models/session.ts';

export type {
  PermissionResult,
  PermissionTarget,
  PermissionTargetState,
} from '../../../models/session.ts';

export type PermissionTargetSource = (
  onState: (state: PermissionTargetState) => void,
) => () => void;

type Settlement =
  { status: 'cancelled' } | { status: 'completed'; value: PermissionResult };

export function firstPermissionTarget(entries: readonly EntrySummary[]) {
  for (const entry of entries)
    for (const item of entry.items) {
      if (item.type !== 'tool_call' || !('permission' in item)) continue;
      if (!item.permission?.pending) continue;
      return {
        entryId: entry.id,
        itemId: item.itemId,
        requestId: item.permission.requestId,
        kind: item.kind,
        title: item.title,
        path: item.path,
      } satisfies PermissionTarget;
    }
  return undefined;
}

/**
 * One gate per chat mount. Closing the sheet by hand stops automatic reopening
 * until the user leaves and returns; the transcript row stays a manual way in.
 */
export function createPermissionGate() {
  const answered = new Set<string>();
  let open = false;
  let dismissed = false;
  return {
    shouldOpen(target: Pick<PermissionTarget, 'requestId'>) {
      return !open && !dismissed && !answered.has(target.requestId);
    },
    opened() {
      open = true;
    },
    settled(result: Settlement) {
      open = false;
      if (result.status === 'cancelled') dismissed = true;
      else if (result.value) answered.add(result.value.requestId);
    },
  };
}
