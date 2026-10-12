import {
  mentionCatalog,
  sessionMentions,
  commandMentions,
  skillMentions,
  skillDirs,
} from './mentions';
import { createSharingRuntime } from './sharing/runtime.ts';
import { readShareHistory } from './sharing/history.ts';
import type { ShareRequest } from '../models/session-sharing.ts';
import { expandMentions } from './mention-expansion';
import { workspaceRoleMentions } from './agent-roles';
import type {
  MentionCatalog,
  MentionSource,
  MentionCategory,
} from '../models/mentions';
import { projectHistory } from './project-history';
import type { HistoryRequest } from '../models/project-history.ts';
import {
  projectControl,
  directoryResult,
  registerProject,
} from './local-projects';
import {
  creationAgentCatalog,
  creationOptions,
  createSession,
  type CreateSessionArgs,
} from './create-session';
import {
  archiveSession,
  docFields,
  deleteSession,
  pinSession,
  markSessionRead,
  renameSession,
} from './archive-session';
import { releaseDeletedSessions, sessionDoc, readySessionDoc } from './session';
import {
  createPreview,
  iosSimulatorControl,
  previewTarget,
  revokePreview,
} from './preview';
import { machineRpc } from './machine-rpc';
import { projectManagement } from './project-management.ts';
import type { ProjectManagementRequest } from '../models/project-management.ts';
import {
  providersCommand,
  stopProviderOperations,
  type ProviderOperation,
  type ProviderContext,
} from './providers.ts';
import type { ProviderRequest } from '../models/providers.ts';
import { sessionTools } from './session-tools.ts';
import type { SessionToolsRequest } from '../models/session-tools.ts';
import { createSubagentHistoryRuntime } from './subagent-history.ts';
import type { SubagentHistoryRequest } from '../models/subagent-history.ts';
import { workspaceRunOptions, resolveTurnRunOptions } from './run-options.ts';
import type { RunOptionsRequest } from '../models/run-options.ts';
import { scheduleCommand } from './schedules.ts';
import type { ScheduleRequest } from '../models/schedules.ts';
import { remoteSettings } from './settings';
import type { SettingsRequest } from '../models/settings.ts';
import {
  fileDiff,
  workspaceChanges,
  type FileContext,
  listDir,
  readFile,
  turnDiff,
} from './files';
import { Flock } from '@loro-dev/flock-wasm/base64';
import { StreamsClient } from '@loro-dev/streams-client';
import { decompress } from 'fzstd';
import type { Catalog, Project } from '../models/catalog.ts';
import { projectRows } from '../protocol/catalog.ts';
import { mergeAgentQuotas } from '../protocol/agent-usage.ts';
import {
  openSession,
  closeSession,
  stopSessions,
  ensureSession,
  releaseReserve,
  retainedSessionIds,
  reservedSessionIds,
  itemDetail,
  respondPermission,
  controlTurn,
  sendTurn as sendSessionTurn,
  checkTurnQuota,
  queueMessage,
  checkSend,
  editSession,
} from './session';
import { decodeFrames, encodeFrame } from '../frames';
import {
  watchMachinePresence,
  availableCreationOptions,
} from './machine-presence';
import { unknownPresence, type MachinePresence } from '../models/machines.ts';

type Grant = {
  token: string;
  gatewayBaseUrl: string;
  expiresIn: number;
  shardHostSuffix?: string;
};
const host = (globalThis as any).webkit.messageHandlers.dataRuntime;
const send = (message: object) => host.postMessage(message);
let grantResolve: ((grant: Grant) => void) | undefined;
let grantReject: ((error: Error) => void) | undefined;
let grant: Grant | undefined,
  expiresAt = 0;
let grantPending: Promise<Grant> | undefined;
const githubReplies = new Map<string, (value: MentionCatalog | null) => void>();
const githubPending = new Map<string, Promise<MentionCatalog>>();
function githubMentions(repoFullName: string): Promise<MentionCatalog> {
  const key = `${workspace}:${repoFullName}`;
  const pending = githubPending.get(key);
  if (pending) return pending;
  const id = crypto.randomUUID();
  const request = new Promise<MentionCatalog>((resolve, reject) => {
    const timer = setTimeout(() => {
      githubReplies.delete(id);
      reject(new Error('github_mentions_unavailable'));
    }, 35000);
    githubReplies.set(id, (value) => {
      clearTimeout(timer);
      if (value) resolve(value);
      else reject(new Error('github_mentions_unavailable'));
    });
    send({
      type: 'githubMentions',
      id,
      workspaceId: workspace,
      userId: runtimeUserId,
      repoFullName,
    });
  }).finally(() => githubPending.delete(key));
  githubPending.set(key, request);
  return request;
}
async function getGrant() {
  if (grant && Date.now() < expiresAt) return grant;
  if (!grantPending) {
    const pending = new Promise<Grant>((resolve, reject) => {
      grantResolve = resolve;
      grantReject = reject;
      send({ type: 'grant', workspaceId: workspace, userId: runtimeUserId });
    }).finally(() => {
      if (grantPending === pending) grantPending = undefined;
    });
    grantPending = pending;
  }
  return grantPending;
}
const delay = (ms: number, signal: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    if (signal.aborted) {
      reject(new Error('cancelled'));
      return;
    }
    const abort = () => {
      clearTimeout(timer);
      reject(new Error('cancelled'));
    };
    const timer = setTimeout(() => {
      signal.removeEventListener('abort', abort);
      resolve();
    }, ms);
    signal.addEventListener('abort', abort, { once: true });
  });
let metaReplica: { flock: Flock; client: StreamsClient } | undefined;
let workspace = '';
let presence: MachinePresence = unknownPresence;
let stopPresence: (() => void) | undefined;
function startPresence() {
  stopPresence?.();
  stopPresence = watchMachinePresence(workspace, getGrant, (value) => {
    presence = value;
    send({ type: 'machinePresence', presence: JSON.stringify(value) });
  });
}
const machineReplicas = new Map<string, Flock>();
let creating = false;
let registering = false;
const browsers = new Map<string, AbortController>();
let runtimeLifetime = new AbortController();
const providerOperations = new Map<string, ProviderOperation>();
let providerCleanupContext: ProviderContext | undefined;

async function markDispatch(sessionId: string, turnId: string, queued = false) {
  if (!metaReplica) throw new Error('metadata_not_ready');
  const { flock, client } = metaReplica;
  const version = flock.version();
  if (queued) {
    const key = ['m', `session-${sessionId}`, 'messageQueueUpdatedAt'];
    const previous = flock.get(key);
    flock.set(
      key,
      Math.max(
        Date.now(),
        typeof previous === 'number' && Number.isFinite(previous)
          ? previous + 1
          : 0,
      ),
    );
  } else {
    flock.set(['m', `session-${sessionId}`, 'latestUserMsgId'], turnId);
    flock.set(
      ['m', `session-${sessionId}`, 'lastMissingHistoryUserMsgId'],
      undefined,
    );
  }
  flock.commit();
  const result = await client.append({
    part: {
      contentType: 'application/octet-stream',
      body: encodeFrame(
        new TextEncoder().encode(JSON.stringify(flock.exportJson(version))),
      ),
    },
  });
  if (!result.ok) throw new Error(result.result.code);
}

const watchers = new Map<string, AbortController>();
const catalogs = new Map<string, Catalog>();
const shareReplies = new Map<
  string,
  (value: unknown, failed: boolean) => void
>();
const broker = (operation: string, args: object, signal?: AbortSignal) =>
  new Promise<unknown>((resolve, reject) => {
    if (!workspace || signal?.aborted) {
      reject(new Error('metadata_not_ready'));
      return;
    }
    const workspaceId = workspace,
      userId = runtimeUserId;
    const id = crypto.randomUUID();
    const clear = () => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      shareReplies.delete(id);
    };
    const abort = () => {
      clear();
      reject(new Error('cancelled'));
    };
    const timer = setTimeout(() => {
      clear();
      reject(new Error('share_request_timeout'));
    }, 65000);
    shareReplies.set(id, (value, failed) => {
      clear();
      if (workspace !== workspaceId || runtimeUserId !== userId) {
        reject(new Error('metadata_not_ready'));
        return;
      }
      if (failed) reject(new Error('share_request_failed'));
      else resolve(value);
    });
    signal?.addEventListener('abort', abort, { once: true });
    send({
      type: 'shareRequest',
      workspaceId,
      userId,
      id,
      operation,
      args,
    });
  });
const shareRuntime = createSharingRuntime({
  sessions: () => catalogs.get('meta')?.sessions ?? [],
  history: (id, signal) => readShareHistory(workspace, id, getGrant, signal),
  progress: (progress) => send({ type: 'shareProgress', progress }),
  broker,
});
const sharingEditors = new Map<string, ShareRequest>();
const subagentRuntime = createSubagentHistoryRuntime({
  doc: readySessionDoc,
  emit: send,
});
const unhealthy = new Set<string>();
const gitRepos = new Map<string, string>();
const gitStateAsked = new Set<string>();
let gitStateQueue = Promise.resolve();
let runtimeUserId = '';
function managementContext(
  args: { workspaceId: string; userId: string },
  controller?: AbortController,
  timeoutMs = 65000,
) {
  const replica = metaReplica;
  const signal = AbortSignal.any([
    runtimeLifetime.signal,
    AbortSignal.timeout(timeoutMs),
    ...(controller ? [controller.signal] : []),
  ]);
  const assertCurrent = () => {
    signal.throwIfAborted();
    if (
      !args.userId ||
      args.userId !== runtimeUserId ||
      args.workspaceId !== workspace ||
      !replica ||
      metaReplica !== replica ||
      unhealthy.size
    )
      throw new Error('metadata_not_ready');
  };
  assertCurrent();
  return {
    workspaceId: args.workspaceId,
    userId: args.userId,
    meta: replica!.flock,
    machines: machineReplicas,
    signal,
    assertCurrent,
    agentCatalog: () => {
      assertCurrent();
      return creationAgentCatalog(replica!.flock, machineReplicas).agents;
    },
    getGrant: async () => {
      assertCurrent();
      const value = await getGrant();
      assertCurrent();
      return value;
    },
  };
}
function stopRuntime() {
  const authorization = grant;
  if (providerCleanupContext)
    stopProviderOperations({
      ...providerCleanupContext,
      signal: AbortSignal.timeout(10000),
      assertCurrent: undefined,
      getGrant: async () => {
        if (!authorization) throw new Error('grant_failed');
        return authorization;
      },
    });
  else providerOperations.clear();
  providerCleanupContext = undefined;
  runtimeLifetime.abort();
  subagentRuntime.stop();
  for (const args of sharingEditors.values())
    void shareRuntime({ ...args, action: 'close' }).catch(() => {});
  sharingEditors.clear();
  for (const controller of browsers.values()) controller.abort();
  browsers.clear();
  for (const controller of watchers.values()) controller.abort();
  watchers.clear();
  stopPresence?.();
  stopPresence = undefined;
  presence = unknownPresence;
  stopSessions();
  for (const reply of [...shareReplies.values()]) reply(null, true);
  shareReplies.clear();
  for (const reply of githubReplies.values()) reply(null);
  githubReplies.clear();
  githubPending.clear();
  grantReject?.(new Error('cancelled'));
  grantResolve = undefined;
  grantReject = undefined;
  grantPending = undefined;
  grant = undefined;
  expiresAt = 0;
  metaReplica = undefined;
  machineReplicas.clear();
  catalogs.clear();
  unhealthy.clear();
  gitRepos.clear();
  gitStateAsked.clear();
  gitStateQueue = Promise.resolve();
  lastPublished = '';
  workspace = '';
  runtimeUserId = '';
}
// ponytail: one ask per project per runtime; an offline machine keeps its last repo through the saved catalog until restart.
function askGitState(project: Project) {
  const localProjectId = project.id.split(':local:')[1];
  if (
    project.repoFullName ||
    !localProjectId ||
    !runtimeUserId ||
    gitStateAsked.has(project.id)
  )
    return;
  const source = { workspaceId: workspace, userId: runtimeUserId };
  const lifetime = runtimeLifetime;
  gitStateAsked.add(project.id);
  gitStateQueue = gitStateQueue
    .then(() => {
      if (lifetime.signal.aborted) return;
      const ctx = managementContext(source, undefined, 20000);
      return machineRpc(
        ctx.workspaceId,
        project.machineId,
        'local-project/git-state',
        { localProjectId, requestedByUserId: ctx.userId },
        ctx.getGrant,
        ctx.signal,
      ).then(
        (reply) => {
          try {
            ctx.assertCurrent();
          } catch {
            return;
          }
          const result = reply.result as
            | {
                success?: boolean;
                state?: { git?: boolean; githubRepoFullName?: unknown };
              }
            | undefined;
          const repo =
            result?.success && result.state?.git
              ? String(result.state.githubRepoFullName ?? '').trim()
              : '';
          if (!repo) return;
          gitRepos.set(project.id, repo);
          publish();
        },
        () => {},
      );
    })
    .catch(() => {});
}
let revision = 0;
let lastPublished = '';
function publish() {
  const meta = catalogs.get('meta');
  if (!meta) return;
  const expected = new Set(['meta', ...meta.machineIds]);
  for (const [id, controller] of watchers)
    if (!expected.has(id)) {
      controller.abort();
      watchers.delete(id);
      catalogs.delete(id);
      machineReplicas.delete(id);
      unhealthy.delete(id);
    }
  for (const machine of meta.machineIds)
    if (!watchers.has(machine)) watch(machine);
  if (unhealthy.size || meta.machineIds.some((id) => !catalogs.has(id))) return;
  const projects = new Map(meta.projects.map((p) => [p.id, p]));
  for (const id of meta.machineIds)
    for (const p of catalogs.get(id)!.projects)
      projects.set(p.id, { ...projects.get(p.id), ...p });
  for (const [id, p] of projects) {
    const repo = gitRepos.get(id);
    if (repo && !p.repoFullName) projects.set(id, { ...p, repoFullName: repo });
    else askGitState(p);
  }
  const catalog = JSON.stringify({
    ...meta,
    agentUsage: Object.fromEntries(
      meta.machineIds.map((id) => {
        const usage = catalogs.get(id)?.agentUsage?.[id];
        return [
          id,
          {
            configs: usage?.configs ?? [],
            quotas: mergeAgentQuotas(
              meta.agentUsage?.[id]?.quotas ?? [],
              usage?.quotas ?? [],
            ),
          },
        ];
      }),
    ),
    projects: [...projects.values()].sort((a, b) =>
      a.name.localeCompare(b.name),
    ),
    sessions: [...meta.sessions].sort((a, b) =>
      b.createdAt.localeCompare(a.createdAt),
    ),
  });
  if (catalog !== lastPublished) {
    lastPublished = catalog;
    send({ type: 'catalog', catalog, revision: ++revision });
  }
  send({ type: 'synced', revision, streams: watchers.size });
}
function apply(flock: Flock, bytes: Uint8Array) {
  for (const frame of decodeFrames(bytes))
    flock.importJson(JSON.parse(new TextDecoder().decode(frame)));
}
function watch(mode: string) {
  const controller = new AbortController();
  watchers.set(mode, controller);
  const { signal } = controller;
  void (async () => {
    let failures = 0;
    while (!signal.aborted) {
      try {
        const authorization = await getGrant();
        if (signal.aborted) return;
        const stream =
          mode === 'meta' ? `${workspace}:meta` : `${workspace}:mf:${mode}`;
        const client = new StreamsClient({
          url: `${authorization.gatewayBaseUrl.replace(/\/$/, '')}/ds/lody/${encodeURIComponent(stream)}`,
          auth: async () => (await getGrant()).token,
          retry: { maxAttempts: 1 },
          timeout: { connectTimeoutMs: 15000, pollTimeoutMs: 35000 },
        });
        send({ type: 'diagnostic', stage: 'bootstrap', stream: mode });
        const initial = await client.bootstrap({ signal });
        send({
          type: 'diagnostic',
          stage: initial.ok ? 'bootstrap_ok' : initial.result.code,
          stream: mode,
        });
        if (!initial.ok) {
          if (initial.result.code === 'not_found' && mode !== 'meta') {
            unhealthy.delete(mode);
            catalogs.set(mode, { projects: [], sessions: [], machineIds: [] });
            publish();
            await delay(30000, signal);
            continue;
          }
          throw new Error(initial.result.code);
        }
        const flock = new Flock(`lody-ios-${crypto.randomUUID()}`);
        const data = initial.result;
        let size = 0;
        if (data.snapshotOffset !== '-1' && data.snapshot) {
          const bytes = data.snapshot.body;
          size += bytes.length;
          if (size > 8 * 1024 * 1024) throw new Error('catalog_limit');
          flock.importFile(
            bytes[0] === 0x28 &&
              bytes[1] === 0xb5 &&
              bytes[2] === 0x2f &&
              bytes[3] === 0xfd
              ? decompress(bytes)
              : bytes,
          );
        }
        for (const part of data.updates) {
          size += part.body.length;
          if (size > 8 * 1024 * 1024) throw new Error('catalog_limit');
          apply(flock, part.body);
        }
        let offset = data.nextOffset,
          cursor = data.cursor,
          upToDate = data.upToDate;
        let pages = 0;
        while (!signal.aborted) {
          if (upToDate) {
            if (mode === 'meta') {
              if (metaReplica?.flock !== flock) metaReplica = { flock, client };
            } else machineReplicas.set(mode, flock);
            unhealthy.delete(mode);
            catalogs.set(mode, projectRows(flock.scan(), mode));
            publish();
            failures = 0;
            pages = 0;
          }
          const response = await client.readOnce({
            offset,
            cursor,
            signal,
            ...(upToDate ? { live: 'long-poll' as const } : {}),
          });
          if (!response.ok) throw new Error(response.result.code);
          const next = response.result;
          if (signal.aborted) return;
          if (next.payload) {
            size += next.payload.body.length;
            if (size > 8 * 1024 * 1024) throw new Error('catalog_limit');
            apply(flock, next.payload.body);
          }
          if (next.nextOffset === offset && !next.upToDate)
            throw new Error('stalled_cursor');
          if (++pages > 100 && !next.upToDate) throw new Error('catalog_limit');
          offset = next.nextOffset;
          cursor = next.cursor;
          upToDate = next.upToDate;
          if (next.closed) throw new Error('stream_closed');
          // Empty responses may arrive immediately; avoid a hot polling loop.
          if (!next.payload?.body.length && upToDate) await delay(1000, signal);
        }
      } catch (error) {
        if (signal.aborted) return;
        if (mode === 'meta') metaReplica = undefined;
        else machineReplicas.delete(mode);
        unhealthy.add(mode);
        const reason = error instanceof Error ? error.message : 'sync_failed';
        send({
          type: 'syncError',
          reason: ['catalog_limit', 'stream_closed', 'stalled_cursor'].includes(
            reason,
          )
            ? reason
            : 'network_or_auth',
          stream: mode,
        });
        grant = undefined;
        if (reason === 'catalog_limit') return;
        try {
          await delay(
            Math.min(30000, 2000 * 2 ** Math.min(failures++, 4)),
            signal,
          );
        } catch {
          return;
        }
      }
    }
  })();
}
function machineFor(
  sessionId: string,
  path: string,
): FileContext & { localProjectId?: string } {
  if (!metaReplica || unhealthy.size) throw new Error('metadata_not_ready');
  if (typeof path !== 'string' || path.length > 32768 || path.includes('\0'))
    throw new Error('invalid_path');
  const session = catalogs
    .get('meta')
    ?.sessions.find((item) => item.id === sessionId);
  if (!session || !machineReplicas.has(session.machineId))
    throw new Error('machine_unavailable');
  const localPrefix = `${session.machineId}:local:`;
  return {
    workspaceId: workspace,
    machineId: session.machineId,
    // Code Collab ownership lives in workspace Meta Flock, not the session doc.
    ownerSessionId: session.parentSessionId ?? session.id,
    localProjectId: session.projectId.startsWith(localPrefix)
      ? session.projectId.slice(localPrefix.length)
      : undefined,
    getGrant,
    signal: AbortSignal.timeout(35000),
  };
}
function previewControl(sessionId: string, userId: string) {
  const { workspaceId, machineId, getGrant } = machineFor(sessionId, '/');
  return {
    workspaceId,
    machineId,
    sessionId,
    userId,
    rpc: (method: string, params: object, timeoutMs: number) =>
      machineRpc(
        workspaceId,
        machineId,
        method,
        params,
        getGrant,
        AbortSignal.timeout(timeoutMs),
      ),
    mintToken: (intent: object) =>
      broker('previewToken', { intent }).catch(() => undefined),
  };
}
async function getMentions(
  args: MentionSource & { category: MentionCategory; userId: string },
): Promise<MentionCatalog> {
  const ctx = managementContext(args, undefined, 35000);
  if (args.category === 'session')
    return sessionMentions(
      catalogs.get('meta')?.sessions ?? [],
      [...catalogs.values()].flatMap((value) => value.projects),
      args.sessionId,
    );
  const session = args.sessionId
    ? catalogs.get('meta')?.sessions.find((item) => item.id === args.sessionId)
    : undefined;
  if (args.sessionId && !session) throw new Error('session_unavailable');
  const projectId = session?.projectId ?? args.projectId;
  const project = [...catalogs.values()]
    .flatMap((value) => value.projects)
    .find((item) => item.id === projectId);
  if (args.projectId && !project && !projectId?.startsWith('github:'))
    throw new Error('project_unavailable');
  if (args.category === 'skill' && projectId?.startsWith('github:')) {
    const result = await broker(
      'projectApi',
      {
        method: 'github-skills',
        args: { repoFullName: projectId.slice(7), skillDirs },
      },
      ctx.signal,
    );
    ctx.assertCurrent();
    if (!result || typeof result !== 'object' || Array.isArray(result))
      throw new Error('invalid_skill_list');
    return skillMentions([result as Record<string, unknown>]);
  }
  const machineId =
    session?.machineId ??
    (projectId?.startsWith('github:') ? args.machineId : project?.machineId) ??
    args.machineId;
  if (machineId && !machineReplicas.has(machineId))
    throw new Error('machine_unavailable');
  const prefix = `${machineId}:local:`;
  const localProjectId = projectId?.startsWith(prefix)
    ? projectId.slice(prefix.length)
    : undefined;
  if (
    machineId &&
    localProjectId &&
    machineReplicas
      .get(machineId)
      ?.get(['cmd', 'deleteLocalProject', localProjectId]) !== undefined
  )
    throw new Error('project_unavailable');
  if (args.category === 'issue' || args.category === 'pr') {
    if (!projectId?.startsWith('github:'))
      return { items: [], truncated: false, incomplete: false };
    const result = await githubMentions(projectId.slice(7));
    ctx.assertCurrent();
    return {
      ...result,
      items: result.items.filter((item) => item.kind === args.category),
    };
  }
  if (!machineId) throw new Error('machine_unavailable');
  if (args.category === 'cmd') {
    const metadata = session
      ? (ctx.meta.get(['m', `session-${session.id}`]) as
          Record<string, unknown> | undefined)
      : undefined;
    const configId = session
      ? (ctx.meta.get(['m', `session-${session.id}`, 'agentConfigId']) ??
        metadata?.agentConfigId)
      : args.agentConfigId;
    if (typeof configId !== 'string') return commandMentions([]);
    const capability = machineReplicas
      .get(machineId)
      ?.get(['acpCapability', configId]) as Record<string, unknown> | undefined;
    if (
      !capability ||
      capability.cliType !== (args.cliType ?? session?.cliType) ||
      capability.agentType !== (args.agentType ?? session?.agentType)
    )
      return commandMentions([]);
    return commandMentions(capability.availableCommands);
  }
  if (args.category === 'role') {
    const pinned =
      projectId?.startsWith(`${machineId}:local:`) ||
      (session && projectId?.startsWith('github:'));
    return workspaceRoleMentions(
      workspace,
      args.userId,
      machineReplicas,
      pinned ? machineId : undefined,
      ctx.getGrant,
      ctx.signal,
      ctx.agentCatalog,
    );
  }
  return mentionCatalog(
    {
      workspaceId: workspace,
      machineId,
      localProjectId,
      repoFullName: projectId?.startsWith('github:')
        ? projectId.slice('github:'.length)
        : undefined,
      sessionId: session?.id,
      getGrant: ctx.getGrant,
      signal: ctx.signal,
    },
    args.category,
    args.userId,
  );
}
Object.assign(globalThis, {
  dataRuntime: {
    sessionSharing(args: ShareRequest) {
      if (args.workspaceId !== workspace)
        throw new Error('share_workspace_changed');
      if (args.action === 'close') sharingEditors.delete(args.editorId);
      else sharingEditors.set(args.editorId, args);
      return shareRuntime(args);
    },
    async scheduleCommand(args: ScheduleRequest & { userId: string }) {
      const ctx = managementContext(args, undefined, 120000);
      const { userId: _userId, ...request } = args;
      const result = await scheduleCommand(request, { ...ctx, presence });
      ctx.assertCurrent();
      return result;
    },
    async projectCommand(args: {
      workspaceId: string;
      userId: string;
      editorId: string;
      request: ProjectManagementRequest;
    }) {
      if (
        typeof args.editorId !== 'string' ||
        !args.editorId ||
        args.editorId.length > 256 ||
        args.editorId.includes('\0')
      )
        throw new Error('invalid_project_request');
      const key = `project:${args.editorId}`;
      if (args.request.kind === 'cancel') {
        if (args.workspaceId !== workspace || args.userId !== runtimeUserId)
          throw new Error('metadata_not_ready');
        browsers.get(key)?.abort();
        browsers.delete(key);
        return { projects: [] };
      }
      let controller = browsers.get(key);
      if (!controller) {
        controller = new AbortController();
        browsers.set(key, controller);
      }
      const ctx = managementContext(args, controller, 120000);
      const result = await projectManagement(args.request, {
        ...ctx,
        projects: [...catalogs.values()].flatMap((value) => value.projects),
        sessions: catalogs.get('meta')?.sessions ?? [],
        onlineMachineIds:
          presence.state === 'live' ? presence.onlineMachineIds : undefined,
        cloud: async (method, value) => {
          ctx.assertCurrent();
          const result = await broker(
            'projectApi',
            { method, args: value },
            ctx.signal,
          );
          ctx.assertCurrent();
          return result;
        },
        skills: (projectId) =>
          getMentions({
            workspaceId: ctx.workspaceId,
            userId: ctx.userId,
            projectId,
            category: 'skill',
          }),
      });
      ctx.assertCurrent();
      for (const [id, flock] of machineReplicas)
        catalogs.set(id, projectRows(flock.scan(), id));
      publish();
      return result;
    },
    async providerCommand(args: ProviderRequest & { userId: string }) {
      const ctx = managementContext(args);
      const context = {
        ...ctx,
        presence,
        operations: providerOperations,
      };
      providerCleanupContext = context;
      const result = await providersCommand(args, context);
      ctx.assertCurrent();
      return result;
    },
    async sessionTools(args: SessionToolsRequest & { userId: string }) {
      const ctx = managementContext(args);
      const result = await sessionTools(args, {
        ...ctx,
        meta: metaReplica!,
        sessionDoc,
      });
      ctx.assertCurrent();
      if (result.action === 'pin' || result.action === 'unread') {
        catalogs.set('meta', projectRows(ctx.meta.scan(), 'meta'));
        publish();
      }
      return result;
    },
    async runOptions(args: RunOptionsRequest & { sessionId?: string }) {
      const ctx = managementContext(args);
      const session = args.sessionId
        ? catalogs
            .get('meta')
            ?.sessions.find((item) => item.id === args.sessionId)
        : undefined;
      if (args.sessionId && !session) throw new Error('session_unavailable');
      let machineId = args.machineId,
        agentConfigId = args.agentConfigId;
      if (session) {
        machineId = session.machineId;
        const fields = docFields(ctx.meta, `session-${session.id}`);
        const configId =
          ctx.meta.get(['m', `session-${session.id}`, 'agentConfigId']) ??
          fields?.agentConfigId;
        if (typeof configId !== 'string')
          throw new Error('session_unavailable');
        agentConfigId = configId;
      }
      if (machineId && !machineReplicas.has(machineId))
        throw new Error('machine_unavailable');
      const projectId = session?.projectId ?? args.projectId;
      const creationProjectId =
        session?.projectId === `${session?.machineId}:unassigned`
          ? undefined
          : projectId;
      const options = creationOptions(
        creationProjectId,
        ctx.meta,
        machineReplicas,
      );
      if (agentConfigId) {
        const selected = options.agents.find(
          (agent) =>
            agent.id === agentConfigId &&
            (!machineId || agent.machineId === machineId),
        );
        if (!selected) throw new Error('agent_unavailable');
        machineId = selected.machineId;
      }
      const result = await workspaceRunOptions(
        {
          ...args,
          machineId,
          agentConfigId,
          projectId: session?.projectId ?? args.projectId,
        },
        machineReplicas,
        ctx.getGrant,
        ctx.signal,
        ctx.agentCatalog,
      );
      ctx.assertCurrent();
      return result;
    },
    subagentHistory(
      args: SubagentHistoryRequest & { workspaceId: string; userId: string },
    ) {
      if (args.action === 'unwatch') {
        if (
          args.workspaceId !== workspace ||
          !args.userId ||
          args.userId !== runtimeUserId
        )
          throw new Error('metadata_not_ready');
        return subagentRuntime.execute(args);
      }
      const ctx = managementContext(args);
      if (
        !catalogs
          .get('meta')
          ?.sessions.some((item) => item.id === args.identity.sessionId)
      )
        throw new Error('session_unavailable');
      ctx.assertCurrent();
      return subagentRuntime.execute(args);
    },
    async sessionPreview(args: {
      sessionId: string;
      userId: string;
      action?: 'create' | 'revoke';
    }) {
      const doc = sessionDoc(args.sessionId);
      const target = doc && previewTarget(doc);
      if (!target) return { error: 'unavailable' };
      const control = previewControl(args.sessionId, args.userId);
      return args.action === 'revoke'
        ? revokePreview(control)
        : createPreview({ ...control, target });
    },
    async iosSimulatorControl(args: {
      workspaceId: string;
      sessionId: string;
      userId: string;
      command: { action: string };
    }) {
      if (args.workspaceId !== workspace) throw new Error('metadata_not_ready');
      const control = previewControl(args.sessionId, args.userId);
      const room = `machine-${control.machineId}`;
      const capabilities = (metaReplica!.flock.get([
        'm',
        room,
        'protocolCapabilities',
      ]) ??
        (metaReplica!.flock.get(['m', room]) as Record<string, unknown>)
          ?.protocolCapabilities) as Record<string, number> | undefined;
      // Older CLIs drop unknown methods without replying.
      if (!((capabilities?.iosSimulator ?? 0) >= 1))
        return { error: 'unsupported', capabilities };
      return iosSimulatorControl({ ...control, command: args.command });
    },
    shareResult(id: string, value: unknown, failed: boolean) {
      const reply = shareReplies.get(id);
      shareReplies.delete(id);
      reply?.(value, failed);
    },
    ping: () => true,
    githubMentionsResult(id: string, value: MentionCatalog | null) {
      const reply = githubReplies.get(id);
      githubReplies.delete(id);
      reply?.(value);
    },
    async remoteSettings(args: SettingsRequest & { userId: string }) {
      if (args.workspaceId !== workspace || !metaReplica || unhealthy.size)
        throw new Error('metadata_not_ready');
      return remoteSettings(
        args,
        args.userId,
        getGrant,
        AbortSignal.timeout(35000),
      );
    },
    /**
     * Development probe: reports the shape of the machine replicas so the client
     * can find out whether model choices exist in the data at all. Names only —
     * values may carry launch environment and secrets and must never leave the
     * WebView.
     */
    probeSchema() {
      // Development probe. `acpCapability` is a published capability catalog —
      // model and mode names are exactly what the picker must show, so its
      // values are safe to report. `agentConfig.env` carries launch secrets and
      // never leaves the WebView; only its field names are reported.
      const names = (value: unknown): string[] =>
        value && typeof value === 'object' && !Array.isArray(value)
          ? Object.keys(value as Record<string, unknown>).sort()
          : [];
      const report: Record<string, unknown> = {};
      if (metaReplica)
        report.agentCatalog = creationAgentCatalog(
          metaReplica.flock,
          machineReplicas,
        ).diagnostics;
      // Run the real projection here so its exception text survives; a JS throw
      // reaches Swift as a generic WKError with no message.
      const trials: Record<string, string> = {};
      for (const catalog of catalogs.values())
        for (const project of catalog.projects) {
          if (trials[project.id]) continue;
          try {
            const value = creationOptions(
              project.id,
              metaReplica!.flock,
              machineReplicas,
            );
            trials[project.id] =
              `ok agents=${value.agents.length} capabilities=${value.capabilities.length}`;
          } catch (error) {
            trials[project.id] = `THREW ${String(
              error,
            )} | ${(error as Error)?.stack ?? ''}`.slice(0, 400);
          }
        }
      report.creationOptionsTrial = trials;
      for (const [machineId, flock] of machineReplicas) {
        const capabilities: unknown[] = [];
        const otherKeys = new Set<string>();
        for (const row of flock.scan()) {
          const kind = String(row.key[0]);
          if (kind !== 'acpCapability') {
            otherKeys.add(kind);
            continue;
          }
          const value = (row.value ?? {}) as Record<string, unknown>;
          capabilities.push({
            key: row.key.map(String),
            cliType: value.cliType,
            agentType: value.agentType,
            models: value.models,
            modes: value.modes,
            modelReasoningEfforts: value.modelReasoningEfforts,
            configOptionFields: names(value.configOptions),
          });
        }
        report[machineId] = { otherKeys: [...otherKeys].sort(), capabilities };
      }
      return report;
    },
    async localProjects(args: {
      workspaceId: string;
      browserId: string;
      action: string;
      userId: string;
      history?: HistoryRequest;
      machineId?: string;
      path?: string;
      cursor?: string;
    }) {
      if (args.workspaceId !== workspace || !args.browserId)
        throw new Error('metadata_not_ready');
      if (args.action === 'cancel') {
        browsers.get(args.browserId)?.abort();
        browsers.delete(args.browserId);
        return {};
      }
      if (!metaReplica || unhealthy.size) throw new Error('metadata_not_ready');
      if (args.action === 'history' && args.history) {
        let controller = browsers.get(args.browserId);
        if (!controller) {
          controller = new AbortController();
          browsers.set(args.browserId, controller);
        }
        return projectHistory(
          args.history,
          workspace,
          args.userId,
          metaReplica.flock,
          machineReplicas,
          getGrant,
          AbortSignal.any([controller.signal, AbortSignal.timeout(120000)]),
        );
      }
      if (args.action === 'machines') {
        return {
          machines: (catalogs.get('meta')?.machineIds ?? []).map((id) => {
            const meta = metaReplica!.flock;
            const value = meta.get(['m', `machine-${id}`]) as
              Record<string, unknown> | undefined;
            const name =
              meta.get(['m', `machine-${id}`, 'name']) ?? value?.name;
            return {
              id,
              name: typeof name === 'string' && name ? name : '未命名电脑',
            };
          }),
        };
      }
      const machineId = args.machineId;
      if (
        !machineId ||
        !machineReplicas.has(machineId) ||
        !['browse', 'add'].includes(args.action)
      )
        throw new Error('machine_unavailable');
      if (
        args.path !== undefined &&
        (typeof args.path !== 'string' ||
          args.path.length > 32768 ||
          args.path.includes('\0'))
      )
        throw new Error('invalid_path');
      let controller = browsers.get(args.browserId);
      if (!controller) {
        controller = new AbortController();
        browsers.set(args.browserId, controller);
      }
      const signal = AbortSignal.any([
        controller.signal,
        AbortSignal.timeout(35000),
      ]);
      const flock = machineReplicas.get(machineId)!;
      if (args.action === 'browse')
        return directoryResult(
          await projectControl(
            workspace,
            machineId,
            {
              type: 'local-project/browse-dir',
              absolutePath: args.path,
              cursor: args.cursor,
              limit: 100,
            },
            getGrant,
            signal,
          ),
        );
      if (registering || !args.path) throw new Error('project_not_ready');
      registering = true;
      try {
        const prepared = await projectControl(
          workspace,
          machineId,
          { type: 'local-project/prepare-add', rootPath: args.path },
          getGrant,
          signal,
        );
        signal.throwIfAborted();
        if (machineReplicas.get(machineId) !== flock)
          throw new Error('metadata_not_ready');
        const result = await registerProject(
          workspace,
          machineId,
          prepared,
          flock,
          getGrant,
          signal,
        );
        if (machineReplicas.get(machineId) === flock) {
          catalogs.set(machineId, projectRows(flock.scan(), machineId));
          publish();
        }
        return result;
      } finally {
        registering = false;
      }
    },
    turnDiff(args: { sessionId: string; entryId: string; path: string }) {
      return turnDiff(machineFor(args.sessionId, args.path), args);
    },
    workspaceChanges(args: { sessionId: string }) {
      return workspaceChanges(machineFor(args.sessionId, '/'), args);
    },
    fileDiff(args: { sessionId: string; path: string }) {
      return fileDiff(machineFor(args.sessionId, args.path), args);
    },
    readFile(args: { sessionId: string; path: string }) {
      return readFile(machineFor(args.sessionId, args.path), args);
    },
    mentionCatalog: getMentions,
    listDir(args: {
      workspaceId: string;
      sessionId: string;
      relativePath: string;
      userId: string;
    }) {
      if (args.workspaceId !== workspace) throw new Error('metadata_not_ready');
      const ctx = machineFor(args.sessionId, args.relativePath);
      if (!ctx.localProjectId) throw new Error('project_unavailable');
      return listDir(ctx, {
        localProjectId: ctx.localProjectId,
        relativePath: args.relativePath,
        userId: args.userId,
      });
    },
    creationOptions(args: { workspaceId: string; projectId?: string }) {
      if (args.workspaceId !== workspace || !metaReplica || unhealthy.size)
        throw new Error('metadata_not_ready');
      const options = creationOptions(
        args.projectId,
        metaReplica.flock,
        machineReplicas,
      );
      return availableCreationOptions(options, presence);
    },
    async createSession(args: CreateSessionArgs) {
      if (
        creating ||
        args.workspaceId !== workspace ||
        !args.userId ||
        args.userId !== runtimeUserId ||
        !metaReplica ||
        unhealthy.size
      )
        return { state: 'rejected', reason: 'metadata_not_ready' };
      const replica = metaReplica;
      creating = true;
      try {
        const ctx = managementContext(args, undefined, 120000);
        const options = creationOptions(
          args.projectId,
          replica.flock,
          machineReplicas,
        );
        const result = await createSession(
          args,
          options,
          replica,
          ctx.getGrant,
          {
            machines: ctx.machines,
            signal: ctx.signal,
            assertCurrent: ctx.assertCurrent,
            agentCatalog: ctx.agentCatalog,
          },
        );
        if (result.state === 'created' && metaReplica === replica) {
          catalogs.set('meta', projectRows(replica.flock.scan(), 'meta'));
          publish();
        }
        return result;
      } catch (error) {
        const message = error instanceof Error ? error.message : '';
        return {
          state: message === 'session_already_exists' ? 'unknown' : 'rejected',
          reason: /^[a-z][a-z0-9_]*$/.test(message)
            ? message
            : 'session_creation_failed',
        };
      } finally {
        creating = false;
      }
    },
    async deleteSession(args: {
      workspaceId: string;
      sessionId: string;
      sessionIds: string[];
    }) {
      if (args.workspaceId !== workspace || !metaReplica || unhealthy.size)
        throw new Error('metadata_not_ready');
      const replica = metaReplica;
      const sessionIds = await deleteSession(args, replica);
      if (metaReplica === replica) {
        releaseDeletedSessions(sessionIds);
        catalogs.set('meta', projectRows(replica.flock.scan(), 'meta'));
        publish();
      }
      return { sessionIds };
    },
    async archiveSession(args: {
      workspaceId: string;
      sessionId: string;
      archived: boolean;
    }) {
      if (args.workspaceId !== workspace || !metaReplica)
        throw new Error('metadata_not_ready');
      const replica = metaReplica;
      await archiveSession(args, replica, machineReplicas, getGrant);
      if (metaReplica === replica) {
        catalogs.set('meta', projectRows(replica.flock.scan(), 'meta'));
        publish();
      }
      return {};
    },
    async pinSession(args: {
      workspaceId: string;
      sessionId: string;
      pinned: boolean;
    }) {
      if (args.workspaceId !== workspace || !metaReplica)
        throw new Error('metadata_not_ready');
      const replica = metaReplica;
      await pinSession(args, replica);
      if (metaReplica === replica) {
        catalogs.set('meta', projectRows(replica.flock.scan(), 'meta'));
        publish();
      }
      return {};
    },
    async markSessionRead(args: {
      workspaceId: string;
      sessionId: string;
      lastReadAt: number;
    }) {
      if (args.workspaceId !== workspace || !metaReplica)
        throw new Error('metadata_not_ready');
      const replica = metaReplica;
      await markSessionRead(args, replica);
      if (metaReplica === replica) {
        catalogs.set('meta', projectRows(replica.flock.scan(), 'meta'));
        publish();
      }
      return {};
    },
    async renameSession(args: {
      workspaceId: string;
      sessionId: string;
      title: string;
    }) {
      if (args.workspaceId !== workspace || !metaReplica)
        throw new Error('metadata_not_ready');
      const replica = metaReplica;
      await renameSession(args, replica);
      if (metaReplica === replica) {
        catalogs.set('meta', projectRows(replica.flock.scan(), 'meta'));
        publish();
      }
      return {};
    },
    session(id: string) {
      const result = openSession(id, workspace, getGrant, send, markDispatch);
      send({
        type: 'sessionSubscriptions',
        ids: retainedSessionIds(),
        reserved: reservedSessionIds(),
      });
      return result;
    },
    closeSession() {
      closeSession();
      send({
        type: 'sessionSubscriptions',
        ids: retainedSessionIds(),
        reserved: reservedSessionIds(),
      });
    },
    async ensureSession(args: { sessionId: string }) {
      const result = ensureSession(
        args.sessionId,
        workspace,
        getGrant,
        send,
        markDispatch,
      );
      send({
        type: 'sessionSubscriptions',
        ids: retainedSessionIds(),
        reserved: reservedSessionIds(),
      });
      return result;
    },
    releaseReserve(args: { sessionId: string }) {
      releaseReserve(args.sessionId);
      send({
        type: 'sessionSubscriptions',
        ids: retainedSessionIds(),
        reserved: reservedSessionIds(),
      });
      return {};
    },
    restoreSessions(
      ids: string[],
      current: string | null,
      reserved: string[] = [],
    ) {
      for (const id of ids) {
        if (id === current || reserved.includes(id)) continue;
        void openSession(id, workspace, getGrant, send, markDispatch, false);
      }
      for (const id of reserved)
        void ensureSession(id, workspace, getGrant, send, markDispatch).catch(
          () => {},
        );
      if (current)
        void openSession(current, workspace, getGrant, send, markDispatch);
      else closeSession();
      send({
        type: 'sessionSubscriptions',
        ids: retainedSessionIds(),
        reserved: reservedSessionIds(),
      });
    },
    itemDetail,
    respondPermission,
    controlTurn,
    checkTurnQuota,
    async queueMessage(
      args: Parameters<typeof queueMessage>[0] & {
        workspaceId: string;
        userId: string;
      },
    ) {
      const ctx = managementContext(args);
      if (
        !catalogs
          .get('meta')
          ?.sessions.some((item) => item.id === args.sessionId)
      )
        return { state: 'rejected', reason: 'session_not_ready' };
      const result = await queueMessage(args);
      ctx.assertCurrent();
      return result;
    },
    async checkSend(
      args: Parameters<typeof checkSend>[0] & {
        workspaceId: string;
        userId: string;
      },
    ) {
      const ctx = managementContext(args);
      if (
        !catalogs
          .get('meta')
          ?.sessions.some((item) => item.id === args.sessionId)
      )
        return { state: 'unknown', reason: 'session_not_ready' };
      const result = await checkSend(args);
      ctx.assertCurrent();
      return result;
    },
    editSession(args: Parameters<typeof editSession>[0]) {
      if (!metaReplica || unhealthy.size)
        return { state: 'not_sent', reason: 'metadata_not_ready' };
      const meta = metaReplica.flock.get(['m', `session-${args.sessionId}`]) as
        Record<string, any> | undefined;
      if (!meta) return { state: 'not_sent', reason: 'session_not_ready' };
      const capability = machineReplicas
        .get(meta.machineId)
        ?.get(['acpCapability', meta.agentConfigId]) as
        Record<string, any> | undefined;
      return editSession(args, meta, capability);
    },
    sendTurn(
      args: Parameters<typeof sendSessionTurn>[0] & { workspaceId: string },
    ) {
      if (!metaReplica)
        return { state: 'not_sent', reason: 'metadata_not_ready' };
      let ctx: ReturnType<typeof managementContext>;
      try {
        ctx = managementContext(args, undefined, 120000);
      } catch {
        return { state: 'not_sent', reason: 'metadata_not_ready' };
      }
      const session = catalogs
        .get('meta')
        ?.sessions.find((item) => item.id === args.sessionId);
      if (!session || session.machineId !== args.machineId)
        return { state: 'not_sent', reason: 'session_not_ready' };
      const fields = docFields(ctx.meta, `session-${session.id}`);
      const agentConfigId =
        typeof fields.agentConfigId === 'string' ? fields.agentConfigId : '';
      const source = {
        workspaceId: ctx.workspaceId,
        sessionId: session.id,
        userId: ctx.userId,
        projectId: session.projectId,
        machineId: session.machineId,
        agentConfigId,
        cliType: session.cliType,
        agentType: session.agentType,
      };
      return sendSessionTurn(
        args,
        async (text) => {
          ctx.assertCurrent();
          const result = await expandMentions(text, (category) =>
            getMentions({ ...source, category }),
          );
          ctx.assertCurrent();
          return result;
        },
        async (previous, input) => {
          ctx.assertCurrent();
          const result = await resolveTurnRunOptions(args, previous, input, {
            ...ctx,
            machineId: session.machineId,
            agentConfigId,
          });
          ctx.assertCurrent();
          return result;
        },
      );
    },
    start(id: string, userId?: string, active = true) {
      if (workspace && (workspace !== id || runtimeUserId !== (userId ?? '')))
        stopRuntime();
      if (runtimeLifetime.signal.aborted)
        runtimeLifetime = new AbortController();
      workspace = id;
      runtimeUserId = userId ?? '';
      if (!watchers.has('meta')) watch('meta');
      if (active) startPresence();
    },
    stop: stopRuntime,
    setActive(active: boolean) {
      if (!workspace) return;
      if (active) startPresence();
      else {
        stopPresence?.();
        stopPresence = undefined;
      }
    },
    grant(value: Grant | null) {
      if (!value) grantReject?.(new Error('grant_failed'));
      else {
        grant = value;
        expiresAt = Date.now() + Math.max(1, value.expiresIn - 30) * 1000;
        grantResolve?.(value);
      }
      grantResolve = undefined;
      grantReject = undefined;
    },
  },
});
send({ type: 'ready' });
