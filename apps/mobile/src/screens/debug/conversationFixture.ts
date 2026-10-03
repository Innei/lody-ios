import type { Session } from '@/models/catalog';

type Entry = {
  id: string;
  role: 'user' | 'assistant';
  status: string;
  finished: boolean;
  items: Record<string, unknown>[];
};

export type ConversationFixtureState = {
  sessions: Session[];
  entries: Record<string, Entry[]>;
  offline: boolean;
  failNextFork: boolean;
};

const now = Date.now();
const session = (id: string, title: string, extra: Partial<Session> = {}) => ({
  id,
  title,
  machineId: 'fixture',
  projectId: 'fixture:local:lody',
  status: 'completed',
  archived: false,
  pinned: false,
  createdAt: new Date(now - 600_000).toISOString(),
  lastMessageAt: now - 180_000,
  lastReadAt: now,
  branchName: 'fix/login-loop',
  ...extra,
});
const user = (id: string, text: string): Entry => ({
  id,
  role: 'user',
  status: 'completed',
  finished: true,
  items: [{ itemId: 'text', type: 'text', text }],
});
const reply = (id: string, text: string, finished = true): Entry => ({
  id,
  role: 'assistant',
  status: finished ? 'completed' : 'running',
  finished,
  items: [
    { itemId: 'think', type: 'thought', text: 'Trace the redirect guard.' },
    {
      itemId: 'read',
      type: 'tool_call',
      kind: 'read',
      status: 'completed',
      title: 'Read middleware/session.ts',
    },
    { itemId: 'answer', type: 'text', text },
  ],
});

function initial(): ConversationFixtureState {
  return {
    offline: false,
    failNextFork: false,
    sessions: [
      session('main', 'Fix login redirect loop'),
      session('tests', 'Refactor tests', {
        parentSessionId: 'main',
        status: 'requestPermission',
        awaitingUserSince: now - 60_000,
        lastMessageAt: now - 60_000,
        createdAt: new Date(now - 500_000).toISOString(),
      }),
      session('explore', 'Explore auth flow', {
        parentSessionId: 'main',
        lastMessageAt: now - 720_000,
        lastReadAt: now - 800_000,
        createdAt: new Date(now - 400_000).toISOString(),
      }),
      session('cookie', 'Why does the cookie expire?', {
        parentSessionId: 'main',
        childSessionPlacement: 'side-panel',
        createdAt: new Date(now - 300_000).toISOString(),
      }),
      session('legacy', 'Old fixture cleanup', {
        parentSessionId: 'main',
        archived: true,
      }),
    ],
    entries: {
      main: [
        user('m1', 'Users bounce between /login and /callback. Fix it.'),
        reply(
          'm2',
          'The loop comes from `refreshSession()` clearing the cookie before the redirect guard reads it. I split the work: a tab rewrites the auth specs while I patch the middleware.',
        ),
      ],
      tests: [
        user('t1', 'Rewrite the auth specs around the new refresh order.'),
        reply(
          't2',
          'Updated 6 cases in `auth.spec.ts`. Waiting for approval to delete the legacy fixtures.',
          false,
        ),
      ],
      explore: [
        user('e1', 'Map every caller of verifyToken.'),
        reply(
          'e2',
          'Six callers run inside the middleware; two touch the cookie in the wrong order.',
        ),
      ],
      cookie: [
        user('c1', 'Why does the cookie expire after 5 minutes at all?'),
        reply(
          'c2',
          '`SESSION_TTL` is 300 s in the dev env file. Production reads 7 days from the server config.',
        ),
      ],
      legacy: [],
    },
  };
}

let state = initial();
const listeners = new Set<() => void>();

export const conversationFixture = {
  get: () => state,
  subscribe(listener: () => void) {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  },
  update(
    next: (current: ConversationFixtureState) => ConversationFixtureState,
  ) {
    state = next(state);
    listeners.forEach((listener) => listener());
  },
  reset() {
    conversationFixture.update(initial);
  },
  addSession(
    extra: Partial<Session> & { id: string; title: string },
    entries: Entry[],
  ) {
    conversationFixture.update((current) => ({
      ...current,
      sessions: [
        ...current.sessions,
        session(extra.id, extra.title, {
          createdAt: new Date().toISOString(),
          lastMessageAt: Date.now(),
          ...extra,
        }),
      ],
      entries: { ...current.entries, [extra.id]: entries },
    }));
  },
  send(id: string, text: string) {
    conversationFixture.update((current) => ({
      ...current,
      sessions: current.sessions.map((s) =>
        s.id === id && s.title === 'New Tab'
          ? { ...s, title: text.slice(0, 40), lastModel: undefined }
          : s,
      ),
      entries: {
        ...current.entries,
        [id]: [
          ...(current.entries[id] ?? []),
          user(`u-${Date.now()}`, text),
          reply(
            `a-${Date.now()}`,
            'Fixture reply: looked at the branch and summarized it.',
          ),
        ],
      },
    }));
  },
  remove(id: string) {
    conversationFixture.update((current) => ({
      ...current,
      sessions: current.sessions.filter((s) => s.id !== id),
    }));
  },
};
