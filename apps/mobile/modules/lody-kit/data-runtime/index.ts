import {
  projectControl,
  directoryResult,
  registerProject,
} from './local-projects';
import {
  creationOptions,
  createSession,
  type CreateSessionArgs,
} from './create-session';
import { archiveSession, pinSession } from './archive-session';
import {
  fileDiff,
  listDir,
  readFile,
  turnDiff,
  type MachineContext,
} from './files';
import { Flock } from '@loro-dev/flock-wasm/base64';
import { StreamsClient } from '@loro-dev/streams-client';
import { decompress } from 'fzstd';
import type { Catalog } from '../../../src/models/catalog.ts';
import { projectRows } from '../../../src/cloud/catalog/model.ts';
import {
  openSession,
  closeSession,
  retainedSessionIds,
  itemDetail,
  respondPermission,
  sendTurn as sendSessionTurn,
} from './session';
import { decodeFrames, encodeFrame } from '../decoder/frames';

type Grant = { token: string; gatewayBaseUrl: string; expiresIn: number };
const host = (globalThis as any).webkit.messageHandlers.dataRuntime;
const send = (message: object) => host.postMessage(message);
let grantResolve: ((grant: Grant) => void) | undefined;
let grantReject: ((error: Error) => void) | undefined;
let grant: Grant | undefined,
  expiresAt = 0;
let grantPending: Promise<Grant> | undefined;
async function getGrant() {
  if (grant && Date.now() < expiresAt) return grant;
  if (!grantPending) {
    grantPending = new Promise<Grant>((resolve, reject) => {
      grantResolve = resolve;
      grantReject = reject;
      send({ type: 'grant' });
    }).finally(() => {
      grantPending = undefined;
    });
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
const machineReplicas = new Map<string, Flock>();
let creating = false;
let registering = false;
const browsers = new Map<string, AbortController>();

async function markDispatch(sessionId: string, turnId: string) {
  if (!metaReplica) throw new Error('metadata_not_ready');
  const { flock, client } = metaReplica;
  const version = flock.version();
  flock.set(['m', `session-${sessionId}`, 'latestUserMsgId'], turnId);
  flock.set(
    ['m', `session-${sessionId}`, 'lastMissingHistoryUserMsgId'],
    undefined,
  );
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
const unhealthy = new Set<string>();
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
    for (const p of catalogs.get(id)!.projects) projects.set(p.id, p);
  const catalog = JSON.stringify({
    ...meta,
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
            if (mode === 'meta') metaReplica = { flock, client };
            else machineReplicas.set(mode, flock);
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
): MachineContext & { localProjectId?: string } {
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
    localProjectId: session.projectId.startsWith(localPrefix)
      ? session.projectId.slice(localPrefix.length)
      : undefined,
    getGrant,
    signal: AbortSignal.timeout(35000),
  };
}
Object.assign(globalThis, {
  dataRuntime: {
    ping: () => true,
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
    fileDiff(args: { sessionId: string; path: string }) {
      return fileDiff(machineFor(args.sessionId, args.path), args);
    },
    readFile(args: { sessionId: string; path: string }) {
      return readFile(machineFor(args.sessionId, args.path), args);
    },
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
    creationOptions(args: { workspaceId: string; projectId: string }) {
      if (args.workspaceId !== workspace || !metaReplica || unhealthy.size)
        throw new Error('metadata_not_ready');
      return creationOptions(
        args.projectId,
        metaReplica.flock,
        machineReplicas,
      );
    },
    async createSession(args: CreateSessionArgs) {
      if (
        creating ||
        args.workspaceId !== workspace ||
        !metaReplica ||
        unhealthy.size
      )
        return { state: 'rejected' };
      const replica = metaReplica;
      creating = true;
      try {
        const options = creationOptions(
          args.projectId,
          replica.flock,
          machineReplicas,
        );
        const result = await createSession(args, options, replica, getGrant);
        if (result.state === 'created' && metaReplica === replica) {
          catalogs.set('meta', projectRows(replica.flock.scan(), 'meta'));
          publish();
        }
        return result;
      } catch (error) {
        return {
          state:
            error instanceof Error && error.message === 'session_already_exists'
              ? 'unknown'
              : 'rejected',
        };
      } finally {
        creating = false;
      }
    },
    async archiveSession(args: {
      workspaceId: string;
      sessionId: string;
      archived: boolean;
    }) {
      if (args.workspaceId !== workspace || !metaReplica || unhealthy.size)
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
      if (args.workspaceId !== workspace || !metaReplica || unhealthy.size)
        throw new Error('metadata_not_ready');
      const replica = metaReplica;
      await pinSession(args, replica);
      if (metaReplica === replica) {
        catalogs.set('meta', projectRows(replica.flock.scan(), 'meta'));
        publish();
      }
      return {};
    },
    session(id: string) {
      const result = openSession(id, workspace, getGrant, send, markDispatch);
      send({ type: 'sessionSubscriptions', ids: retainedSessionIds() });
      return result;
    },
    closeSession() {
      closeSession();
      send({ type: 'sessionSubscriptions', ids: retainedSessionIds() });
    },
    restoreSessions(ids: string[], current: string | null) {
      for (const id of ids)
        if (id !== current)
          void openSession(id, workspace, getGrant, send, markDispatch);
      if (current)
        void openSession(current, workspace, getGrant, send, markDispatch);
      else closeSession();
      send({ type: 'sessionSubscriptions', ids: retainedSessionIds() });
    },
    itemDetail,
    respondPermission,
    sendTurn(args: Parameters<typeof sendSessionTurn>[0]) {
      if (!metaReplica)
        return { state: 'not_sent', reason: 'metadata_not_ready' };
      return sendSessionTurn(args);
    },
    start(id: string) {
      workspace = id;
      watch('meta');
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
