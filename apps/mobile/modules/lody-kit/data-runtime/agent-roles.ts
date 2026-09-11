import type { Flock } from '@loro-dev/flock-wasm/base64';
import type { MentionCatalog, MentionItem } from '../../../src/models/mentions';
import { openSettings } from './settings';

// Shared workspace catalog owner for Role consumers. Authorization is checked
// from the fresh row on every read; the UI never supplies Role instructions.
export async function workspaceRoleMentions(
  workspaceId: string,
  userId: string,
  machines: Map<string, Flock>,
  machineId: string | undefined,
  getGrant: Parameters<typeof openSettings>[1],
): Promise<MentionCatalog> {
  const { flock } = await openSettings(
    `${workspaceId}:wf:workspace`,
    getGrant,
    AbortSignal.timeout(30000),
  );
  return roleMentions(flock.scan(), userId, machines, machineId);
}

export function roleMentions(
  rows: { key: unknown[]; value?: unknown }[],
  userId: string,
  machines: Map<string, Pick<Flock, 'get'>>,
  machineId?: string,
): MentionCatalog {
  const items: MentionItem[] = [];
  for (const row of rows) {
    if (
      row.key.length !== 2 ||
      row.key[0] !== 'agentRole' ||
      !row.value ||
      typeof row.value !== 'object'
    )
      continue;
    const role = row.value as Record<string, unknown>;
    const validText = (value: unknown): value is string =>
      typeof value === 'string' &&
      value.length > 0 &&
      value.length <= 4096 &&
      !/[\x00-\x1f\x7f]/.test(value);
    if (
      role.v !== 1 ||
      role.id !== row.key[1] ||
      !validText(role.id) ||
      /\s/.test(role.id) ||
      !validText(role.name) ||
      !validText(role.ownerUserId) ||
      !validText(role.machineId) ||
      !validText(role.agentConfigId) ||
      !['private', 'workspace'].includes(String(role.visibility)) ||
      (role.visibility !== 'workspace' && role.ownerUserId !== userId) ||
      typeof role.revision !== 'number' ||
      !Number.isFinite(role.revision) ||
      (machineId !== undefined && role.machineId !== machineId)
    )
      continue;
    const agent = machines
      .get(role.machineId)
      ?.get(['agentConfig', role.agentConfigId]) as
      Record<string, unknown> | undefined;
    if (
      !agent ||
      agent.id !== role.agentConfigId ||
      agent.machineId !== role.machineId
    )
      continue;
    const summary =
      typeof role.promptPrefix === 'string'
        ? role.promptPrefix.slice(0, 512)
        : '';
    items.push({
      path: role.id,
      name: role.name,
      kind: 'role',
      subtitle: summary || String(agent.name ?? ''),
      insertText: `@role:${role.id}`,
    });
  }
  items.sort(
    (a, b) => a.name.localeCompare(b.name) || a.path.localeCompare(b.path),
  );
  return { items, truncated: false, incomplete: false };
}
