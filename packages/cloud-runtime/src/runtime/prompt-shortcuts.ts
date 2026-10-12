import { LoroDoc } from 'loro-crdt/base64';
import { clientFor, unpack } from './session.ts';
import { openSettings } from './settings.ts';
import { decodeFrames, encodeFrame } from '../frames.ts';
import {
  expandShortcutTemplate,
  resolveShortcutTargets,
} from './mention-expansion.ts';
import type {
  MentionCatalog,
  MentionCategory,
  MentionItem,
} from '../models/mentions.ts';
import {
  parsePromptShortcut,
  parseShortcutIndex,
  projectShortcutIndex,
  shortcutAvailability,
  shortcutBytes,
  shortcutFailure,
  shortcutObject,
  type PromptShortcut,
  type PromptShortcutScope,
  type PromptShortcutIndexEntry,
  type PromptShortcutDirectoryEntry,
  type PromptShortcutRequest,
  type PromptShortcutResult,
  type ShortcutCloudMethod,
  type PromptShortcutAvailability,
} from '../models/prompt-shortcuts.ts';

export type PromptShortcutContext = {
  workspaceId: string;
  userId: string;
  signal: AbortSignal;
  check(): void;
  cloud(
    method: ShortcutCloudMethod,
    args: Record<string, unknown>,
  ): Promise<unknown>;
};
const check = (ctx: PromptShortcutContext) => {
  ctx.signal.throwIfAborted();
  ctx.check();
  if (!ctx.workspaceId || !ctx.userId) shortcutFailure('permission_denied');
};
async function cloud(
  ctx: PromptShortcutContext,
  method: ShortcutCloudMethod,
  args: Record<string, unknown>,
) {
  check(ctx);
  const result = await ctx.cloud(method, {
    ...args,
    workspaceId: ctx.workspaceId,
  });
  check(ctx);
  if (
    result &&
    typeof result === 'object' &&
    !Array.isArray(result) &&
    'shortcutError' in result
  ) {
    const reason = (result as Record<string, unknown>).shortcutError;
    if (typeof reason === 'string' && /^[a-z_]+$/.test(reason))
      shortcutFailure(reason);
    shortcutFailure('unavailable');
  }
  return result;
}
export const shortcutIndexStream = (
  workspaceId: string,
  ownerUserId: string,
  visibility: 'private' | 'workspace',
) =>
  `shortcut-index:${encodeURIComponent(workspaceId)}:${encodeURIComponent(ownerUserId)}:${visibility}`;
export const shortcutBodyStream = (bodyDocId: string) =>
  `shortcut-body:${encodeURIComponent(bodyDocId)}`;
function scopedGrant(
  ctx: PromptShortcutContext,
  target:
    | {
        kind: 'index';
        ownerUserId: string;
        visibility: 'private' | 'workspace';
      }
    | { kind: 'body'; bodyDocId: string },
  write: boolean,
) {
  const expected =
    target.kind === 'body'
      ? shortcutBodyStream(target.bodyDocId)
      : shortcutIndexStream(
          ctx.workspaceId,
          target.ownerUserId,
          target.visibility,
        );
  let cached:
    { token: string; gatewayBaseUrl: string; expiresAt: number } | undefined;
  return async () => {
    check(ctx);
    if (cached && cached.expiresAt > Date.now() + 5000) return cached;
    const row = shortcutObject(
      await cloud(ctx, 'getStreamToken', { target, write }),
    );
    if (
      row.streamId !== expected ||
      typeof row.token !== 'string' ||
      !row.token ||
      typeof row.gatewayBaseUrl !== 'string' ||
      !row.gatewayBaseUrl.startsWith('https://') ||
      typeof row.expiresIn !== 'number' ||
      !Number.isFinite(row.expiresIn) ||
      row.expiresIn <= 0
    )
      shortcutFailure('permission_denied');
    if (cached && cached.gatewayBaseUrl !== row.gatewayBaseUrl)
      shortcutFailure('permission_denied');
    cached = {
      token: row.token,
      gatewayBaseUrl: row.gatewayBaseUrl,
      expiresAt: Date.now() + row.expiresIn * 1000,
    };
    return cached;
  };
}
function parseDirectory(
  value: unknown,
  ctx: PromptShortcutContext,
): PromptShortcutDirectoryEntry[] {
  if (!Array.isArray(value) || value.length > 10000)
    shortcutFailure('invalid_template');
  const seen = new Set<string>();
  return value.map((value) => {
    const row = shortcutObject(value);
    for (const key of ['shortcutId', 'bodyDocId', 'ownerUserId'])
      if (
        typeof row[key] !== 'string' ||
        !row[key] ||
        (row[key] as string).length > 200
      )
        shortcutFailure('invalid_template');
    if (
      !['private', 'workspace'].includes(String(row.visibility)) ||
      (row.visibility === 'private' && row.ownerUserId !== ctx.userId) ||
      (row.revision !== null &&
        (typeof row.revision !== 'string' ||
          !row.revision ||
          row.revision.length > 200)) ||
      (row.deleted !== undefined && typeof row.deleted !== 'boolean') ||
      seen.has(row.shortcutId as string)
    )
      shortcutFailure('permission_denied');
    seen.add(row.shortcutId as string);
    return row as PromptShortcutDirectoryEntry;
  });
}
async function directory(ctx: PromptShortcutContext) {
  return parseDirectory(await cloud(ctx, 'listAccessibleDocuments', {}), ctx);
}
function matchesDirectory(
  entry: PromptShortcutIndexEntry,
  row: PromptShortcutDirectoryEntry,
) {
  return (
    !row.deleted &&
    entry.id === row.shortcutId &&
    entry.bodyDocId === row.bodyDocId &&
    entry.ownerUserId === row.ownerUserId &&
    entry.visibility === row.visibility &&
    entry.revision === row.revision
  );
}
async function index(
  ctx: PromptShortcutContext,
  ownerUserId: string,
  visibility: 'private' | 'workspace',
  write = false,
) {
  const stream = shortcutIndexStream(ctx.workspaceId, ownerUserId, visibility);
  const grant = scopedGrant(
    ctx,
    { kind: 'index', ownerUserId, visibility },
    write,
  );
  if (write) {
    const created = await (
      await clientFor(stream, grant)
    ).create({ contentType: 'application/octet-stream' });
    check(ctx);
    if (!created.ok) shortcutFailure('offline');
  }
  return openSettings(stream, grant, ctx.signal);
}
function indexEntries(
  flock: Awaited<ReturnType<typeof openSettings>>['flock'],
) {
  const entries: PromptShortcutIndexEntry[] = [];
  for (const row of flock.scan({ prefix: ['promptShortcut'] })) {
    if (row.key.length !== 2 || typeof row.key[1] !== 'string')
      shortcutFailure('invalid_template');
    if (flock.get(['deletedPromptShortcut', row.key[1]]) !== undefined)
      continue;
    const value = shortcutObject(row.value);
    if (value.kind === 'deleted') continue;
    if (value.kind !== 'active') shortcutFailure('invalid_template');
    const entry = parseShortcutIndex(value.entry);
    if (entry.id !== row.key[1]) shortcutFailure('invalid_template');
    entries.push(entry);
  }
  return entries;
}
export async function listPromptShortcuts(
  ctx: PromptShortcutContext,
): Promise<PromptShortcutIndexEntry[]> {
  const rows = (await directory(ctx)).filter((row) => !row.deleted);
  const domains = new Map(
    rows.map((row) => [`${row.ownerUserId}:${row.visibility}`, row]),
  );
  const results: PromptShortcutIndexEntry[] = [];
  for (const domain of domains.values()) {
    const replica = await index(ctx, domain.ownerUserId, domain.visibility);
    check(ctx);
    const entries = indexEntries(replica.flock);
    for (const row of rows.filter(
      (row) =>
        row.ownerUserId === domain.ownerUserId &&
        row.visibility === domain.visibility,
    )) {
      const entry = entries.find((entry) => matchesDirectory(entry, row));
      // Activation may have completed before the final index ACK; never hide that failure.
      if (!entry) shortcutFailure('revision_pending');
      if (entry.workspaceId !== ctx.workspaceId)
        shortcutFailure('permission_denied');
      results.push(entry);
    }
  }
  check(ctx);
  return results.sort((a, b) => a.name.localeCompare(b.name));
}
async function openBody(
  ctx: PromptShortcutContext,
  bodyDocId: string,
  write = false,
) {
  const stream = shortcutBodyStream(bodyDocId);
  const grant = scopedGrant(ctx, { kind: 'body', bodyDocId }, write);
  const client = await clientFor(stream, grant);
  if (write) {
    const created = await client.create({
      contentType: 'application/octet-stream',
    });
    check(ctx);
    if (!created.ok) shortcutFailure('offline');
  }
  const doc = new LoroDoc();
  try {
    const initial = await client.bootstrap({ signal: ctx.signal });
    check(ctx);
    if (!initial.ok) shortcutFailure('offline');
    let bytesRead = 0;
    const consume = (bytes: Uint8Array, snapshot = false) => {
      bytesRead += bytes.length;
      if (bytesRead > 8 * 1024 * 1024) shortcutFailure('size_limit');
      if (snapshot) {
        const decoded = unpack(bytes);
        if (decoded.length > 8 * 1024 * 1024) shortcutFailure('size_limit');
        doc.import(decoded);
      } else for (const frame of decodeFrames(bytes)) doc.import(frame);
    };
    const data = initial.result;
    if (data.snapshotOffset !== '-1' && data.snapshot)
      consume(data.snapshot.body, true);
    for (const part of data.updates) consume(part.body);
    let { nextOffset: offset, cursor, upToDate } = data;
    for (let page = 0; !upToDate; page++) {
      check(ctx);
      if (page >= 100) shortcutFailure('size_limit');
      const next = await client.readOnce({
        offset,
        cursor,
        signal: ctx.signal,
      });
      if (!next.ok || next.result.closed) shortcutFailure('offline');
      if (next.result.payload) consume(next.result.payload.body);
      if (next.result.nextOffset === offset && !next.result.upToDate)
        shortcutFailure('revision_pending');
      ({ nextOffset: offset, cursor, upToDate } = next.result);
    }
    check(ctx);
    return { doc, client };
  } catch (error) {
    doc.free();
    throw error;
  }
}
export function readShortcutDocument(doc: LoroDoc): PromptShortcut | null {
  const revisions = new Map<string, string[]>();
  for (const [id, value] of doc.getMap('revisions').entries()) {
    const row = shortcutObject(value);
    if (
      !id ||
      id.length > 200 ||
      Object.keys(row).length !== 1 ||
      !Array.isArray(row.parents) ||
      row.parents.length > 100 ||
      row.parents.some(
        (parent) =>
          typeof parent !== 'string' ||
          !parent ||
          parent.length > 200 ||
          parent === id,
      ) ||
      new Set(row.parents).size !== row.parents.length
    )
      shortcutFailure('invalid_template');
    revisions.set(id, row.parents as string[]);
  }
  const parentIds = new Set([...revisions.values()].flat());
  const children = new Map<string, string[]>();
  const remaining = new Map(
    [...revisions].map(([id, parents]) => [id, parents.length]),
  );
  for (const [id, parents] of revisions)
    for (const parent of parents) {
      if (!revisions.has(parent)) shortcutFailure('revision_pending');
      children.set(parent, [...(children.get(parent) ?? []), id]);
    }
  const queue = [...remaining]
    .filter(([, degree]) => degree === 0)
    .map(([id]) => id);
  for (let i = 0; i < queue.length; i++)
    for (const child of children.get(queue[i]) ?? []) {
      const degree = remaining.get(child)! - 1;
      remaining.set(child, degree);
      if (degree === 0) queue.push(child);
    }
  if (queue.length !== revisions.size) shortcutFailure('invalid_template');
  const heads = [...revisions.keys()].filter((id) => !parentIds.has(id));
  if (heads.length > 1) shortcutFailure('conflict');
  if (!heads.length) return null;
  const content = doc.getMap('contents').get(heads[0]);
  if (content === undefined) shortcutFailure('revision_pending');
  const shortcut = parsePromptShortcut(content);
  if (shortcut.revision !== heads[0]) shortcutFailure('invalid_template');
  return shortcut;
}
function equalIndex(a: PromptShortcutIndexEntry, b: PromptShortcutIndexEntry) {
  return JSON.stringify(a) === JSON.stringify(b);
}
export async function readPromptShortcut(
  ctx: PromptShortcutContext,
  entry: PromptShortcutIndexEntry,
): Promise<PromptShortcut> {
  entry = parseShortcutIndex(entry);
  const row = (await directory(ctx)).find((row) =>
    matchesDirectory(entry, row),
  );
  if (entry.workspaceId !== ctx.workspaceId || !row)
    shortcutFailure('not_found');
  const replica = await openBody(ctx, entry.bodyDocId);
  try {
    const value = readShortcutDocument(replica.doc);
    if (
      !value ||
      !equalIndex(projectShortcutIndex(value, entry.bodyDocId), entry)
    )
      shortcutFailure('revision_pending');
    if (!(await directory(ctx)).some((row) => matchesDirectory(entry, row)))
      shortcutFailure('permission_denied');
    return value;
  } finally {
    replica.doc.free();
  }
}
async function appendIndex(
  ctx: PromptShortcutContext,
  ownerUserId: string,
  visibility: 'private' | 'workspace',
  mutate: (flock: Awaited<ReturnType<typeof openSettings>>['flock']) => void,
) {
  if (ownerUserId !== ctx.userId) shortcutFailure('permission_denied');
  const { flock, client } = await index(ctx, ownerUserId, visibility, true);
  const version = flock.version();
  check(ctx);
  mutate(flock);
  flock.commit();
  const result = await client.append({
    part: {
      contentType: 'application/octet-stream',
      body: encodeFrame(
        new TextEncoder().encode(JSON.stringify(flock.exportJson(version))),
      ),
    },
  });
  check(ctx);
  if (!result.ok) shortcutFailure('write_unknown');
}
export async function promptShortcuts(
  request: PromptShortcutRequest,
  ctx: PromptShortcutContext,
): Promise<PromptShortcutResult> {
  check(ctx);
  if (request.workspaceId !== ctx.workspaceId)
    shortcutFailure('permission_denied');
  if (request.action === 'list')
    return { entries: await listPromptShortcuts(ctx) };
  if (request.action === 'read')
    return { entries: [], item: await readPromptShortcut(ctx, request.entry) };
  if (request.action === 'save') {
    const value = parsePromptShortcut(request.value);
    const base = request.base && parseShortcutIndex(request.base);
    if (
      value.workspaceId !== ctx.workspaceId ||
      value.ownerUserId !== ctx.userId ||
      !request.bodyDocId ||
      request.bodyDocId.length > 200 ||
      (base &&
        (base.id !== value.id ||
          base.ownerUserId !== value.ownerUserId ||
          base.workspaceId !== value.workspaceId ||
          base.createdAt !== value.createdAt ||
          base.bodyDocId === request.bodyDocId ||
          base.revision === value.revision))
    )
      shortcutFailure('permission_denied');
    const current = await directory(ctx);
    const active = current.find((row) => row.shortcutId === value.id);
    const retry =
      !!active &&
      active.bodyDocId === request.bodyDocId &&
      active.revision === value.revision &&
      !active.deleted;
    if (
      active?.deleted ||
      (!retry && (base ? !active || !matchesDirectory(base, active) : !!active))
    )
      shortcutFailure('conflict');
    const entry = projectShortcutIndex(value, request.bodyDocId);
    const validateIndex = (
      flock: Awaited<ReturnType<typeof openSettings>>['flock'],
    ) => {
      if (flock.get(['deletedPromptShortcut', entry.id]) !== undefined)
        shortcutFailure('conflict');
      const siblings = indexEntries(flock).filter(
        (item) => item.id !== entry.id,
      );
      if (siblings.some((item) => item.slug === entry.slug))
        shortcutFailure('conflict');
      if (
        siblings.length >= 100 ||
        shortcutBytes(JSON.stringify([...siblings, entry])) > 512 * 1024
      )
        shortcutFailure('size_limit');
    };
    const staged = shortcutObject(
      await cloud(ctx, 'stageDocument', {
        ownerUserId: ctx.userId,
        shortcutId: entry.id,
        bodyDocId: entry.bodyDocId,
        visibility: entry.visibility,
      }),
    );
    if (
      staged.bodyDocId !== entry.bodyDocId ||
      !['staged', 'active'].includes(String(staged.status))
    )
      shortcutFailure('invalid_template');
    if (staged.status === 'staged') {
      const replica = await openBody(ctx, entry.bodyDocId, true);
      try {
        const previous = readShortcutDocument(replica.doc);
        if (previous && JSON.stringify(previous) !== JSON.stringify(value))
          shortcutFailure('conflict');
        if (!previous) {
          const version = replica.doc.version();
          replica.doc
            .getMap('contents')
            .set(value.revision, JSON.parse(JSON.stringify(value)));
          replica.doc.getMap('revisions').set(value.revision, { parents: [] });
          replica.doc.commit();
          check(ctx);
          const written = await replica.client.append({
            part: {
              contentType: 'application/octet-stream',
              body: encodeFrame(
                replica.doc.export({ mode: 'update', from: version }),
              ),
            },
          });
          check(ctx);
          if (!written.ok) shortcutFailure('write_unknown');
        }
        await appendIndex(ctx, ctx.userId, value.visibility, validateIndex);
        await cloud(ctx, 'activateDocument', {
          bodyDocId: entry.bodyDocId,
          previousBodyDocId: base?.bodyDocId ?? null,
          previousRevision: base?.revision ?? null,
          revision: entry.revision,
          slug: entry.slug,
          indexBytes: shortcutBytes(JSON.stringify(entry)),
        });
      } finally {
        replica.doc.free();
      }
    } else {
      const published = await readPromptShortcut(ctx, entry);
      if (JSON.stringify(published) !== JSON.stringify(value))
        shortcutFailure('conflict');
    }
    await appendIndex(ctx, ctx.userId, value.visibility, (flock) => {
      validateIndex(flock);
      flock.set(
        ['promptShortcut', entry.id],
        JSON.parse(JSON.stringify({ kind: 'active', entry })),
      );
    });
    if (base && base.visibility !== value.visibility)
      await appendIndex(ctx, ctx.userId, base.visibility, (flock) => {
        const raw = flock.get(['promptShortcut', base.id]);
        if (raw === undefined || raw === null) return;
        const current = shortcutObject(raw);
        if (
          current.kind === 'active' &&
          parseShortcutIndex(current.entry).bodyDocId === base.bodyDocId
        )
          flock.delete(['promptShortcut', base.id]);
      });
    return { entries: await listPromptShortcuts(ctx), item: value };
  }
  if (request.action !== 'delete') shortcutFailure('invalid_template');
  const entry = parseShortcutIndex(request.entry);
  if (entry.workspaceId !== ctx.workspaceId || entry.ownerUserId !== ctx.userId)
    shortcutFailure('permission_denied');
  const current = (await directory(ctx)).find(
    (row) => row.shortcutId === entry.id,
  );
  if (!current || (!current.deleted && !matchesDirectory(entry, current)))
    shortcutFailure('conflict');
  await cloud(ctx, 'revokeShortcut', {
    shortcutId: entry.id,
    bodyDocId: entry.bodyDocId,
    visibility: entry.visibility,
  });
  for (const visibility of ['private', 'workspace'] as const)
    await appendIndex(ctx, ctx.userId, visibility, (flock) =>
      flock.set(['deletedPromptShortcut', entry.id], entry.revision),
    );
  return { entries: await listPromptShortcuts(ctx) };
}

type Loader = (category: MentionCategory) => Promise<MentionCatalog>;
export async function shortcutMentionCatalog(
  ctx: PromptShortcutContext,
  scope: PromptShortcutScope,
  load: Loader,
  onlineMachineIds?: string[],
): Promise<MentionCatalog> {
  const entries = await listPromptShortcuts(ctx);
  const items: MentionItem[] = [];
  for (const entry of entries) {
    let reason: PromptShortcutAvailability = shortcutAvailability(entry, {
      ...ctx,
      scope,
    });
    if (
      reason === 'available' &&
      entry.scope.machineId &&
      onlineMachineIds &&
      !onlineMachineIds.includes(entry.scope.machineId)
    )
      reason = 'machine_offline';
    if (reason === 'available') {
      try {
        await resolveShortcutTargets(
          entry.scope,
          entry.dependencySummary,
          load,
          () => check(ctx),
        );
      } catch (error) {
        check(ctx);
        const message = String(error);
        reason = 'dependencies_unverified';
        for (const known of [
          'dependency_missing',
          'missing_scope',
          'scope_mismatch',
        ] as const)
          if (message.includes(`shortcut_${known}`)) reason = known;
      }
    }
    items.push({
      path: entry.id,
      name: entry.name,
      kind: 'shortcut',
      subtitle: entry.description ?? '',
      command: `/${entry.slug}`,
      insertText: `@shortcut:${encodeURIComponent(entry.id)}`,
      emoji: entry.emoji ?? '📝',
      ...(reason !== 'available'
        ? { disabledReason: `shortcut_${reason}` }
        : {}),
    });
  }
  return { items, truncated: false, incomplete: false };
}
export async function expandShortcut(
  id: string,
  ctx: PromptShortcutContext,
  scope: PromptShortcutScope,
  load: Loader,
): Promise<string> {
  const entry = (await listPromptShortcuts(ctx)).find(
    (entry) => entry.id === id,
  );
  if (!entry) shortcutFailure('not_found');
  const availability = shortcutAvailability(entry, { ...ctx, scope });
  if (availability !== 'available') shortcutFailure(availability);
  const value = await readPromptShortcut(ctx, entry);
  return expandShortcutTemplate(value, { ...ctx, scope }, load, () =>
    check(ctx),
  );
}
