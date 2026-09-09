import { Flock } from '@loro-dev/flock-wasm/base64';
import type { StreamsClient } from '@loro-dev/streams-client';
import type { Session } from '../../../src/models/catalog.ts';
import type {
  Capability,
  CapabilityChoice,
  CreationOptions,
} from '../../../src/models/send.ts';
import { projectRows } from '../../../src/cloud/catalog/model.ts';
import { encodeFrame } from '../decoder/frames';
import { clientFor } from './session';

export type CreateSessionArgs = {
  workspaceId: string;
  projectId: string;
  sessionId: string;
  machineId: string;
  agentConfigId: string;
  userId: string;
  title: string;
  branch?: string;
};

export function creationOptions(
  projectId: string,
  meta: Flock,
  machines: Map<string, Flock>,
): CreationOptions {
  const catalog = projectRows(meta.scan(), 'meta');
  const projects = [...catalog.projects];
  for (const [id, flock] of machines)
    projects.push(...projectRows(flock.scan(), id).projects);
  const project = projects.findLast((p) => p.id === projectId);
  if (!project || (!projectId.startsWith('github:') && !project.rootPath))
    throw new Error('project_unavailable');
  if (!projectId.startsWith('github:')) {
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
    idKey: 'id' | 'modelId',
  ): CapabilityChoice[] =>
    Array.isArray(value)
      ? value.flatMap((item) => {
          const entry = item as Record<string, unknown>;
          const id = entry?.[idKey];
          const name = entry?.name;
          return typeof id === 'string' && id && typeof name === 'string'
            ? [
                {
                  id,
                  name,
                  ...(typeof entry.description === 'string'
                    ? { description: entry.description }
                    : {}),
                },
              ]
            : [];
        })
      : [];

  const agents: CreationOptions['agents'] = [];
  for (const [machineId, flock] of machines) {
    if (!projectId.startsWith('github:') && machineId !== project.machineId)
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
        const effortOption = (
          Array.isArray(value.configOptions) ? value.configOptions : []
        ).find((item) => {
          const option = item as Record<string, unknown>;
          return (
            option.id === 'reasoning_effort' ||
            option.category === 'thought_level'
          );
        }) as Record<string, unknown> | undefined;
        capabilities.set(key, {
          machineId,
          cliType,
          agentType,
          models: choices(value.models, 'modelId'),
          modes: choices(value.modes, 'id'),
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
      if (
        row.key[0] !== 'agentConfig' ||
        !value ||
        value.machineId !== machineId
      )
        continue;
      if (
        typeof value.id !== 'string' ||
        value.id !== row.key[1] ||
        typeof value.name !== 'string' ||
        typeof value.agentType !== 'string' ||
        !value.agentType ||
        !['builtin', 'registry', 'custom'].includes(String(value.cliType))
      )
        continue;
      // Project only labels and IDs; never send launch environment or secrets to RN.
      agents.push({
        id: value.id,
        name: value.name,
        machineId,
        machineName: (() => {
          const value =
            meta.get(['m', `machine-${machineId}`, 'name']) ??
            (
              meta.get(['m', `machine-${machineId}`]) as
                Record<string, unknown> | undefined
            )?.name;
          return typeof value === 'string' && value ? value : '未命名电脑';
        })(),
        cliType: String(value.cliType),
        agentType: value.agentType,
      });
    }
  }
  return {
    sessionId: crypto.randomUUID(),
    project,
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
) {
  const agent = options.agents.find(
    (a) => a.id === args.agentConfigId && a.machineId === args.machineId,
  );
  const github = options.project.id.startsWith('github:');
  if (
    !agent ||
    args.projectId !== options.project.id ||
    typeof args.sessionId !== 'string' ||
    !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(args.sessionId) ||
    typeof args.userId !== 'string' ||
    !args.userId.trim() ||
    typeof args.title !== 'string' ||
    !args.title.trim() ||
    args.title.length > 200 ||
    (github &&
      (typeof args.branch !== 'string' ||
        !args.branch.trim() ||
        args.branch.length > 255))
  )
    throw new Error('invalid_session');
  const room = `session-${args.sessionId}`;
  if (
    attempted.has(args.sessionId) ||
    replica.flock.get(['e', room]) !== undefined
  )
    throw new Error('session_already_exists');
  const project: Record<string, string> = github
    ? {
        kind: 'github',
        repoFullName: options.project.id.slice(7),
        branch: args.branch!.trim(),
      }
    : {
        kind: 'local',
        localProjectId: options.project.id.slice(
          `${agent.machineId}:local:`.length,
        ),
      };
  const meta = {
    id: args.sessionId,
    machineId: agent.machineId,
    userId: args.userId,
    title: args.title.trim(),
    titleSource: 'user',
    status: { type: 'idle' },
    isArchived: false,
    createdAt: new Date().toISOString(),
    cliType: agent.cliType,
    agentType: agent.agentType,
    agentConfigId: agent.id,
    project,
    ...(github
      ? {
          repoFullName: options.project.id.slice(7),
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
    projectId: args.projectId,
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
  const write = new Flock(`lody-ios-create-${crypto.randomUUID()}`);
  write.set(['e', room], true);
  write.set(['m', room], meta);
  write.commit();
  const update = write.exportJson();
  attempted.add(args.sessionId);
  try {
    const result = await replica.client.append({
      part: {
        contentType: 'application/octet-stream',
        body: encodeFrame(new TextEncoder().encode(JSON.stringify(update))),
      },
    });
    if (!result.ok) throw new Error(result.result.code);
    replica.flock.importJson(update);
    return { state: 'created', session };
  } catch {
    // A lost ACK can still mean durable metadata. Keep the ID; never replay creation.
    return { state: 'unknown', session };
  }
}
