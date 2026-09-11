import type { PullRequestPreviewData } from '../../models/pull-request.ts';

export type PullRequestState = {
  data?: PullRequestPreviewData;
  loading: boolean;
  error?: string;
};
export type PullRequestSource = ReturnType<typeof createPullRequestSource>;

/** One in-memory snapshot per presented PR; old requests cannot cross its lifetime. */
export function createPullRequestSource(
  load: () => Promise<PullRequestPreviewData>,
  comment: (body: string) => Promise<void>,
  initial?: PullRequestPreviewData,
) {
  let state: PullRequestState = { data: initial, loading: false };
  let active = true;
  let posting = false;
  let inFlight: Promise<void> | undefined;
  const listeners = new Set<() => void>();
  function publish(next: PullRequestState) {
    if (!active) return;
    state = next;
    listeners.forEach((listener) => listener());
  }
  function refresh() {
    if (!active) return Promise.resolve();
    if (inFlight) return inFlight;
    publish({ ...state, loading: true, error: undefined });
    inFlight = (async () => {
      try {
        publish({ data: await load(), loading: false });
      } catch (error) {
        publish({
          ...state,
          loading: false,
          error: error instanceof Error ? error.message : 'unavailable',
        });
      } finally {
        inFlight = undefined;
      }
    })();
    return inFlight;
  }
  return {
    getSnapshot: () => state,
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    refresh,
    async postComment(body: string) {
      if (!active || posting) throw new Error('unavailable');
      posting = true;
      try {
        await comment(body);
        // Refresh is independent of the write acknowledgement. A failed read must
        // not invite resending a comment that GitHub already accepted.
        if (inFlight) void inFlight.then(refresh);
        else void refresh();
      } finally {
        posting = false;
      }
    },
    dispose() {
      active = false;
      state = { loading: false, error: 'unauthorized' };
      listeners.forEach((listener) => listener());
      listeners.clear();
    },
  };
}
