import type { LoroDoc, LoroList, LoroMap } from 'loro-crdt/base64';

export type ItemSummary =
  | { itemId: string; rev: number; type: 'text'; text: string }
  | { itemId: string; rev: number; type: 'thought'; text: string }
  | {
      itemId: string;
      rev: number;
      type: 'tool_call';
      kind: string;
      title: string;
      status: string;
      path?: string;
      added?: number;
      removed?: number;
      hasDetail: boolean;
      permission?: {
        requestId: string;
        pending: boolean;
        options?: { optionId: string; name: string; kind?: string }[];
      };
    }
  | {
      itemId: string;
      rev: number;
      type: 'plan';
      entries: { content: string; status: string; priority?: string }[];
    }
  | {
      itemId: string;
      rev: number;
      type: 'subagent_task';
      taskId: string;
      status: string;
      actor?: string;
      description?: string;
    }
  | { itemId: string; rev: number; type: string };

export type EntrySummary = {
  id: string;
  rev: number;
  role: string;
  status: string;
  finished: boolean;
  timestamp?: string;
  startedAt?: number;
  endedAt?: number;
  permissionWaitMs?: number;
  items: ItemSummary[];
};

export type Envelope = {
  v: 1;
  status: string;
  reason?: string;
  revision: number;
  awaitingUserSince?: number;
  composer?: { modelId?: string; modeId?: string; effort?: string };
  entries: EntrySummary[];
};

let revision = 0;
type Projection = {
  revs: Map<string, { rev: number; fingerprint: string }>;
  entries: Map<
    string,
    { fingerprint: string; value: EntrySummary & { userTurnId?: string } }
  >;
};
const projections = new WeakMap<LoroDoc, Projection>();
function projectionFor(doc: LoroDoc) {
  let projection = projections.get(doc);
  if (!projection) {
    projection = { revs: new Map(), entries: new Map() };
    projections.set(doc, projection);
  }
  return projection;
}
function bump(projection: Projection, key: string, fingerprint: string) {
  const previous = projection.revs.get(key);
  if (previous && previous.fingerprint === fingerprint) return previous.rev;
  const rev = (previous?.rev ?? 0) + 1;
  projection.revs.set(key, { rev, fingerprint });
  return rev;
}

export function itemRev(doc: LoroDoc, entryId: string, itemId: string) {
  return projectionFor(doc).revs.get(`${entryId}/${itemId}`)?.rev ?? 0;
}

export function identityAt(list: LoroList, index: number) {
  const id = list.getIdAt(index);
  return id ? `${id.peer}:${id.counter}` : `idx:${index}`;
}

function countDiff(content: unknown) {
  if (!Array.isArray(content)) return undefined;
  let added = 0,
    removed = 0,
    path: string | undefined;
  for (const block of content) {
    if (!block || block.type !== 'diff') continue;
    path ??= typeof block.path === 'string' ? block.path : undefined;
    const before = String(block.oldText ?? '').split('\n');
    const after = String(block.newText ?? '').split('\n');
    const shared = new Set(before);
    for (const line of after) if (!shared.has(line)) added += 1;
    const target = new Set(after);
    for (const line of before) if (!target.has(line)) removed += 1;
  }
  return path === undefined && added === 0 && removed === 0
    ? undefined
    : { path, added, removed };
}

function summarizeItem(
  projection: Projection,
  raw: any,
  entryId: string,
  identity: string,
) {
  const type = String(raw?.type ?? 'unknown');
  const itemId =
    type === 'tool_call' && typeof raw.toolCallId === 'string'
      ? raw.toolCallId
      : identity;
  const key = `${entryId}/${itemId}`;

  if (type === 'system_notice') {
    const name = typeof raw.name === 'string' ? raw.name : '';
    return { itemId, rev: bump(projection, key, name), type, name };
  }

  if (type === 'text' || type === 'thought') {
    const text = typeof raw.text === 'string' ? raw.text : '';
    return {
      itemId,
      rev: bump(projection, key, text),
      type,
      text,
    } as ItemSummary;
  }

  if (type === 'image') {
    const image = {
      id: String(raw.imageId ?? ''),
      fileName: String(raw.fileName ?? '图片'),
      storageSessionId:
        typeof raw.storageSessionId === 'string'
          ? raw.storageSessionId
          : undefined,
      width:
        typeof raw.width === 'number' && raw.width > 0 ? raw.width : undefined,
      height:
        typeof raw.height === 'number' && raw.height > 0
          ? raw.height
          : undefined,
    };
    return {
      itemId,
      rev: bump(projection, key, JSON.stringify(image)),
      type,
      image,
    } as ItemSummary;
  }
  if (type === 'file') {
    const text = `文件：${String(raw.fileName ?? '附件')}`;
    return {
      itemId,
      rev: bump(projection, key, text),
      type: 'text',
      text,
    } as ItemSummary;
  }

  if (type === 'tool_call') {
    const diff = countDiff(raw.content);
    const permission = raw.permissionRequest
      ? {
          requestId: String(raw.permissionRequest.requestId ?? ''),
          pending: raw.permissionRequest.outcome == null,
          options: raw.permissionRequest.options,
        }
      : undefined;
    const summary = {
      itemId,
      rev: 0,
      type,
      kind: String(raw.kind ?? 'other'),
      title: String(raw.title ?? raw.toolName ?? ''),
      status: String(raw.status ?? 'pending'),
      path: diff?.path,
      added: diff?.added,
      removed: diff?.removed,
      hasDetail: Array.isArray(raw.content) ? raw.content.length > 0 : false,
      permission,
    };
    summary.rev = bump(projection, key, JSON.stringify(summary));
    return summary as ItemSummary;
  }

  if (type === 'plan') {
    const entries = (Array.isArray(raw.entries) ? raw.entries : []).map(
      (e: any) => ({
        content: String(e?.content ?? ''),
        status: String(e?.status ?? 'pending'),
        priority: e?.priority == null ? undefined : String(e.priority),
      }),
    );
    return {
      itemId,
      rev: bump(projection, key, JSON.stringify(entries)),
      type,
      entries,
    } as ItemSummary;
  }

  if (type === 'subagent_task') {
    const summary = {
      itemId,
      rev: 0,
      type,
      taskId: String(raw.taskId ?? itemId),
      status: String(raw.status ?? 'pending'),
      actor: raw.actor == null ? undefined : String(raw.actor),
      description:
        raw.description == null ? undefined : String(raw.description),
    };
    summary.rev = bump(projection, key, JSON.stringify(summary));
    return summary as ItemSummary;
  }

  return { itemId, rev: bump(projection, key, type), type } as ItemSummary;
}

function summarizeEntry(
  projection: Projection,
  history: LoroList,
  entry: any,
  index: number,
) {
  const id = String(entry?.id ?? identityAt(history, index));
  const fingerprint = JSON.stringify(entry);
  const cached = projection.entries.get(id);
  if (cached && cached.fingerprint === fingerprint) return cached.value;
  const container = history.get(index) as LoroMap | undefined;
  const items =
    container && typeof (container as any).get === 'function'
      ? ((container as any).get('items') as LoroList | undefined)
      : undefined;
  const list = Array.isArray(entry?.items) ? entry.items : [];
  const summarizedItems: ItemSummary[] = list.map((item: any, i: number) =>
    summarizeItem(
      projection,
      item,
      id,
      items && typeof items.getIdAt === 'function'
        ? identityAt(items, i)
        : `idx:${index}:${i}`,
    ),
  );
  const fileDiffs = (Array.isArray(entry?.fileDiff) ? entry.fileDiff : [])
    .filter((diff: any) => diff && typeof diff.filePath === 'string')
    .map((diff: any) => ({
      path: String(diff.filePath),
      add: Number(diff.add) || 0,
      del: Number(diff.del) || 0,
    }));
  const value = {
    id,
    rev: bump(
      projection,
      `entry/${id}`,
      summarizedItems.map((i) => `${i.itemId}:${i.rev}`).join(',') +
        `|${entry?.status}|${entry?.finished}|${JSON.stringify(fileDiffs)}`,
    ),
    role: String(entry?.role ?? 'assistant'),
    status: entry?.status ?? (entry?.read ? 'seen' : 'pending'),
    finished: entry?.finished === true,
    timestamp: entry?.timestamp,
    startedAt: entry?.startedAt,
    endedAt: entry?.endedAt,
    permissionWaitMs: entry?.permissionWaitMs,
    userTurnId: entry?.userTurnId,
    items: summarizedItems,
    ...(fileDiffs.length ? { fileDiffs } : {}),
  };
  projection.entries.set(id, { fingerprint, value });
  return value;
}

export function projectSession(
  doc: LoroDoc,
  status: string,
  reason?: string,
): Envelope {
  const history = doc.getList('history') as LoroList;
  const raw = history.toJSON() as any[];
  const input = raw.findLast((entry) => entry?.role === 'user')?.inputConfig;
  const options =
    input?.configOptionValues && typeof input.configOptionValues === 'object'
      ? input.configOptionValues
      : {};
  const effort = [options.reasoning_effort, options.effort].find(
    (value) => typeof value === 'string',
  );
  const summarized = raw.map((entry, index) =>
    summarizeEntry(projectionFor(doc), history, entry, index),
  );

  // A daemon history-sync timeout can place a concurrent reply before its input.
  // Use its explicit causal link; never sort streamed turns by arrival time.
  const userIds = new Set(
    summarized.filter((e) => e.role === 'user').map((e) => e.id),
  );
  const replies = new Map<string, typeof summarized>();
  for (const entry of summarized)
    if (entry.role === 'assistant' && userIds.has(entry.userTurnId!)) {
      const group = replies.get(entry.userTurnId!) ?? [];
      group.push(entry);
      replies.set(entry.userTurnId!, group);
    }
  const ordered = summarized.flatMap((entry) =>
    entry.role === 'assistant' && userIds.has(entry.userTurnId!)
      ? []
      : [
          entry,
          ...(entry.role === 'user' ? (replies.get(entry.id) ?? []) : []),
        ],
  );

  const waitingSteerIds = new Set(
    raw
      .filter((entry) => entry.inputConfig?._lodyDeliveryKind === 'steer')
      .map((entry) => entry.id),
  );
  revision += 1;
  const session = doc.getMap('session').toJSON();
  return {
    v: 1,
    status,
    reason,
    revision,
    awaitingUserSince:
      typeof session?.awaitingUserSince === 'number'
        ? session.awaitingUserSince
        : undefined,
    ...(input
      ? {
          composer: {
            ...(typeof input.modelId === 'string'
              ? { modelId: input.modelId }
              : {}),
            ...(typeof input.modeId === 'string'
              ? { modeId: input.modeId }
              : {}),
            ...(typeof effort === 'string' ? { effort } : {}),
          },
        }
      : {}),
    entries: [
      ...ordered.map(({ userTurnId, ...entry }) => {
        const waitingSteer =
          entry.role === 'user' &&
          waitingSteerIds.has(entry.id) &&
          ['pending_apply', 'pending', 'seen'].includes(entry.status) &&
          !replies.has(entry.id);
        if (!waitingSteer) return entry;
        return { ...entry, status: 'queued', canSteer: false };
      }),
      ...(doc.getMovableList('mq').toJSON() as any[])
        .filter(
          (item) =>
            typeof item.userTurnId === 'string' &&
            !userIds.has(item.userTurnId),
        )
        .map((item) => ({
          id: item.userTurnId,
          role: 'user',
          status: 'queued',
          finished: false,
          rev: 0,
          timestamp: item.timestamp,
          items: (
            item.acpSessionConfig?.inputBlocks ?? [
              { type: 'text', text: item.task },
            ]
          ).map((block: any, index: number) =>
            summarizeItem(
              projectionFor(doc),
              block,
              item.userTurnId,
              `queue:${index}`,
            ),
          ),
        })),
    ],
  };
}
