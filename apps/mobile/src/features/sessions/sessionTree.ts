import type { Session } from '../../models/catalog.ts';

/** Input order is the list's ranking. A group takes its freshest member's place. */
export function sessionTree(sessions: Session[], allSessions: Session[]) {
  const all = new Map(allSessions.map((session) => [session.id, session]));
  const visible = new Map(sessions.map((session) => [session.id, session]));
  const parentOf = (session: Session): string | undefined => {
    // Contained Tabs keep their existing entry until iOS has a Tab navigation host.
    if (session.parentSessionId) return;
    let id = session.openedByRootSessionId || session.openedBySessionId;
    const seen = new Set<string>();
    while (id && all.get(id)?.parentSessionId && !seen.has(id)) {
      seen.add(id);
      id = all.get(id)?.parentSessionId;
    }
    const opener = id ? visible.get(id) : undefined;
    if (
      opener &&
      opener.projectId === session.projectId &&
      opener.archived === session.archived
    )
      return opener.id;
  };
  // ponytail: long chains take quadratic walks; memoize roots if catalog profiling warrants it.
  const rootOf = (session: Session) => {
    const seen = new Set([session.id]);
    let root = session;
    let id = parentOf(root);
    while (id) {
      if (seen.has(id)) return session.id;
      seen.add(id);
      root = visible.get(id)!;
      id = parentOf(root);
    }
    return root.id;
  };
  const roots = new Map(
    sessions.map((session) => [session.id, rootOf(session)]),
  );
  const groups = new Map<string, { session: Session; children: Session[] }>();
  for (const session of sessions) {
    const root = roots.get(session.id)!;
    const group = groups.get(root) ?? {
      session: visible.get(root)!,
      children: [],
    };
    if (root !== session.id) group.children.push(session);
    groups.set(root, group);
  }
  return [...groups.values()];
}
