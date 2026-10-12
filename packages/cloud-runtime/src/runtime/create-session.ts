import { Flock } from '@loro-dev/flock-wasm/base64';
import type { StreamsClient } from '@loro-dev/streams-client';
import type { Session } from '../models/catalog.ts';
import type {
  Capability,
  CapabilityChoice,
  ConfigOption,
  CreationOptions,
} from '../models/send.ts';
import { githubProject, projectRows } from '../protocol/catalog.ts';
import { isThoughtLevel, validConfigValue } from '../protocol/capability';
import { supportsRunConfigOptions } from '../protocol/run-options';
import { encodeFrame } from '../frames';
import type { RunOptionsChoice } from '../models/run-options';
import { workspaceAgentRoles } from './agent-roles';
import {
  remoteWorktreeAvailable,
  validateRunOptionsChoice,
  validateSelectedRole,
  type RunOptionsContext,
} from './run-options';
import { clientFor } from './session';
import {
  quotaReason,
  workspaceSessionCount,
  type BillingEntitlement,
} from './billing';

export type CreateSessionArgs = RunOptionsChoice & {
  workspaceId: string;
  projectId?: string;
  sessionId: string;
  machineId: string;
  agentConfigId: string;
  userId: string;
  title: string;
  branch?: string;
  useWorktree?: boolean;
  configOptionValues?: Record<string, string | boolean>;
  billingEntitlement?: BillingEntitlement | null;
};

export function creationAgentCatalog(
  meta: Flock,
  machines: Map<string, Flock>,
) {
  type Counts = { accepted: number; rejected: Record<string, number> };
  const diagnostics = {
    legacy: { accepted: 0, rejected: {} } as Counts,
    machines: {} as Record<string, Counts>,
  };
  const agents = new Map<string, CreationOptions['agents'][number]>();
  const add = (
    id: unknown,
    raw: unknown,
    counts: Counts,
    machineId?: string,
  ) => {
    const reject = (reason: string) => {
      counts.rejected[reason] = (counts.rejected[reason] ?? 0) + 1;
    };
    if (!raw || typeof raw !== 'object' || Array.isArray(raw))
      return reject('invalid_shape');
    const value = raw as Record<string, unknown>;
    if (typeof id !== 'string' || !id.trim() || value.id !== id)
      return reject('identity_mismatch');
    if (machineId && value.machineId !== machineId)
      return reject('machine_mismatch');
    if (typeof value.machineId !== 'string' || !machines.has(value.machineId))
      return reject('machine_unavailable');
    if (
      typeof value.name !== 'string' ||
      !value.name.trim() ||
      typeof value.agentType !== 'string' ||
      !value.agentType.trim() ||
      !['builtin', 'registry', 'custom'].includes(String(value.cliType))
    )
      return reject('invalid_config');
    const name =
      meta.get(['m', `machine-${value.machineId}`, 'name']) ??
      (
        meta.get(['m', `machine-${value.machineId}`]) as
          Record<string, unknown> | undefined
      )?.name;
    // Only labels and IDs leave the WebView; diagnostics contain counts, never config values.
    agents.set(id, {
      id,
      name: value.name,
      machineId: value.machineId,
      machineName: typeof name === 'string' && name ? name : '未命名电脑',
      cliType: String(value.cliType),
      agentType: value.agentType,
    });
    counts.accepted++;
  };
  const active = new Set<string>();
  const legacy = new Map<string, Record<string, unknown>>();
  for (const row of meta.scan()) {
    const room = row.key[1];
    if (typeof room !== 'string' || !room.startsWith('agent-')) continue;
    if (row.key[0] === 'e' && row.value === true) active.add(room);
    if (row.key[0] !== 'm') continue;
    const fields =
      legacy.get(room) ?? (Object.create(null) as Record<string, unknown>);
    if (
      row.key.length === 2 &&
      row.value &&
      typeof row.value === 'object' &&
      !Array.isArray(row.value)
    )
      Object.assign(fields, row.value);
    else if (row.key.length === 3 && typeof row.key[2] === 'string') {
      if (row.value === undefined) delete fields[row.key[2]];
      else fields[row.key[2]] = row.value;
    }
    legacy.set(room, fields);
  }
  for (const [room, value] of legacy)
    if (active.has(room)) add(room.slice(6), value, diagnostics.legacy);
  // Match desktop's two storage generations: Machine Flock wins by config ID.
  for (const [machineId, flock] of machines) {
    const counts: Counts = { accepted: 0, rejected: {} };
    diagnostics.machines[machineId] = counts;
    for (const row of flock.scan()) {
      if (row.key[0] !== 'agentConfig' || row.value === undefined) continue;
      if (row.key.length !== 2) {
        counts.rejected.invalid_key = (counts.rejected.invalid_key ?? 0) + 1;
        continue;
      }
      add(row.key[1], row.value, counts, machineId);
    }
  }
  return { agents: [...agents.values()], diagnostics };
}

export function creationOptions(
  projectId: string | undefined,
  meta: Flock,
  machines: Map<string, Flock>,
): CreationOptions {
  const catalog = projectRows(meta.scan(), 'meta');
  const projects = [...catalog.projects];
  for (const [id, flock] of machines)
    projects.push(...projectRows(flock.scan(), id).projects);
  const chat = !projectId;
  let project = projects.findLast((p) => p.id === projectId);
  if (projectId?.startsWith('github:')) {
    // Repository discovery comes from Cloud, not existing session history.
    // Repository access is still checked by the official token broker.
    project = githubProject(projectId.slice(7));
  }
  if (
    !chat &&
    (!project || (!projectId.startsWith('github:') && !project.rootPath))
  )
    throw new Error('project_unavailable');
  if (!chat && project && projectId && !projectId.startsWith('github:')) {
    const localId = projectId.slice(`${project.machineId}:local:`.length);
    if (
      machines
        .get(project.machineId)
        ?.get(['cmd', 'deleteLocalProject', localId]) !== undefined
    )
      throw new Error('project_unavailable');
  }
  const capabilities = new Map<string, Capability & { fetchedAt: number }>();
  const choices = (
    value: unknown,
    idKey: 'id' | 'modelId' | 'value',
  ): CapabilityChoice[] => {
    if (!Array.isArray(value)) return [];
    return value.flatMap((item) => {
      const entry = item as Record<string, unknown>;
      const id = entry?.[idKey],
        name = entry?.name;
      if (typeof id !== 'string' || !id || typeof name !== 'string') return [];
      const choice: CapabilityChoice = { id, name };
      if (typeof entry.description === 'string')
        choice.description = entry.description;
      return [choice];
    });
  };

  const agents = creationAgentCatalog(meta, machines).agents.filter(
    (agent) =>
      chat ||
      projectId.startsWith('github:') ||
      agent.machineId === project!.machineId,
  );
  for (const [machineId, flock] of machines) {
    if (
      !chat &&
      !projectId.startsWith('github:') &&
      machineId !== project!.machineId
    )
      continue;
    for (const row of flock.scan()) {
      const value = row.value as Record<string, unknown> | undefined;
      if (row.key[0] === 'acpCapability' && value) {
        const cliType = String(value.cliType);
        const agentType = String(value.agentType);
        if (!agentType || !cliType) continue;
        const key = `${machineId}:${cliType}:${agentType}`;
        // The same agent can publish more than one capability row; the most
        // recently fetched one describes what the machine will actually accept.
        const fetchedAt = Number(value.fetchedAt) || 0;
        if ((capabilities.get(key)?.fetchedAt ?? -1) >= fetchedAt) continue;
        const efforts = value.modelReasoningEfforts;
        const configOptions: ConfigOption[] = (
          Array.isArray(value.configOptions) ? value.configOptions : []
        ).flatMap((item) => {
          if (!item || typeof item !== 'object') return [];
          const option = item as Record<string, unknown>;
          if (
            typeof option.id !== 'string' ||
            !option.id ||
            /(?:api[_-]?key|auth|bearer|credential|password|passwd|secret|token)/i.test(
              option.id,
            ) ||
            typeof option.name !== 'string' ||
            !['select', 'boolean'].includes(String(option.type))
          )
            return [];
          const projected: ConfigOption = {
            id: option.id,
            name: option.name,
            type: option.type as ConfigOption['type'],
            options: choices(option.options, 'value'),
            ...(typeof option.category === 'string'
              ? { category: option.category }
              : {}),
            ...(typeof option.description === 'string'
              ? { description: option.description }
              : {}),
          };
          if (projected.type === 'select' && !projected.options.length)
            return [];
          if (validConfigValue(projected, option.currentValue))
            projected.currentValue = option.currentValue as string | boolean;
          return [projected];
        });
        const effortOption = configOptions.find(isThoughtLevel);
        const modelOption = configOptions.find(
          (option) => option.category === 'model' && option.type === 'select',
        );
        const modeOption = configOptions.find(
          (option) => option.category === 'mode' && option.type === 'select',
        );
        capabilities.set(key, {
          machineId,
          cliType,
          agentType,
          models: modelOption?.options ?? choices(value.models, 'modelId'),
          modes: modeOption?.options ?? choices(value.modes, 'id'),
          legacyModes: choices(value.modes, 'id'),
          configOptions,
          reasoningEfforts: Object.fromEntries(
            Object.entries(
              (efforts && typeof efforts === 'object' ? efforts : {}) as Record<
                string,
                unknown
              >,
            ).flatMap(([modelId, levels]) =>
              Array.isArray(levels)
                ? [[modelId, levels.filter((l) => typeof l === 'string')]]
                : [],
            ),
          ),
          ...(typeof effortOption?.id === 'string' && effortOption.id
            ? { reasoningEffortConfigId: effortOption.id }
            : {}),
          steer:
            value.acknowledgedSteer === true && value.provenance === 'runtime',
          fetchedAt,
        });
        continue;
      }
    }
  }
  return {
    sessionId: crypto.randomUUID(),
    ...(project ? { project } : {}),
    agents,
    capabilities: [...capabilities.values()].map(
      ({ fetchedAt: _fetchedAt, ...capability }) => capability,
    ),
  };
}

const attempted = new Set<string>();

export async function createSession(
  args: CreateSessionArgs,
  options: CreationOptions,
  replica: { flock: Flock; client: StreamsClient },
  getGrant: () => Promise<{ token: string; gatewayBaseUrl: string }>,
  context?: Pick<
    RunOptionsContext,
    'machines' | 'signal' | 'assertCurrent' | 'agentCatalog'
  >,
) {
  const agent = options.agents.find(
    (a) => a.id === args.agentConfigId && a.machineId === args.machineId,
  );
  const chat = !args.projectId && !options.project;
  const github = options.project?.id.startsWith('github:') === true;
  if (
    !agent ||
    (!chat && args.projectId !== options.project?.id) ||
    typeof args.sessionId !== 'string' ||
    !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(args.sessionId) ||
    typeof args.userId !== 'string' ||
    !args.userId.trim() ||
    typeof args.title !== 'string' ||
    !args.title.trim() ||
    args.title.length > 200 ||
    (args.useWorktree !== undefined && typeof args.useWorktree !== 'boolean') ||
    (args.useWorktree === true && (chat || github)) ||
    (github &&
      (typeof args.branch !== 'string' ||
        !args.branch.trim() ||
        args.branch.length > 255))
  )
    throw new Error('invalid_session');
  validateRunOptionsChoice(args);
  if (!supportsRunConfigOptions(args.configOptionValues))
    throw new Error('invalid_config_options');
  const room = `session-${args.sessionId}`;
  if (
    attempted.has(args.sessionId) ||
    replica.flock.get(['e', room]) !== undefined
  )
    throw new Error('session_already_exists');
  const reason = quotaReason(
    'session',
    args.billingEntitlement,
    workspaceSessionCount(replica.flock.scan()),
  );
  if (reason) return { state: 'rejected', reason } as const;
  if (args.agentRoleId) {
    if (!context) throw new Error('role_unavailable');
    const roles = await workspaceAgentRoles(
      args.workspaceId,
      args.userId,
      getGrant,
      context.signal,
    );
    context.assertCurrent?.();
    const role = validateSelectedRole(roles, args, {
      machineId: args.machineId,
      agentConfigId: args.agentConfigId,
      machines: context.machines,
      agentCatalog: context.agentCatalog ?? (() => options.agents),
    });
    if (
      !supportsRunConfigOptions({
        ...args.configOptionValues,
        ...role.runConfig.configOptionValues,
      })
    )
      throw new Error('role_unavailable');
  }
  if (args.useWorktree === true) {
    const available = await remoteWorktreeAvailable(
      args.workspaceId,
      args.projectId,
      args.userId,
      getGrant,
      context?.signal,
    );
    context?.assertCurrent?.();
    if (!available) throw new Error('worktree_unavailable');
  }
  let project: Record<string, string | boolean> | undefined;
  if (!chat && github) {
    project = {
      kind: 'github',
      repoFullName: options.project!.id.slice(7),
      branch: args.branch!.trim(),
    };
  } else if (!chat) {
    project = {
      kind: 'local',
      localProjectId: options.project!.id.slice(
        `${agent.machineId}:local:`.length,
      ),
      ...(args.useWorktree ? { useWorktree: true } : {}),
    };
  }
  const meta = {
    id: args.sessionId,
    machineId: agent.machineId,
    userId: args.userId,
    title: args.title.trim(),
    titleSource: 'draft',
    status: { type: 'idle' },
    isArchived: false,
    createdAt: new Date().toISOString(),
    cliType: agent.cliType,
    agentType: agent.agentType,
    agentConfigId: agent.id,
    ...(args.agentRoleId
      ? {
          agentRoleId: args.agentRoleId,
          agentRoleRevision: args.agentRoleRevision,
        }
      : {}),
    ...(args.useWorktree ? { isWorktree: true } : {}),
    ...(project ? { project } : {}),
    ...(github
      ? {
          repoFullName: options.project!.id.slice(7),
          baseBranch: args.branch!.trim(),
          isWorktree: true,
        }
      : {}),
  };
  const session: Session = {
    id: meta.id,
    machineId: meta.machineId,
    title: meta.title,
    status: 'idle',
    archived: false,
    pinned: false,
    projectId: args.projectId ?? `${agent.machineId}:unassigned`,
    createdAt: meta.createdAt,
    cliType: meta.cliType,
    agentType: meta.agentType,
  };
  // Create the empty stream before publishing the list entry, so it can be opened immediately.
  const stream = await clientFor(
    `${args.workspaceId}:s:${args.sessionId}`,
    getGrant,
  );
  const created = await stream.create({
    contentType: 'application/octet-stream',
  });
  if (!created.ok) throw new Error(created.result.code);
  context?.assertCurrent?.();
  context?.signal?.throwIfAborted();
  const write = new Flock(`lody-ios-create-${crypto.randomUUID()}`);
  write.set(['e', room], true);
  write.set(['m', room], meta);
  write.commit();
  const update = write.exportJson();
  attempted.add(args.sessionId);
  try {
    context?.assertCurrent?.();
    context?.signal?.throwIfAborted();
    const result = await replica.client.append({
      part: {
        contentType: 'application/octet-stream',
        body: encodeFrame(new TextEncoder().encode(JSON.stringify(update))),
      },
    });
    if (!result.ok) throw new Error(result.result.code);
    context?.assertCurrent?.();
    context?.signal?.throwIfAborted();
    replica.flock.importJson(update);
    return { state: 'created', session };
  } catch {
    // A lost ACK can still mean durable metadata. Keep the ID; never replay creation.
    return { state: 'unknown', session };
  }
}
