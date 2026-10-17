// Relative on purpose: this module is imported directly by node --test, which
// does not resolve the `@/` alias. Keep it free of aliased value imports.
import type {
  EntrySummary,
  PermissionResult,
  PermissionTarget,
  PermissionTargetState,
} from '@lody/cloud-runtime/models/session';

export type {
  PermissionResult,
  PermissionTarget,
  PermissionTargetState,
} from '@lody/cloud-runtime/models/session';

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
        options: item.permission.options,
        kind:
          item.permission.kind === 'ask_user_question'
            ? 'ask_user_question'
            : item.kind,
        ...(item.permission.questionMeta
          ? { questionMeta: item.permission.questionMeta }
          : {}),
        title: item.title,
        path: item.path,
      } satisfies PermissionTarget;
    }
  return undefined;
}

/**
 * One gate per chat visit. Closing the sheet by hand stops automatic reopening
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
    canPrompt() {
      return !open && !dismissed;
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

export type PermissionChannel = {
  gate: ReturnType<typeof createPermissionGate>;
  source: PermissionTargetSource;
  publish: (state: PermissionTargetState) => void;
  retain: () => () => void;
};

const channels = new Map<string, PermissionChannel>();

// A layout change remounts the chat while its permission sheet stays open; the
// sheet and the new mount must share one gate and one target source.
export function permissionChannel(sessionId: string): PermissionChannel {
  const existing = channels.get(sessionId);
  if (existing) return existing;
  const listeners = new Set<(state: PermissionTargetState) => void>();
  let state: PermissionTargetState = { ready: false };
  let holders = 0;
  const channel: PermissionChannel = {
    gate: createPermissionGate(),
    source(onState) {
      listeners.add(onState);
      onState(state);
      return () => {
        listeners.delete(onState);
      };
    },
    publish(next) {
      state = next;
      for (const notify of listeners) notify(state);
    },
    retain() {
      holders++;
      let released = false;
      return () => {
        if (released) return;
        released = true;
        holders--;
        if (!holders && channels.get(sessionId) === channel)
          channels.delete(sessionId);
      };
    },
  };
  channels.set(sessionId, channel);
  return channel;
}
