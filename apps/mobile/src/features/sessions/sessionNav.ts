import type { Catalog, Session } from '../../models/catalog.ts';

export type SessionNavIntent =
  | { kind: 'open'; session: Session }
  | {
      kind: 'create';
      workspaceId: string;
      catalog: Catalog;
      projectId?: string;
    };

type Stored = SessionNavIntent & {
  resolve: () => void;
};

let queue: Stored[] = [];
let handler: ((intent: SessionNavIntent) => Promise<void>) | null = null;

function enqueue(intent: SessionNavIntent) {
  return new Promise<void>((resolve) => {
    queue = [...queue, { ...intent, resolve }];
    void flush();
  });
}

async function flush() {
  if (!handler) return;
  const next = queue[0];
  if (!next) return;
  queue = queue.slice(1);
  const { resolve, ...intent } = next;
  try {
    await handler(intent);
  } catch {
    /* hook toasts; request still settles */
  }
  resolve();
  void flush();
}

export function requestOpenSession(session: Session) {
  return enqueue({ kind: 'open', session });
}

export function requestNewSession(
  workspaceId: string,
  catalog: Catalog,
  projectId?: string,
) {
  return enqueue({ kind: 'create', workspaceId, catalog, projectId });
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
