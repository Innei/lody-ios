import type { Catalog, Session } from '../../models/catalog.ts';

export type SessionNavIntent =
  | { kind: 'share'; workspaceId: string; sessionId: string }
  | { kind: 'open'; session: Session; findQuery?: string }
  | {
      kind: 'create';
      workspaceId: string;
      catalog: Catalog;
      projectId?: string;
      context?: 'project' | 'chat';
      morphSourceLabel?: string;
    };

type Stored = SessionNavIntent & {
  resolve: () => void;
};

let queue: Stored[] = [];
type Handler = (intent: SessionNavIntent, signal: AbortSignal) => Promise<void>;
let handlers: { handle: Handler; controller: AbortController }[] = [];
let flushing = false;

function enqueue(intent: SessionNavIntent) {
  return new Promise<void>((resolve) => {
    queue = [...queue, { ...intent, resolve }];
    void flush();
  });
}

async function flush() {
  if (flushing || !handlers.length) return;
  flushing = true;
  try {
    while (queue.length) {
      const handler = handlers.at(-1);
      if (!handler) return;
      const next = queue[0];
      queue = queue.slice(1);
      const { resolve, ...intent } = next;
      const { signal } = handler.controller;
      let cancel = () => {};
      const cancelled = new Promise<void>((done) => {
        cancel = done;
        signal.addEventListener('abort', cancel, { once: true });
      });
      try {
        await Promise.race([handler.handle(intent, signal), cancelled]);
      } catch {
        /* hook toasts; request still settles */
      } finally {
        signal.removeEventListener('abort', cancel);
      }
      resolve();
    }
  } finally {
    flushing = false;
    if (queue.length && handlers.length) void flush();
  }
}

export function requestOpenSession(session: Session, findQuery?: string) {
  return enqueue({ kind: 'open', session, findQuery });
}
export function requestShareSession(workspaceId: string, sessionId: string) {
  // A transient share can open while the navigation mailbox awaits an open page.
  const handler = handlers.at(-1);
  if (!handler) return Promise.reject(new Error('Navigation unavailable'));
  return handler.handle(
    { kind: 'share', workspaceId, sessionId },
    handler.controller.signal,
  );
}

export function requestNewSession(
  workspaceId: string,
  catalog: Catalog,
  projectId?: string,
  context?: 'project' | 'chat',
  morphSourceLabel?: string,
) {
  return enqueue({
    kind: 'create',
    workspaceId,
    catalog,
    projectId,
    context,
    morphSourceLabel,
  });
}

export function subscribeSessionNav(next: Handler) {
  const subscription = { handle: next, controller: new AbortController() };
  handlers = [...handlers, subscription];
  void flush();
  return () => {
    subscription.controller.abort();
    handlers = handlers.filter((handler) => handler !== subscription);
    void flush();
  };
}
