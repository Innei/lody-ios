import { Flock } from '@loro-dev/flock-wasm/base64';
import { LoroDoc, LoroMap, LoroList } from 'loro-crdt/base64';
import type { StreamsClient } from '@loro-dev/streams-client';
import type { MachinePresence } from '../models/machines.ts';
import type {
  ScheduleContext,
  ScheduleDocument,
  ScheduleDraft,
  ScheduleProposalRef,
  ScheduleRequest,
  ScheduleResult,
  ScheduleRow,
  ScheduleRuntimeRow,
} from '../models/schedules.ts';
import {
  buildScheduleRow,
  canonicalScheduleJson,
  matchingScheduleRuntime,
  object,
  parseScheduleAgent,
  parseScheduleDocument,
  parseScheduleProject,
  parseScheduleProposal,
  readScheduleRegistry,
  scheduleId,
  scheduleOwnSessionId,
  sensitiveScheduleOption,
  validateScheduleDraft,
  validateScheduleRequest,
} from '../protocol/schedules.ts';
import { previewSchedule } from '../protocol/schedule-time.ts';
import { encodeFrame } from '../frames.ts';
import { clientFor, importUpdates, unpack } from './session.ts';
import { creationOptions } from './create-session.ts';
import { openSettings } from './settings.ts';
import { workspaceAgentRoles } from './agent-roles.ts';
import { remoteWorktreeAvailable } from './run-options.ts';

type Grant = () => Promise<{ token: string; gatewayBaseUrl: string }>;
export type ScheduleRuntimeContext = {
  workspaceId: string;
  userId: string;
  meta: Flock;
  machines: Map<string, Flock>;
  presence: MachinePresence;
  getGrant: Grant;
  signal: AbortSignal;
  assertCurrent?: () => void;
};
type Registry = { flock: Flock; client: StreamsClient };
type Mutation = { document?: ScheduleDocument; key?: string[]; value?: object };
function fence(context: ScheduleRuntimeContext) {
  context.signal.throwIfAborted();
  context.assertCurrent?.();
}
function definitionDraft(document: ScheduleDocument): ScheduleDraft {
  const {
    scheduleId: _id,
    ownerId: _owner,
    enabled: _enabled,
    activationId: _activation,
    activeFrom: _from,
    createdAt: _created,
    updatedAt: _updated,
    createdBy: _by,
    ...draft
  } = document.definition;
  return { ...draft, prompt: document.prompt };
}
// The same document-first and idempotency rules as OSS ScheduleRepository.
export function planScheduleMutation(
  request: Exclude<
    ScheduleRequest,
    | { action: 'list' | 'context' }
    | { action: 'worktree' }
    | { action: 'show' }
    | { action: 'proposal' }
  >,
  previous: ScheduleDocument | undefined,
  registry: Pick<Flock, 'get'>,
  userId: string,
  now: number,
): Mutation {
  if (!scheduleId(request.scheduleId) || !userId)
    throw new Error('schedule_invalid');
  const tombstone = object(registry.get(['tombstone', request.scheduleId]));
  if (typeof tombstone.deletedAt === 'number') {
    if (request.action === 'delete' && tombstone.actorId === userId) return {};
    throw new Error('schedule_deleted');
  }
  const row = object(registry.get(['schedule', request.scheduleId]));
  if (request.action !== 'create') {
    if (!previous || row.scheduleId !== request.scheduleId)
      throw new Error('schedule_not_found');
    if (row.ownerId !== userId || previous.definition.ownerId !== userId)
      throw new Error('schedule_owner_only');
  }
  if (request.action === 'delete')
    return {
      key: ['tombstone', request.scheduleId],
      value: { deletedAt: now, actorId: userId },
    };
  if (!scheduleId(request.requestId)) throw new Error('schedule_invalid');
  if (request.action === 'run') {
    const key = ['manual', request.scheduleId, request.requestId];
    const value = {
      scheduleId: request.scheduleId,
      actorId: userId,
      manualRunId: request.requestId,
      activationId: previous!.definition.activationId,
      requestedAt: now,
    };
    const prior = registry.get(key);
    if (prior) {
      if (
        canonicalScheduleJson({ ...object(prior), requestedAt: 0 }) !==
        canonicalScheduleJson({ ...value, requestedAt: 0 })
      )
        throw new Error('schedule_idempotency_conflict');
      return {};
    }
    return { key, value };
  }
  const prior = previous?.timeline.find(
    (entry) => entry.id === request.requestId,
  );
  if (request.action === 'create' || request.action === 'edit') {
    const draft = validateScheduleDraft(request.draft);
    const kind = request.action === 'create' ? 'created' : 'edited';
    if (prior) {
      if (
        prior.kind !== kind ||
        prior.actorId !== userId ||
        previous!.definition.ownerId !== userId ||
        canonicalScheduleJson(definitionDraft(previous!)) !==
          canonicalScheduleJson(draft)
      )
        throw new Error('schedule_idempotency_conflict');
      return { document: previous };
    }
    if (request.action === 'create' && (previous || row.scheduleId))
      throw new Error('schedule_exists');
    const { prompt, ...fields } = draft;
    return {
      document: {
        definition: {
          ...fields,
          scheduleId: request.scheduleId,
          ownerId: userId,
          enabled: previous?.definition.enabled ?? true,
          activationId: request.requestId,
          activeFrom: now,
          createdAt: previous?.definition.createdAt ?? now,
          updatedAt: now,
          createdBy: previous?.definition.createdBy ?? userId,
        },
        prompt,
        timeline: [
          ...(previous?.timeline ?? []),
          { id: request.requestId, kind, actorId: userId, createdAt: now },
        ],
      },
    };
  }
  const enabled = request.action === 'resume',
    kind = enabled ? 'resumed' : 'paused';
  if (prior) {
    if (
      prior.kind !== kind ||
      prior.actorId !== userId ||
      prior.requesterSessionId !== undefined
    )
      throw new Error('schedule_idempotency_conflict');
    return { document: previous };
  }
  return {
    document: {
      ...previous!,
      definition: {
        ...previous!.definition,
        enabled,
        updatedAt: now,
        ...(enabled
          ? { activationId: request.requestId, activeFrom: now }
          : {}),
      },
      timeline: [
        ...previous!.timeline,
        { id: request.requestId, kind, actorId: userId, createdAt: now },
      ],
    },
  };
}

async function registryFor(
  context: ScheduleRuntimeContext,
  create = false,
): Promise<Registry | undefined> {
  const stream = `${context.workspaceId}:sr`;
  try {
    return await openSettings(stream, context.getGrant, context.signal);
  } catch (error) {
    if (!(error instanceof Error) || error.message !== 'not_found') throw error;
    if (!create) return undefined;
    fence(context);
    const client = await clientFor(stream, context.getGrant);
    const created = await client.create({
      contentType: 'application/octet-stream',
    });
    if (!created.ok) {
      if (created.result.code === 'conflict')
        return openSettings(stream, context.getGrant, context.signal);
      throw new Error(created.result.code);
    }
    return {
      client,
      flock: new Flock(`lody-ios-schedules-${crypto.randomUUID()}`),
    };
  }
}
async function openDocument(
  stream: string,
  context: ScheduleRuntimeContext,
  create = false,
): Promise<{ doc: LoroDoc; client: StreamsClient }> {
  const client = await clientFor(stream, context.getGrant),
    doc = new LoroDoc();
  try {
    const initial = await client.bootstrap({ signal: context.signal });
    if (!initial.ok) {
      if (!create || initial.result.code !== 'not_found')
        throw new Error(initial.result.code);
      fence(context);
      const created = await client.create({
        contentType: 'application/octet-stream',
      });
      if (!created.ok) {
        if (created.result.code === 'conflict') {
          doc.free();
          return openDocument(stream, context, false);
        }
        throw new Error(created.result.code);
      }
      return { doc, client };
    }
    let size = 0;
    const consume = (bytes: Uint8Array, snapshot = false) => {
      size += bytes.length;
      if (
        size >
        (stream.startsWith(`${context.workspaceId}:s:`) ? 32 : 8) * 1024 * 1024
      )
        throw new Error('schedule_limit');
      if (snapshot) doc.import(unpack(bytes));
      else importUpdates(doc, bytes);
    };
    const data = initial.result;
    if (data.snapshotOffset !== '-1' && data.snapshot)
      consume(data.snapshot.body, true);
    for (const update of data.updates) consume(update.body);
    let { nextOffset: offset, cursor, upToDate } = data;
    for (let page = 0; !upToDate; page++) {
      fence(context);
      if (page >= 100) throw new Error('schedule_limit');
      const next = await client.readOnce({
        offset,
        cursor,
        signal: context.signal,
      });
      if (!next.ok || next.result.closed)
        throw new Error('schedule_read_failed');
      if (next.result.payload) consume(next.result.payload.body);
      if (!next.result.upToDate && next.result.nextOffset === offset)
        throw new Error('schedule_stalled_cursor');
      ({ nextOffset: offset, cursor, upToDate } = next.result);
    }
    fence(context);
    return { doc, client };
  } catch (error) {
    doc.free();
    throw error;
  }
}
function documentValue(doc: LoroDoc, id: string): ScheduleDocument | undefined {
  const raw = doc.toJSON();
  if (!Object.keys(object(raw.definition)).length) return undefined;
  return parseScheduleDocument(raw, id);
}
export function writeScheduleDocument(
  doc: LoroDoc,
  document: ScheduleDocument,
) {
  const definition = doc.getMap('definition');
  for (const [key, value] of Object.entries(document.definition)) {
    if (value === undefined) definition.delete(key);
    else definition.set(key, value);
  }
  if (!document.definition.project) definition.delete('project');
  const prompt = doc.getText('prompt');
  if (prompt.toString() !== document.prompt) {
    prompt.delete(0, prompt.length);
    prompt.insert(0, document.prompt);
  }
  const timeline = doc.getList('timeline'),
    existing = new Set(
      (timeline.toJSON() as { id?: string }[]).map((entry) => entry.id),
    );
  for (const activity of document.timeline) {
    if (existing.has(activity.id)) continue;
    const entry = timeline.pushContainer(new LoroMap());
    for (const [key, value] of Object.entries(activity))
      if (value !== undefined) entry.set(key, value);
  }
  doc.commit();
}
async function appendLoro(
  handle: Awaited<ReturnType<typeof openDocument>>,
  version: ReturnType<LoroDoc['version']>,
  context: ScheduleRuntimeContext,
) {
  fence(context);
  try {
    const saved = await handle.client.append({
      part: {
        contentType: 'application/octet-stream',
        body: encodeFrame(handle.doc.export({ mode: 'update', from: version })),
      },
    });
    if (!saved.ok) throw new Error(saved.result.code);
  } catch {
    throw new Error('schedule_write_unknown');
  }
  fence(context);
}
async function appendRegistry(
  registry: Registry,
  key: string[],
  value: object,
  context: ScheduleRuntimeContext,
) {
  fence(context);
  if (
    canonicalScheduleJson(registry.flock.get(key)) ===
    canonicalScheduleJson(value)
  )
    return;
  const version = registry.flock.version();
  registry.flock.set(key, value as never);
  registry.flock.commit();
  try {
    const saved = await registry.client.append({
      part: {
        contentType: 'application/octet-stream',
        body: encodeFrame(
          new TextEncoder().encode(
            JSON.stringify(registry.flock.exportJson(version)),
          ),
        ),
      },
    });
    if (!saved.ok) throw new Error(saved.result.code);
  } catch {
    throw new Error('schedule_write_unknown');
  }
  fence(context);
}
function machineField(meta: Flock, id: string, key: string) {
  return (
    meta.get(['m', `machine-${id}`, key]) ??
    object(meta.get(['m', `machine-${id}`]))[key]
  );
}
function sessionContexts(meta: Flock): ScheduleContext['sessions'] {
  const sessions: ScheduleContext['sessions'] = [];
  for (const entry of meta.scan()) {
    if (
      entry.key.length !== 2 ||
      entry.key[0] !== 'e' ||
      typeof entry.key[1] !== 'string' ||
      !entry.key[1].startsWith('session-') ||
      entry.value !== true
    )
      continue;
    const room = entry.key[1],
      raw = object(meta.get(['m', room]));
    const value = (key: string) => meta.get(['m', room, key]) ?? raw[key];
    const id = room.slice(8),
      machineId = value('machineId'),
      agentConfigId = value('agentConfigId'),
      ownerId = value('userId');
    if (
      typeof machineId !== 'string' ||
      typeof agentConfigId !== 'string' ||
      typeof ownerId !== 'string'
    )
      continue;
    let project;
    try {
      if (value('project')) project = parseScheduleProject(value('project'));
    } catch {
      /* Invalid project context cannot be inherited. */
    }
    sessions.push({
      id,
      title: String(value('title') ?? ''),
      machineId,
      agentConfigId,
      ownerId,
      ...(project ? { project } : {}),
    });
  }
  return sessions;
}
export function scheduleContext(
  context: ScheduleRuntimeContext,
): ScheduleContext {
  const options = creationOptions(undefined, context.meta, context.machines);
  const machines: ScheduleContext['machines'] = [];
  for (const entry of context.meta.scan()) {
    if (
      entry.key.length !== 2 ||
      entry.key[0] !== 'e' ||
      typeof entry.key[1] !== 'string' ||
      !entry.key[1].startsWith('machine-') ||
      entry.value !== true
    )
      continue;
    const id = entry.key[1].slice(8),
      capabilities = object(
        machineField(context.meta, id, 'protocolCapabilities'),
      );
    const zone = machineField(context.meta, id, 'timeZone');
    let timeZone =
      typeof zone === 'string'
        ? zone
        : Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
    try {
      new Intl.DateTimeFormat('en', { timeZone }).format(0);
    } catch {
      timeZone = 'UTC';
    }
    let state: ScheduleContext['machines'][number]['state'] = 'unknown';
    if (context.presence.state === 'live')
      state = context.presence.onlineMachineIds.includes(id)
        ? 'online'
        : 'offline';
    machines.push({
      id,
      name: String(machineField(context.meta, id, 'name') ?? id),
      ownerId: String(machineField(context.meta, id, 'ownerUserId') ?? ''),
      timeZone,
      supported:
        typeof capabilities.schedules === 'number' &&
        Number.isInteger(capabilities.schedules) &&
        capabilities.schedules >= 2,
      state,
    });
  }
  const projects: ScheduleContext['projects'] = [];
  for (const [machineId, flock] of context.machines)
    for (const entry of flock.scan()) {
      const row = object(entry.value),
        id = entry.key[1];
      if (
        entry.key.length === 2 &&
        entry.key[0] === 'localProject' &&
        typeof id === 'string' &&
        typeof row.rootPath === 'string' &&
        row.rootPath &&
        flock.get(['cmd', 'deleteLocalProject', id]) === undefined
      )
        projects.push({
          id: `${machineId}:local:${id}`,
          machineId,
          name: String(row.name ?? id),
          project: { kind: 'local', localProjectId: id },
        });
    }
  for (const session of sessionContexts(context.meta))
    if (session.project?.kind === 'github') {
      const project = session.project,
        id = `github:${project.repoFullName}`;
      if (!projects.some((entry) => entry.id === id))
        projects.push({
          id,
          machineId: '',
          name: project.repoFullName,
          project,
        });
    }
  return {
    machines,
    agents: options.agents,
    capabilities: options.capabilities,
    roles: [],
    projects,
    sessions: sessionContexts(context.meta),
  };
}
async function validateTarget(
  draft: ScheduleDraft,
  context: ScheduleRuntimeContext,
  id: string,
) {
  const options = scheduleContext(context),
    machine = options.machines.find((entry) => entry.id === draft.machineId);
  if (!machine) throw new Error('schedule_machine_missing');
  if (machine.ownerId !== context.userId)
    throw new Error('schedule_owned_machine');
  if (!machine.supported) throw new Error('schedule_upgrade');
  const agent = options.agents.find(
    (entry) =>
      entry.id === draft.agent.agentConfigId &&
      entry.machineId === draft.machineId,
  );
  if (!agent) throw new Error('schedule_agent_missing');
  const capability = options.capabilities.find(
    (entry) =>
      entry.machineId === agent.machineId &&
      entry.cliType === agent.cliType &&
      entry.agentType === agent.agentType,
  );
  if (
    draft.agent.modelId &&
    capability?.models.length &&
    !capability.models.some((entry) => entry.id === draft.agent.modelId)
  )
    throw new Error('schedule_config_invalid');
  if (
    draft.agent.modeId &&
    capability?.modes.length &&
    !capability.modes.some((entry) => entry.id === draft.agent.modeId)
  )
    throw new Error('schedule_config_invalid');
  for (const [id, value] of Object.entries(
    draft.agent.configOptionValues ?? {},
  )) {
    const option = capability?.configOptions?.find((entry) => entry.id === id);
    if (
      option &&
      !(option.type === 'boolean'
        ? typeof value === 'boolean'
        : option.options.some((entry) => entry.id === value))
    )
      throw new Error('schedule_config_invalid');
  }
  const project = draft.project;
  if (
    project?.kind === 'local' &&
    !options.projects.some(
      (entry) =>
        entry.machineId === draft.machineId &&
        entry.project.kind === 'local' &&
        entry.project.localProjectId === project.localProjectId,
    )
  )
    throw new Error('schedule_project_machine');
  if (
    project?.kind === 'local' &&
    project.useWorktree &&
    !(await remoteWorktreeAvailable(
      context.workspaceId,
      `${draft.machineId}:local:${project.localProjectId}`,
      context.userId,
      context.getGrant,
      context.signal,
    ))
  )
    throw new Error('schedule_worktree_unavailable');
  if (draft.destination.kind !== 'new_session') {
    if (draft.project) throw new Error('schedule_destination_project');
    const sessionId =
      draft.destination.kind === 'existing_session'
        ? draft.destination.sessionId
        : await scheduleOwnSessionId(id, draft.destination.epoch);
    const session = options.sessions.find((entry) => entry.id === sessionId);
    if (
      (!session && draft.destination.kind === 'existing_session') ||
      (session &&
        (session.ownerId !== context.userId ||
          session.machineId !== draft.machineId ||
          session.agentConfigId !== draft.agent.agentConfigId))
    )
      throw new Error('schedule_destination_mismatch');
  }
  fence(context);
}
async function proposalDocument(
  ref: ScheduleProposalRef,
  context: ScheduleRuntimeContext,
) {
  if (
    !scheduleId(ref.proposalId) ||
    !ref.sessionId ||
    !ref.entryId ||
    !Number.isInteger(ref.itemIndex) ||
    ref.itemIndex < 0
  )
    throw new Error('schedule_invalid');
  const conversation = sessionContexts(context.meta).find(
    (entry) => entry.id === ref.sessionId,
  );
  if (!conversation || conversation.ownerId !== context.userId)
    throw new Error('schedule_owner_only');
  const handle = await openDocument(
    `${context.workspaceId}:s:${ref.sessionId}`,
    context,
  );
  try {
    const history = handle.doc.getList('history'),
      entries = history.toJSON() as Record<string, unknown>[];
    const index = entries.findIndex((entry) => entry.id === ref.entryId);
    if (index < 0) throw new Error('schedule_proposal_missing');
    const entry = history.get(index);
    if (!(entry instanceof LoroMap))
      throw new Error('schedule_proposal_missing');
    const items = entry.get('items');
    if (!(items instanceof LoroList))
      throw new Error('schedule_proposal_missing');
    const item = items.get(ref.itemIndex);
    if (
      !(item instanceof LoroMap) ||
      item.get('type') !== 'system_notice' ||
      item.get('name') !== 'schedule_proposal'
    )
      throw new Error('schedule_proposal_missing');
    const raw = item.get('meta');
    const proposal = parseScheduleProposal(
      raw instanceof LoroMap ? raw.toJSON() : raw,
    );
    if (!proposal || proposal.proposalId !== ref.proposalId)
      throw new Error('schedule_proposal_missing');
    const latest = entries.findLast(
      (entry) => entry.role === 'user' && entry.inputConfig,
    );
    const config = object(latest?.inputConfig);
    const values = Object.fromEntries(
      Object.entries(object(config.configOptionValues)).filter(
        ([id, value]) =>
          !sensitiveScheduleOption(id) &&
          (typeof value === 'string' || typeof value === 'boolean'),
      ),
    );
    const runConfig = parseScheduleAgent({
      agentConfigId: conversation.agentConfigId,
      ...(typeof config.modelId === 'string'
        ? { modelId: config.modelId }
        : {}),
      ...(typeof config.modeId === 'string' ? { modeId: config.modeId } : {}),
      ...(Object.keys(values).length ? { configOptionValues: values } : {}),
    });
    return {
      ...handle,
      item,
      proposal,
      conversation: { ...conversation, runConfig },
    };
  } catch (error) {
    handle.doc.free();
    throw error;
  }
}
export async function scheduleCommand(
  request: ScheduleRequest,
  context: ScheduleRuntimeContext,
): Promise<ScheduleResult> {
  request = validateScheduleRequest(request);
  if (
    !context.userId ||
    !request.workspaceId ||
    request.workspaceId !== context.workspaceId
  )
    throw new Error('schedule_workspace_changed');
  fence(context);
  if (request.action === 'context') {
    const result = scheduleContext(context);
    result.roles = await workspaceAgentRoles(
      context.workspaceId,
      context.userId,
      context.getGrant,
      context.signal,
    );
    fence(context);
    return result;
  }
  if (request.action === 'worktree') {
    const project = scheduleContext(context).projects.find(
      (entry) => entry.id === request.projectId,
    );
    if (
      !project ||
      project.project.kind !== 'local' ||
      machineField(context.meta, project.machineId, 'ownerUserId') !==
        context.userId
    )
      throw new Error('schedule_project_machine');
    const available = await remoteWorktreeAvailable(
      context.workspaceId,
      request.projectId,
      context.userId,
      context.getGrant,
      context.signal,
    );
    fence(context);
    return { available };
  }
  if (request.action === 'proposal') {
    const source = await proposalDocument(request.ref, context);
    try {
      return { proposal: source.proposal, conversation: source.conversation };
    } finally {
      source.doc.free();
    }
  }
  const readOnly = request.action === 'list' || request.action === 'show';
  const registry = await registryFor(context, !readOnly);
  const snapshot = registry
    ? readScheduleRegistry(registry.flock.scan())
    : { rows: [], runtimes: [] };
  if (request.action === 'list') return snapshot;
  if (!scheduleId(request.scheduleId)) throw new Error('schedule_invalid');
  const row = snapshot.rows.find(
    (entry) => entry.scheduleId === request.scheduleId,
  );
  if (
    request.action === 'delete' &&
    registry?.flock.get(['tombstone', request.scheduleId])
  ) {
    planScheduleMutation(
      request,
      undefined,
      registry.flock,
      context.userId,
      Date.now(),
    );
    return { ok: true, scheduleId: request.scheduleId };
  }
  if (!row && request.action !== 'create' && request.action !== 'delete')
    throw new Error('schedule_not_found');
  const handle = await openDocument(
    `${context.workspaceId}:schedule:${request.scheduleId}`,
    context,
    request.action === 'create',
  );
  let proposal: Awaited<ReturnType<typeof proposalDocument>> | undefined;
  try {
    const previous = documentValue(handle.doc, request.scheduleId);
    if (request.action === 'show') {
      if (!previous || !row) throw new Error('schedule_not_found');
      return {
        document: previous,
        runtime: matchingScheduleRuntime(row, snapshot.runtimes),
        next: previewSchedule(
          previous.definition.trigger,
          previous.definition.activeFrom,
          Date.now(),
        ),
      };
    }
    if (request.action === 'create' || request.action === 'edit') {
      const draft = validateScheduleDraft(request.draft);
      // Re-read ownership/capabilities before publishing an execution gate.
      const fresh = await openSettings(
        `${context.workspaceId}:meta`,
        context.getGrant,
        context.signal,
      );
      fence(context);
      const machine = await openSettings(
        `${context.workspaceId}:mf:${draft.machineId}`,
        context.getGrant,
        context.signal,
      );
      const freshContext = {
        ...context,
        meta: fresh.flock,
        machines: new Map(context.machines).set(draft.machineId, machine.flock),
      };
      await validateTarget(draft, freshContext, request.scheduleId);
      if (request.proposal) {
        proposal = await proposalDocument(request.proposal, freshContext);
        if (
          request.scheduleId !== proposal.proposal.proposalId ||
          proposal.proposal.outcome === 'dismissed'
        )
          throw new Error('schedule_proposal_missing');
      }
    }
    if (request.action === 'resume' || request.action === 'run') {
      const machine = scheduleContext(context).machines.find(
        (entry) => entry.id === previous?.definition.machineId,
      );
      if (!machine || machine.ownerId !== context.userId)
        throw new Error('schedule_owned_machine');
      if (!machine.supported) throw new Error('schedule_upgrade');
      if (machine.state !== 'online')
        throw new Error('schedule_machine_offline');
    }
    const mutation = planScheduleMutation(
      request,
      previous,
      registry!.flock,
      context.userId,
      Date.now(),
    );
    if (mutation.document) {
      if (
        canonicalScheduleJson(mutation.document) !==
        canonicalScheduleJson(previous)
      ) {
        const version = handle.doc.version();
        writeScheduleDocument(handle.doc, mutation.document);
        await appendLoro(handle, version, context);
      }
      const freshRegistry = await registryFor(context, true);
      if (freshRegistry!.flock.get(['tombstone', request.scheduleId]))
        throw new Error('schedule_deleted');
      await appendRegistry(
        freshRegistry!,
        ['schedule', request.scheduleId],
        await buildScheduleRow(mutation.document),
        context,
      );
    }
    if (mutation.key && mutation.value)
      await appendRegistry(registry!, mutation.key, mutation.value, context);
    if (proposal && proposal.proposal.outcome !== 'created') {
      const version = proposal.doc.version();
      proposal.item.set('meta', {
        ...proposal.proposal,
        outcome: 'created',
        scheduleId: request.scheduleId,
      });
      proposal.doc.commit();
      await appendLoro(proposal, version, context);
    }
    return { ok: true, scheduleId: request.scheduleId };
  } finally {
    handle.doc.free();
    proposal?.doc.free();
  }
}
