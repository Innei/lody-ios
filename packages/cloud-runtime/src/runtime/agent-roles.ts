import type { Flock } from '@loro-dev/flock-wasm/base64';
import type { MentionCatalog, MentionItem } from '../models/mentions';
import type { AgentRoleOption, RoleRunConfig } from '../models/run-options';
import type { CreationOptions } from '../models/send';
import { supportsRunConfigOptions } from '../protocol/run-options';
import { openSettings } from './settings';

export type AgentRole = {
  id: string;
  name: string;
  description?: string;
  ownerUserId: string;
  visibility: 'private' | 'workspace';
  machineId: string;
  agentConfigId: string;
  revision: number;
  runConfig: RoleRunConfig;
  runConfigSupported?: boolean;
  promptPrefix?: string;
};

const record = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
const text = (value: unknown): value is string =>
  typeof value === 'string' &&
  value.trim().length > 0 &&
  value.length <= 4096 &&
  !/[\x00-\x1f\x7f]/.test(value);
const sensitiveOptionId =
  /(?:api[_-]?key|auth|bearer|credential|password|passwd|secret|token|\bkey\b|cookie|session[_-]?id|private)/i;

export function readRoleRunConfig(value: unknown): RoleRunConfig {
  const raw = record(value);
  const configEntries: [string, string | boolean][] = [];
  for (const [id, value] of Object.entries(record(raw.configOptionValues))) {
    if (!id.trim() || id.length > 128 || sensitiveOptionId.test(id)) continue;
    if (
      typeof value === 'boolean' ||
      (typeof value === 'string' && value.length <= 512)
    )
      configEntries.push([id, value]);
  }
  const configOptionValues = Object.fromEntries(configEntries);
  const memory = record(raw.memory);
  return {
    ...(text(raw.modelId) ? { modelId: raw.modelId.trim() } : {}),
    ...(text(raw.modeId) ? { modeId: raw.modeId.trim() } : {}),
    ...(Object.keys(configOptionValues).length ? { configOptionValues } : {}),
    ...(text(memory.providerId) &&
    memory.providerId.length <= 100 &&
    text(memory.memoryId) &&
    memory.memoryId.length <= 200
      ? {
          memory: {
            providerId: memory.providerId.trim(),
            memoryId: memory.memoryId.trim(),
          },
        }
      : {}),
  };
}

export function readAgentRoles(
  rows: { key: unknown[]; value?: unknown }[],
  userId: string,
): AgentRole[] {
  const roles: AgentRole[] = [];
  for (const row of rows) {
    const role = record(row.value);
    if (
      row.key.length !== 2 ||
      row.key[0] !== 'agentRole' ||
      role.v !== 1 ||
      role.id !== row.key[1] ||
      !text(role.id) ||
      role.id.length > 256 ||
      /\s/.test(role.id) ||
      !text(role.name) ||
      !text(role.ownerUserId) ||
      !text(role.machineId) ||
      !text(role.agentConfigId) ||
      !['private', 'workspace'].includes(String(role.visibility)) ||
      (role.visibility !== 'workspace' && role.ownerUserId !== userId) ||
      !Number.isSafeInteger(role.revision) ||
      (role.revision as number) < 1 ||
      (role.promptPrefix !== undefined &&
        (typeof role.promptPrefix !== 'string' ||
          role.promptPrefix.length > 32000 ||
          role.promptPrefix.includes('\0')))
    )
      continue;
    const runConfig = readRoleRunConfig(role.runConfig);
    if (record(role.runConfig).memory !== undefined && !runConfig.memory)
      continue;
    const rawOptions = record(role.runConfig).configOptionValues;
    const runConfigSupported =
      rawOptions === undefined ||
      (!!rawOptions &&
        typeof rawOptions === 'object' &&
        !Array.isArray(rawOptions) &&
        supportsRunConfigOptions(
          Object.fromEntries(
            Object.entries(rawOptions).filter(
              ([id]) => !sensitiveOptionId.test(id),
            ),
          ),
          64,
        ));
    roles.push({
      id: role.id.trim(),
      name: role.name.trim(),
      ownerUserId: role.ownerUserId,
      visibility: role.visibility as AgentRole['visibility'],
      machineId: role.machineId,
      agentConfigId: role.agentConfigId,
      revision: role.revision as number,
      runConfig,
      runConfigSupported,
      ...(typeof role.description === 'string'
        ? { description: role.description.slice(0, 140) }
        : {}),
      ...(typeof role.promptPrefix === 'string' && role.promptPrefix.trim()
        ? { promptPrefix: role.promptPrefix.trim() }
        : {}),
    });
  }
  return roles.sort(
    (a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id),
  );
}

export async function workspaceAgentRoles(
  workspaceId: string,
  userId: string,
  getGrant: Parameters<typeof openSettings>[1],
  signal?: AbortSignal,
): Promise<AgentRole[]> {
  const deadline = AbortSignal.timeout(30000);
  const { flock } = await openSettings(
    `${workspaceId}:wf:workspace`,
    getGrant,
    signal ? AbortSignal.any([signal, deadline]) : deadline,
  );
  return readAgentRoles(flock.scan(), userId);
}

function supportedRoleRunConfig(config: RoleRunConfig) {
  return supportsRunConfigOptions(config.configOptionValues, 64);
}

export function roleOptions(
  roles: AgentRole[],
  machines: Map<string, Pick<Flock, 'get'>>,
  machineId?: string,
  agentConfigId?: string,
  agents?: CreationOptions['agents'],
): AgentRoleOption[] {
  return roles
    .filter(
      (role) =>
        (machineId === undefined || role.machineId === machineId) &&
        (agentConfigId === undefined || role.agentConfigId === agentConfigId),
    )
    .map((role) => {
      const agent = agents
        ? record(agents.find((agent) => agent.id === role.agentConfigId))
        : record(
            machines
              .get(role.machineId)
              ?.get(['agentConfig', role.agentConfigId]),
          );
      let unavailableReason: AgentRoleOption['unavailableReason'];
      if (agent.id !== role.agentConfigId)
        unavailableReason = 'agent_config_missing';
      else if (agent.machineId !== role.machineId)
        unavailableReason = 'agent_config_machine_mismatch';
      else if (
        role.runConfigSupported === false ||
        !supportedRoleRunConfig(role.runConfig)
      )
        unavailableReason = 'run_config_unsupported';
      return {
        id: role.id,
        name: role.name,
        description: role.description,
        machineId: role.machineId,
        agentConfigId: role.agentConfigId,
        agentName: typeof agent.name === 'string' ? agent.name : '',
        cliType: typeof agent.cliType === 'string' ? agent.cliType : undefined,
        agentType:
          typeof agent.agentType === 'string' ? agent.agentType : undefined,
        revision: role.revision,
        runConfig: role.runConfig,
        available: unavailableReason === undefined,
        unavailableReason,
      };
    });
}

// Shared workspace catalog owner for Role consumers. Authorization is checked
// from the fresh row on every read; the UI never supplies Role instructions.
export async function workspaceRoleMentions(
  workspaceId: string,
  userId: string,
  machines: Map<string, Flock>,
  machineId: string | undefined,
  getGrant: Parameters<typeof openSettings>[1],
  signal?: AbortSignal,
  agentCatalog?: () => CreationOptions['agents'],
): Promise<MentionCatalog> {
  const deadline = AbortSignal.timeout(30000);
  const { flock } = await openSettings(
    `${workspaceId}:wf:workspace`,
    getGrant,
    signal ? AbortSignal.any([signal, deadline]) : deadline,
  );
  return roleMentions(
    flock.scan(),
    userId,
    machines,
    machineId,
    agentCatalog?.(),
  );
}

export function roleMentions(
  rows: { key: unknown[]; value?: unknown }[],
  userId: string,
  machines: Map<string, Pick<Flock, 'get'>>,
  machineId?: string,
  agents?: CreationOptions['agents'],
): MentionCatalog {
  const items: MentionItem[] = [];
  const roles = readAgentRoles(rows, userId);
  for (const option of roleOptions(
    roles,
    machines,
    machineId,
    undefined,
    agents,
  )) {
    if (!option.available) continue;
    const role = roles.find((role) => role.id === option.id)!;
    const summary =
      typeof role.promptPrefix === 'string'
        ? role.promptPrefix.slice(0, 512)
        : '';
    items.push({
      path: role.id,
      name: role.name,
      kind: 'role',
      subtitle: summary || option.agentName,
      insertText: `@role:${role.id}`,
    });
  }
  items.sort(
    (a, b) => a.name.localeCompare(b.name) || a.path.localeCompare(b.path),
  );
  return { items, truncated: false, incomplete: false };
}
