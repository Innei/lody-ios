import { Flock } from '@loro-dev/flock-wasm/base64';
import { encodeFrame } from '../frames.ts';
import { githubProject } from '../protocol/catalog.ts';
import type { Project, Session } from '../models/catalog.ts';
import type { MentionCatalog } from '../models/mentions.ts';
import type {
  ManagedProject,
  ProjectManagementRequest,
  ProjectManagementResult,
  WorktreeCleanupItem,
  WorktreeCleanupResult,
  WorktreePreflight,
  WorktreeScriptConfig,
} from '../models/project-management.ts';
import { projectControl } from './local-projects.ts';
import { openSettings } from './settings.ts';

type Context = {
  workspaceId: string;
  userId: string;
  meta: Flock;
  machines: Map<string, Flock>;
  projects: Project[];
  sessions: Session[];
  onlineMachineIds?: readonly string[];
  getGrant: Parameters<typeof projectControl>[3];
  signal: AbortSignal;
  cloud: (method: string, args: Record<string, unknown>) => Promise<unknown>;
  skills: (projectId: string) => Promise<MentionCatalog>;
  assertCurrent?: () => void;
};
const object = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
const text = (value: unknown) => (typeof value === 'string' ? value : '');
const field = (meta: Flock, machineId: string, name: string) =>
  meta.get(['m', `machine-${machineId}`, name]) ??
  object(meta.get(['m', `machine-${machineId}`]))[name];
// A lost append ACK requires reconciliation before the command may be attempted again.
const uncertainRemovals = new Set<string>();

export function worktreeScript(value: unknown): WorktreeScriptConfig {
  const config = object(value),
    scripts = object(config.scripts);
  if (
    !value ||
    !config.scripts ||
    Array.isArray(config.scripts) ||
    typeof config.scripts !== 'object' ||
    Object.keys(config).some(
      (key) => !['scripts', 'timeoutMs'].includes(key),
    ) ||
    Object.keys(scripts).some((key) => !['bash', 'powershell'].includes(key)) ||
    Object.values(scripts).some(
      (script) =>
        typeof script !== 'string' ||
        script.length > 65536 ||
        script.includes('\0'),
    ) ||
    (config.timeoutMs !== undefined &&
      (!Number.isSafeInteger(config.timeoutMs) ||
        Number(config.timeoutMs) <= 0))
  )
    throw new Error('invalid_project_script');
  return {
    scripts: { ...scripts } as WorktreeScriptConfig['scripts'],
    ...(config.timeoutMs === undefined
      ? {}
      : { timeoutMs: Number(config.timeoutMs) }),
  };
}

function cleanupItems(
  value: unknown,
  originalRootPath: string,
  failed = false,
) {
  if (!Array.isArray(value)) throw new Error('invalid_project_cleanup');
  return value.map((raw): WorktreeCleanupItem & { message?: string } => {
    const item = object(raw);
    const path = text(item.path);
    // A machine must never claim the source directory as a cleanup candidate.
    const normalize = (path: string) =>
      path.replace(/[\\/]+$/, '').replace(/\\/g, '/');
    if (
      !text(item.sessionId) ||
      typeof item.title !== 'string' ||
      !path ||
      normalize(path) === normalize(originalRootPath) ||
      (failed && typeof item.message !== 'string')
    )
      throw new Error('invalid_project_cleanup');
    return {
      sessionId: text(item.sessionId),
      title: item.title,
      path,
      ...(failed ? { message: text(item.message) } : {}),
    };
  });
}
export function worktreePreflight(
  value: unknown,
  rootPath: string,
): WorktreePreflight {
  const result = object(value);
  return {
    clean: cleanupItems(result.clean, rootPath),
    dirty: cleanupItems(result.dirty, rootPath),
    failed: cleanupItems(
      result.failed,
      rootPath,
      true,
    ) as WorktreePreflight['failed'],
  };
}
function cleanupResult(
  value: unknown,
  rootPath: string,
): WorktreeCleanupResult {
  const result = object(value);
  if (
    !Number.isSafeInteger(result.completedAt) ||
    Number(result.completedAt) <= 0
  )
    throw new Error('invalid_project_cleanup');
  return {
    completedAt: Number(result.completedAt),
    deleted: cleanupItems(result.deleted, rootPath),
    skippedDirty: cleanupItems(result.skippedDirty, rootPath),
    failed: cleanupItems(
      result.failed,
      rootPath,
      true,
    ) as WorktreeCleanupResult['failed'],
  };
}

export function managedProjects(
  ctx: Context,
  cloudValue?: unknown,
): ManagedProject[] {
  const cloud = object(cloudValue);
  const access = Array.isArray(cloud.access) ? cloud.access.map(object) : [];
  const projects = new Map<string, ManagedProject>();
  const addLocal = (
    machineId: string,
    localProjectId: string,
    value: unknown,
    command?: unknown,
  ) => {
    const row = object(value),
      removal = object(command);
    const id = `${machineId}:local:${localProjectId}`;
    const rootPath = text(row.rootPath) || text(removal.originalRootPath);
    if (!rootPath || !localProjectId) return;
    const owned =
      !!ctx.userId && field(ctx.meta, machineId, 'ownerUserId') === ctx.userId;
    const sharing = access.find(
      (row) =>
        row.machineId === machineId && row.localProjectId === localProjectId,
    );
    const sessions = ctx.sessions.filter(
      (session) => session.projectId === id && !session.archived,
    );
    let pending: ManagedProject['removal'];
    if (
      uncertainRemovals.has(
        `${ctx.userId}:${ctx.workspaceId}:mf:${machineId}:${localProjectId}`,
      )
    )
      pending = { requestedAt: 0, status: 'unknown', cleanupWorktrees: false };
    if (command !== undefined) {
      const known =
        removal.v === 1 && Number.isSafeInteger(removal.requestedAt);
      pending = {
        requestedAt: Number(removal.requestedAt) || 0,
        status: known ? 'pending' : 'unknown',
        cleanupWorktrees: removal.cleanupWorktrees === true,
      };
      if (known && removal.status === 'completed') pending.status = 'completed';
      if (removal.cleanupResult !== undefined)
        pending.cleanupResult = cleanupResult(removal.cleanupResult, rootPath);
    }
    projects.set(id, {
      id,
      source: 'local',
      machineId,
      rootPath,
      name: text(row.name) || text(removal.projectName) || localProjectId,
      machineName: text(field(ctx.meta, machineId, 'name')) || machineId,
      shell:
        field(ctx.meta, machineId, 'os') === 'win32' ? 'powershell' : 'bash',
      owned,
      canShare: owned && sharing?.ownerUserId === ctx.userId && !pending,
      sharedWithTeam:
        typeof sharing?.sharedWithTeam === 'boolean'
          ? sharing.sharedWithTeam
          : undefined,
      online: ctx.onlineMachineIds?.includes(machineId),
      conversationCount: sessions.length,
      runningSessionCount: sessions.filter((session) =>
        ['initializing', 'running', 'requestPermission'].includes(
          session.status,
        ),
      ).length,
      removal: pending,
    });
  };
  for (const project of ctx.projects) {
    const prefix = `${project.machineId}:local:`;
    if (project.id.startsWith(prefix))
      addLocal(
        project.machineId,
        project.id.slice(prefix.length),
        project,
        ctx.machines
          .get(project.machineId)
          ?.get(['cmd', 'deleteLocalProject', project.id.slice(prefix.length)]),
      );
  }
  for (const [machineId, flock] of ctx.machines) {
    if (ctx.meta.get(['e', `machine-${machineId}`]) !== true) continue;
    for (const row of flock.scan()) {
      const id = text(row.key[1]);
      if (row.key[0] === 'localProject')
        addLocal(
          machineId,
          id,
          row.value,
          flock.get(['cmd', 'deleteLocalProject', id]),
        );
      if (row.key[0] === 'cmd' && row.key[1] === 'deleteLocalProject')
        addLocal(
          machineId,
          text(row.key[2]),
          flock.get(['localProject', row.key[2]]),
          row.value,
        );
    }
  }
  const repos = Array.isArray(cloud.repos) ? cloud.repos.map(object) : [];
  const availableRepos = new Set(repos.map((row) => text(row.repoFullName)));
  for (const project of ctx.projects) {
    if (
      project.id.startsWith('github:') &&
      !repos.some((row) => row.repoFullName === project.repoFullName)
    )
      repos.push({
        repoFullName: project.repoFullName || project.id.slice(7),
        name: project.name,
      });
  }
  for (const row of repos) {
    const project = githubProject(text(row.repoFullName));
    if (!project) throw new Error('invalid_project_response');
    const sessions = ctx.sessions.filter(
      (session) => session.projectId === project.id && !session.archived,
    );
    projects.set(project.id, {
      ...project,
      name: text(row.name) || project.name,
      source: 'github',
      owned: availableRepos.has(text(row.repoFullName)),
      canShare: false,
      conversationCount: sessions.length,
      runningSessionCount: sessions.filter((session) =>
        ['initializing', 'running', 'requestPermission'].includes(
          session.status,
        ),
      ).length,
      worktreeSetup:
        row.worktreeSetup === undefined
          ? { scripts: {} }
          : worktreeScript(row.worktreeSetup),
      worktreeCleanup:
        row.worktreeCleanup === undefined
          ? { scripts: {} }
          : worktreeScript(row.worktreeCleanup),
    });
  }
  return [...projects.values()].sort((a, b) => a.name.localeCompare(b.name));
}

export async function projectManagement(
  request: ProjectManagementRequest,
  ctx: Context,
): Promise<ProjectManagementResult> {
  if (!ctx.workspaceId || !ctx.userId) throw new Error('project_unavailable');
  if (request.kind === 'cancel') return { projects: [] };
  for (const [machineId, replica] of ctx.machines) {
    const stream = `${ctx.workspaceId}:mf:${machineId}`;
    const prefix = `${ctx.userId}:${stream}:`;
    if (![...uncertainRemovals].some((key) => key.startsWith(prefix))) continue;
    let fresh;
    try {
      fresh = await openSettings(stream, ctx.getGrant, ctx.signal);
    } catch {
      ctx.signal.throwIfAborted();
      ctx.assertCurrent?.();
      continue;
    }
    ctx.assertCurrent?.();
    replica.importJson(fresh.flock.exportJson());
    for (const row of fresh.flock.scan())
      if (row.key[0] === 'cmd' && row.key[1] === 'deleteLocalProject')
        uncertainRemovals.delete(`${prefix}${text(row.key[2])}`);
  }
  let cloud: unknown,
    cloudUnavailable = false;
  try {
    cloud = await ctx.cloud('list', {});
  } catch {
    cloudUnavailable = true;
  }
  ctx.signal.throwIfAborted();
  ctx.assertCurrent?.();
  const projects = managedProjects(ctx, cloud);
  const result: ProjectManagementResult = { projects, cloudUnavailable };
  if (request.kind === 'list') return result;
  const project = projects.find((project) => project.id === request.projectId);
  if (!project) throw new Error('project_unavailable');
  project.affectedSessions = ctx.sessions
    .filter((session) => session.projectId === project.id && !session.archived)
    .map(({ id, title, status }) => ({ id, title, status }));
  const localProjectId = project.id.slice(`${project.machineId}:local:`.length);
  const rpc = (type: string, extra: Record<string, unknown> = {}) =>
    projectControl(
      ctx.workspaceId,
      project.machineId,
      { type, localProjectId, requestedByUserId: ctx.userId, ...extra },
      ctx.getGrant,
      ctx.signal,
    );
  if (request.kind === 'skills') {
    if (project.removal) throw new Error('project_removal_pending');
    return { ...result, skills: await ctx.skills(project.id) };
  }
  if (request.kind === 'detail') {
    if (project.source !== 'local' || project.removal) return result;
    const values = await Promise.allSettled(
      ['setup', 'cleanup'].map(async (phase) => {
        const value = await rpc(`local-project/get-worktree-${phase}`);
        return value === null ? { scripts: {} } : worktreeScript(value);
      }),
    );
    values.forEach((value, index) => {
      const phase = index === 0 ? 'setup' : 'cleanup';
      if (value.status === 'fulfilled') {
        if (phase === 'setup') project.worktreeSetup = value.value;
        else project.worktreeCleanup = value.value;
      } else
        project.scriptErrors = {
          ...project.scriptErrors,
          [phase]: 'project_script_unavailable',
        };
    });
    return result;
  }
  if (project.removal?.status === 'unknown')
    throw new Error('project_write_unknown');
  if (!project.owned || project.removal) throw new Error('project_read_only');
  if (request.kind === 'share') {
    if (
      project.source !== 'local' ||
      !project.canShare ||
      typeof request.sharedWithTeam !== 'boolean'
    )
      throw new Error('project_read_only');
    ctx.assertCurrent?.();
    await ctx.cloud('share', {
      machineId: project.machineId,
      localProjectId,
      sharedWithTeam: request.sharedWithTeam,
    });
    ctx.assertCurrent?.();
    project.sharedWithTeam = request.sharedWithTeam;
    return result;
  }
  if (request.kind === 'save-script') {
    if (!['setup', 'cleanup'].includes(request.phase))
      throw new Error('invalid_project_script');
    let config = worktreeScript(request.config);
    ctx.assertCurrent?.();
    if (project.source === 'github') {
      if (cloudUnavailable) throw new Error('project_unavailable');
      await ctx.cloud('save-github-script', {
        repoFullName: project.repoFullName,
        phase: request.phase,
        config,
      });
    } else {
      const freshMeta = await openSettings(
        `${ctx.workspaceId}:meta`,
        ctx.getGrant,
        ctx.signal,
      );
      ctx.assertCurrent?.();
      if (
        field(freshMeta.flock, project.machineId, 'ownerUserId') !==
          ctx.userId ||
        freshMeta.flock.get(['e', `machine-${project.machineId}`]) !== true
      )
        throw new Error('project_read_only');
      config = worktreeScript(
        await rpc(`local-project/set-worktree-${request.phase}`, { config }),
      );
    }
    ctx.assertCurrent?.();
    if (request.phase === 'setup') project.worktreeSetup = config;
    else project.worktreeCleanup = config;
    return result;
  }
  if (project.source !== 'local') throw new Error('invalid_project_request');
  if (request.kind === 'preflight')
    return {
      ...result,
      preflight: worktreePreflight(
        await rpc('local-project/removal-preflight'),
        project.rootPath,
      ),
    };
  if (
    request.kind !== 'remove' ||
    typeof request.cleanupWorktrees !== 'boolean'
  )
    throw new Error('invalid_project_request');
  // Re-read ownership and the command before a durable, remotely executed removal.
  const freshMeta = await openSettings(
    `${ctx.workspaceId}:meta`,
    ctx.getGrant,
    ctx.signal,
  );
  if (
    field(freshMeta.flock, project.machineId, 'ownerUserId') !== ctx.userId ||
    freshMeta.flock.get(['e', `machine-${project.machineId}`]) !== true
  )
    throw new Error('project_read_only');
  const stream = `${ctx.workspaceId}:mf:${project.machineId}`;
  const fresh = await openSettings(stream, ctx.getGrant, ctx.signal);
  ctx.assertCurrent?.();
  const commandKey = ['cmd', 'deleteLocalProject', localProjectId];
  const key = `${ctx.userId}:${stream}:${localProjectId}`;
  const existing = fresh.flock.get(commandKey);
  if (existing !== undefined) {
    uncertainRemovals.delete(key);
    const replica = ctx.machines.get(project.machineId);
    replica?.importJson(fresh.flock.exportJson());
    result.projects = managedProjects(ctx, cloud);
    return result;
  }
  if (uncertainRemovals.has(key)) throw new Error('project_write_unknown');
  const current = object(fresh.flock.get(['localProject', localProjectId]));
  if (!text(current.rootPath) || current.rootPath !== project.rootPath)
    throw new Error('project_conflict');
  if (request.cleanupWorktrees)
    worktreePreflight(
      await rpc('local-project/removal-preflight'),
      project.rootPath,
    );
  const write = new Flock(`lody-ios-project-removal-${crypto.randomUUID()}`);
  const command = {
    v: 1,
    requestedAt: Date.now(),
    requestedBy: ctx.userId,
    projectName: text(current.name) || project.name,
    originalRootPath: project.rootPath,
    ...(request.cleanupWorktrees ? { cleanupWorktrees: true } : {}),
  };
  write.set(commandKey, command);
  write.commit();
  const update = write.exportJson();
  ctx.signal.throwIfAborted();
  ctx.assertCurrent?.();
  uncertainRemovals.add(key);
  try {
    const saved = await fresh.client.append({
      part: {
        contentType: 'application/octet-stream',
        body: encodeFrame(new TextEncoder().encode(JSON.stringify(update))),
      },
    });
    if (!saved.ok) throw new Error('project_write_unknown');
  } catch {
    throw new Error('project_write_unknown');
  }
  ctx.assertCurrent?.();
  ctx.machines.get(project.machineId)?.importJson(update);
  uncertainRemovals.delete(key);
  project.removal = {
    requestedAt: command.requestedAt,
    status: 'pending',
    cleanupWorktrees: request.cleanupWorktrees,
  };
  return result;
}
