import type { Flock } from '@loro-dev/flock-wasm/base64';
import type { MentionCatalog, MentionItem } from '../models/mentions';
import { openSettings } from './settings';
import { readRole, readableRole } from '../protocol/agent-roles';
import type { MachinePresence } from '../models/machines';

// Shared workspace catalog owner for Role consumers. Authorization is checked
// from the fresh row on every read; the UI never supplies Role instructions.
export async function workspaceRoleMentions(
  workspaceId: string,
  userId: string,
  machines: Map<string, Flock>,
  getGrant: Parameters<typeof openSettings>[1],
  getPresence: () => MachinePresence,
): Promise<MentionCatalog> {
  const { flock } = await openSettings(
    `${workspaceId}:wf:workspace`,
    getGrant,
    AbortSignal.timeout(30000),
  );
  return roleMentions(flock.scan(), userId, machines, getPresence());
}

export function roleMentions(
  rows: { key: unknown[]; value?: unknown }[],
  userId: string,
  machines: Map<string, Pick<Flock, 'get'>>,
  presence: MachinePresence,
): MentionCatalog {
  if (presence.state !== 'live')
    return { items: [], truncated: false, incomplete: true };
  const items: MentionItem[] = [];
  for (const row of rows) {
    if (
      row.key.length !== 2 ||
      row.key[0] !== 'agentRole' ||
      !row.value ||
      typeof row.value !== 'object'
    )
      continue;
    const role = readRole(row.value, row.key[1]);
    if (!role || !readableRole(role, userId)) continue;
    for (const target of role.targets) {
      if (!presence.onlineMachineIds.includes(target.machineId)) continue;
      const agent = machines
        .get(target.machineId)
        ?.get(['agentConfig', target.agentConfigId]) as
        Record<string, unknown> | undefined;
      if (
        !agent ||
        agent.id !== target.agentConfigId ||
        agent.machineId !== target.machineId
      )
        continue;
      const multi = role.targets.length > 1;
      const path = multi ? `${role.id}@${target.machineId}` : role.id;
      let name = role.name;
      if (multi) name = target.alias || `${role.name} · ${target.machineId}`;
      items.push({
        path,
        name,
        roleName: role.name,
        kind: 'role',
        subtitle: role.description?.slice(0, 140) || String(agent.name ?? ''),
        insertText: `@role:${path}`,
      });
    }
  }
  items.sort(
    (a, b) => a.name.localeCompare(b.name) || a.path.localeCompare(b.path),
  );
  return { items, truncated: false, incomplete: false };
}
