import { t } from '../i18n/index.ts';
import type { Catalog, Project, Session } from '../models/catalog.ts';
import type { CreationOptions } from '../models/send.ts';

export type { Catalog, Project, Session } from '../models/catalog.ts';
export type {
  Capability,
  CapabilityChoice,
  CreationOptions,
} from '../models/send.ts';
type Row = { key: unknown[]; value?: unknown };
const object = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
const text = (value: unknown): string =>
  typeof value === 'string' ? value : '';
const stamp = (value: unknown): number | undefined =>
  typeof value === 'number' && Number.isFinite(value) ? value : undefined;
const diffOf = (value: unknown) => {
  const change = object(object(value).allChange);
  const add = stamp(change.add) ?? 0,
    del = stamp(change.del) ?? 0;
  return add || del ? { add, del } : undefined;
};
export function projectRows(rows: Row[], mode: string): Catalog {
  const projects: Project[] = [],
    sessions: Session[] = [],
    machineIds = new Set<string>();
  if (mode !== 'meta') {
    for (const row of rows) {
      if (row.key[0] !== 'localProject' || row.value === undefined) continue;
      const value = object(row.value),
        id = text(row.key[1]);
      if (id)
        projects.push({
          id: `${mode}:local:${id}`,
          machineId: mode,
          name: text(value.name) || id,
          rootPath: text(value.rootPath),
        });
    }
    return { projects, sessions, machineIds: [] };
  }
  const active = new Set<string>();
  const metadata = new Map<string, Record<string, unknown>>();
  for (const row of rows) {
    const id = text(row.key[1]);
    if (row.key[0] === 'e' && row.value === true) active.add(id);
    if (row.key[0] !== 'm' || !id) continue;
    const fields =
      metadata.get(id) ?? (Object.create(null) as Record<string, unknown>);
    if (row.key.length === 2) Object.assign(fields, object(row.value));
    else if (typeof row.key[2] === 'string') {
      if (row.value === undefined) delete fields[row.key[2]];
      else fields[row.key[2]] = row.value;
    }
    metadata.set(id, fields);
  }
  for (const [id, value] of metadata) {
    if (!active.has(id)) continue;
    if (id.startsWith('machine-')) {
      const machineId = id.slice(8);
      machineIds.add(machineId);
      // Match the CLI's legacy metadata + machine Flock project merge.
      for (const [localId, item] of Object.entries(
        object(value.localProjects),
      )) {
        const project = object(item);
        projects.push({
          id: `${machineId}:local:${localId}`,
          machineId,
          name: text(project.name) || localId,
          rootPath: text(project.rootPath),
        });
      }
    }
    if (!id.startsWith('session-') || id.startsWith('session-comment-'))
      continue;
    const machineId = text(value.machineId),
      project = object(value.project);
    const localId = text(project.localProjectId),
      repo = text(project.repoFullName) || text(value.repoFullName);
    const projectId =
      project.kind === 'local' && localId
        ? `${machineId}:local:${localId}`
        : repo
          ? `github:${repo}`
          : `${machineId}:unassigned`;
    sessions.push({
      cliType: text(value.cliType),
      agentType: text(value.agentType),
      resume: text(value.acpSessionId),
      id: text(value.id) || id.slice(8),
      machineId,
      title: text(value.title) || t('session.untitled'),
      status:
        text(value.status) ||
        text(object(value.status).type) ||
        t('session.statusUnknown'),
      archived: value.isArchived === true,
      pinned: value.isPinned === true,
      projectId,
      createdAt: text(value.createdAt),
      lastMessageAt: stamp(value.lastMessageAt),
      lastReadAt: stamp(value.lastReadAt),
      awaitingUserSince: stamp(value.awaitingUserSince),
      branchName: text(value.branchName) || undefined,
      diff: diffOf(value.diffStats),
    });
    projects.push({
      id: projectId,
      machineId,
      name: repo || (localId ? t('project.local') : t('project.unassigned')),
      rootPath: '',
    });
  }
  return {
    projects: [...new Map(projects.reverse().map((p) => [p.id, p])).values()],
    sessions,
    machineIds: [...machineIds],
  };
}

export function capabilityFor(
  options: Pick<CreationOptions, 'capabilities'> | undefined,
  agent: { machineId: string; cliType: string; agentType: string } | undefined,
) {
  if (!options || !agent) return undefined;
  return options.capabilities.find(
    (c) =>
      c.machineId === agent.machineId &&
      c.cliType === agent.cliType &&
      c.agentType === agent.agentType,
  );
}
