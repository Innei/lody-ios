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
let handler: ((intent: SessionNavIntent) => Promise<void>) | null = null;
let flushing = false;

function enqueue(intent: SessionNavIntent) {
  return new Promise<void>((resolve) => {
    queue = [...queue, { ...intent, resolve }];
    void flush();
  });
}

async function flush() {
  if (flushing || !handler) return;
  flushing = true;
  try {
    while (queue.length) {
      const next = queue[0];
      queue = queue.slice(1);
      const { resolve, ...intent } = next;
      try {
        await handler(intent);
      } catch {
        /* hook toasts; request still settles */
      }
      resolve();
    }
  } finally {
    flushing = false;
    if (queue.length && handler) void flush();
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

export function subscribeSessionNav(
  next: (intent: SessionNavIntent) => Promise<void>,
) {
  handler = next;
  void flush();
  return () => {
    if (handler === next) handler = null;
  };
}
