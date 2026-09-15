import type { Catalog, Session } from '../../models/catalog.ts';

export type SessionNavIntent =
  | { kind: 'open'; session: Session }
  | {
      kind: 'create';
      workspaceId: string;
      catalog: Catalog;
      projectId?: string;
      context?: 'project' | 'chat';
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

export function requestOpenSession(session: Session) {
  return enqueue({ kind: 'open', session });
}

export function requestNewSession(
  workspaceId: string,
  catalog: Catalog,
  projectId?: string,
  context?: 'project' | 'chat',
) {
  return enqueue({ kind: 'create', workspaceId, catalog, projectId, context });
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
