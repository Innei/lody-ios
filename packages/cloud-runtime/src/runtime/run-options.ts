import type { Flock } from '@loro-dev/flock-wasm/base64';
import type {
  RunOptionsCatalog,
  RunOptionsChoice,
  RunOptionsRequest,
} from '../models/run-options';
import type { CreationOptions } from '../models/send';
import {
  readAgentRoles,
  readRoleRunConfig,
  roleOptions,
  type AgentRole,
} from './agent-roles';
import { machineRpc } from './machine-rpc';
import { openSettings, settingsRows } from './settings';

type Grant = Parameters<typeof openSettings>[1];
export type RunOptionsContext = {
  workspaceId: string;
  userId: string;
  machineId: string;
  agentConfigId: string;
  machines: Map<string, Flock>;
  getGrant: Grant;
  assertCurrent?: () => void;
  signal?: AbortSignal;
  agentCatalog?: () => CreationOptions['agents'];
};

export function runOptionsFromRows(
  rows: { key: unknown[]; value?: unknown }[],
  userId: string,
  machines: Map<string, Pick<Flock, 'get'>>,
  machineId?: string,
  agentConfigId?: string,
  agents?: CreationOptions['agents'],
): RunOptionsCatalog {
  const mcpServers: RunOptionsCatalog['mcpServers'] = [];
  for (const row of rows) {
    const value = row.value as Record<string, unknown> | undefined;
    if (
      row.key.length !== 2 ||
      row.key[0] !== 'mcpServer' ||
      !value ||
      typeof value.id !== 'string' ||
      value.id !== row.key[1] ||
      !validId(value.id) ||
      typeof value.name !== 'string' ||
      !value.name.trim() ||
      value.name.length > 200 ||
      !['stdio', 'http'].includes(String(value.transport))
    )
      continue;
    mcpServers.push({
      id: value.id,
      name: value.name,
      transport: value.transport as 'stdio' | 'http',
      enabledByDefault: value.enabledByDefault === true,
    });
  }
  return {
    roles: roleOptions(
      readAgentRoles(rows, userId),
      machines,
      machineId,
      agentConfigId,
      agents,
    ),
    mcpServers: mcpServers.sort((a, b) => a.name.localeCompare(b.name)),
  };
}

export async function remoteWorktreeAvailable(
  workspaceId: string,
  projectId: string | undefined,
  userId: string,
  getGrant: Grant,
  signal?: AbortSignal,
): Promise<boolean> {
  if (!projectId || projectId.startsWith('github:')) return false;
  const separator = projectId.indexOf(':local:');
  if (separator <= 0 || !projectId.slice(separator + 7) || !userId)
    return false;
  try {
    const reply = await machineRpc(
      workspaceId,
      projectId.slice(0, separator),
      'local-project/git-state',
      {
        localProjectId: projectId.slice(separator + 7),
        requestedByUserId: userId,
      },
      getGrant,
      signal
        ? AbortSignal.any([signal, AbortSignal.timeout(35000)])
        : AbortSignal.timeout(35000),
    );
    const result = reply.result as
      | { success?: boolean; state?: { git?: boolean; branches?: unknown[] } }
      | undefined;
    return (
      !reply.error &&
      result?.success === true &&
      result.state?.git === true &&
      Array.isArray(result.state.branches) &&
      result.state.branches.length > 0
    );
  } catch {
    return false;
  }
}

export async function workspaceRunOptions(
  args: RunOptionsRequest,
  machines: Map<string, Flock>,
  getGrant: Grant,
  signal?: AbortSignal,
  agentCatalog?: () => CreationOptions['agents'],
): Promise<RunOptionsCatalog> {
  const [settings, worktreeAvailable] = await Promise.all([
    openSettings(
      `${args.workspaceId}:wf:workspace`,
      getGrant,
      signal
        ? AbortSignal.any([signal, AbortSignal.timeout(30000)])
        : AbortSignal.timeout(30000),
    ),
    remoteWorktreeAvailable(
      args.workspaceId,
      args.projectId,
      args.userId,
      getGrant,
      signal,
    ),
  ]);
  return {
    ...runOptionsFromRows(
      settings.flock.scan(),
      args.userId,
      machines,
      args.machineId,
      args.agentConfigId,
      agentCatalog?.(),
    ),
    worktreeAvailable,
  };
}

const validId = (id: unknown): id is string =>
  typeof id === 'string' &&
  id.length > 0 &&
  id.length <= 256 &&
  !/[\s\x00-\x1f\x7f]/.test(id);

export function validateRunOptionsChoice(choice: RunOptionsChoice) {
  if (
    choice.mcpServerIds !== undefined &&
    (!Array.isArray(choice.mcpServerIds) ||
      choice.mcpServerIds.length > 128 ||
      choice.mcpServerIds.some((id) => !validId(id)) ||
      new Set(choice.mcpServerIds).size !== choice.mcpServerIds.length)
  )
    throw new Error('invalid_mcp_selection');
  if (
    choice.agentRoleId !== undefined &&
    choice.agentRoleId !== null &&
    (!validId(choice.agentRoleId) ||
      !Number.isSafeInteger(choice.agentRoleRevision) ||
      (choice.agentRoleRevision ?? 0) < 1)
  )
    throw new Error('invalid_role_selection');
}

const configFingerprint = (value: unknown) => {
  const config = readRoleRunConfig(value);
  return JSON.stringify([
    config.modelId ?? null,
    config.modeId ?? null,
    Object.entries(config.configOptionValues ?? {}).sort(([a], [b]) =>
      a.localeCompare(b),
    ),
    config.memory ?? null,
  ]);
};

export function validateSelectedRole(
  roles: AgentRole[],
  choice: RunOptionsChoice,
  context: Pick<
    RunOptionsContext,
    'machineId' | 'agentConfigId' | 'machines' | 'agentCatalog'
  >,
): AgentRole {
  validateRunOptionsChoice(choice);
  const role = roles.find((role) => role.id === choice.agentRoleId);
  if (!role) throw new Error('role_unavailable');
  if (role.revision !== choice.agentRoleRevision)
    throw new Error('role_revision_changed');
  if (
    role.machineId !== context.machineId ||
    role.agentConfigId !== context.agentConfigId
  )
    throw new Error('role_binding_changed');
  const option = roleOptions(
    [role],
    context.machines,
    undefined,
    undefined,
    context.agentCatalog?.(),
  )[0];
  if (option?.unavailableReason === 'run_config_unsupported')
    throw new Error('role_unavailable');
  if (!option?.available) throw new Error('role_binding_changed');
  if (
    choice.frozenRole &&
    configFingerprint(choice.frozenRole) !== configFingerprint(role.runConfig)
  )
    throw new Error('role_revision_changed');
  return role;
}

export async function resolveTurnRunOptions(
  choice: RunOptionsChoice,
  previous: Record<string, any>,
  inputConfig: Record<string, any>,
  context: RunOptionsContext,
): Promise<Record<string, any>> {
  validateRunOptionsChoice(choice);
  let next = { ...inputConfig };
  const inheritedRole =
    choice.frozenRole === undefined &&
    choice.agentRoleId !== undefined &&
    choice.agentRoleId === previous.agentRoleId &&
    choice.agentRoleRevision === previous.agentRoleRevision;
  if (choice.mcpServerIds !== undefined)
    next.mcpServerIds = [...choice.mcpServerIds];
  if (choice.agentRoleId === null) {
    next.agentRoleId = null;
    delete next.agentRoleRevision;
    delete next.agentRoleSnapshot;
  }
  if ((!choice.agentRoleId || inheritedRole) && !choice.mcpServerIds?.length)
    return next;
  const { flock } = await openSettings(
    `${context.workspaceId}:wf:workspace`,
    context.getGrant,
    context.signal
      ? AbortSignal.any([context.signal, AbortSignal.timeout(30000)])
      : AbortSignal.timeout(30000),
  );
  context.assertCurrent?.();
  if (choice.mcpServerIds?.length) {
    const catalog = new Set(
      settingsRows('mcp', flock).map((server) => server.id),
    );
    if (choice.mcpServerIds.some((id) => !catalog.has(id)))
      throw new Error('mcp_selection_unavailable');
  }
  if (choice.agentRoleId && !inheritedRole) {
    const role = validateSelectedRole(
      readAgentRoles(flock.scan(), context.userId),
      choice,
      context,
    );
    const config = role.runConfig;
    if (
      (config.modelId && config.modelId !== next.modelId) ||
      (config.modeId && config.modeId !== next.modeId) ||
      Object.entries(config.configOptionValues ?? {}).some(
        ([id, value]) => next.configOptionValues?.[id] !== value,
      )
    )
      throw new Error('role_config_changed');
    next = {
      ...next,
      agentRoleId: role.id,
      agentRoleRevision: role.revision,
      agentRoleSnapshot: {
        id: role.id,
        name: role.name,
        revision: role.revision,
      },
      ...(config.memory ? { memory: config.memory } : {}),
    };
    if (!Object.keys(previous).length && role.promptPrefix)
      next.prompt = `${role.promptPrefix}\n\n${next.prompt}`;
  }
  return next;
}
