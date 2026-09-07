import { projectControl } from './local-projects';
import { sealedRpc } from './machine-rpc';

type Grant = () => Promise<{ token: string; gatewayBaseUrl: string }>;
export type MachineContext = {
  workspaceId: string;
  machineId: string;
  getGrant: Grant;
  signal: AbortSignal;
};

type EncodedText =
  | { encoding: 'plain' | 'utf8-plain'; text: string; rawBytes: number }
  | {
      encoding: 'gzip-base64' | 'utf8-gzip-base64';
      data: string;
      rawBytes: number;
    }
  | { encoding: 'base64'; data: string; rawBytes: number };

const bytesOf = (base64: string) =>
  Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));

async function gunzip(base64: string) {
  const stream = new Blob([bytesOf(base64)])
    .stream()
    .pipeThrough(new DecompressionStream('gzip'));
  return new Response(stream).text();
}

export async function decodeText(payload: EncodedText): Promise<string> {
  switch (payload.encoding) {
    case 'plain':
    case 'utf8-plain':
      return payload.text;
    case 'gzip-base64':
    case 'utf8-gzip-base64':
      return gunzip(payload.data);
    case 'base64':
      return new TextDecoder().decode(bytesOf(payload.data));
  }
}

type Snapshot =
  | { kind: 'text'; text: EncodedText }
  | { kind: 'missing' | 'binary' | 'too_large' };
export type DiffSide = { kind: Snapshot['kind']; text?: string };

async function side(snapshot: Snapshot): Promise<DiffSide> {
  if (snapshot.kind === 'text')
    return { kind: 'text', text: await decodeText(snapshot.text) };
  if (snapshot.kind === 'missing') return { kind: 'missing', text: '' };
  return { kind: snapshot.kind };
}

type DiffResponse =
  | {
      status: 'ok';
      path: string;
      oldSnapshot: Snapshot;
      newSnapshot: Snapshot;
      add?: number;
      del?: number;
    }
  | { status: 'unavailable'; path: string; reason: string; message?: string };

export type DiffResult =
  | {
      status: 'ok';
      base: 'turn' | 'current';
      path: string;
      old: DiffSide;
      new: DiffSide;
      add?: number;
      del?: number;
    }
  | {
      status: 'unavailable';
      base: 'turn' | 'current';
      path: string;
      reason: string;
      message?: string;
    };

async function toDiffResult(
  response: DiffResponse,
  base: 'turn' | 'current',
): Promise<DiffResult> {
  if (response.status !== 'ok')
    return {
      status: 'unavailable',
      base,
      path: response.path,
      reason: response.reason,
      message: response.message,
    };
  return {
    status: 'ok',
    base,
    path: response.path,
    old: await side(response.oldSnapshot),
    new: await side(response.newSnapshot),
    add: response.add,
    del: response.del,
  };
}

export async function fileDiff(
  ctx: MachineContext,
  args: { sessionId: string; path: string },
): Promise<DiffResult> {
  const response = (await sealedRpc(
    ctx.workspaceId,
    ctx.machineId,
    'code-collab/open-current-diff',
    args.sessionId,
    { sessionId: args.sessionId, path: args.path },
    ctx.getGrant,
    ctx.signal,
  )) as DiffResponse;
  return toDiffResult(response, 'current');
}

export async function turnDiff(
  ctx: MachineContext,
  args: { sessionId: string; entryId: string; path: string },
): Promise<DiffResult> {
  const response = (await sealedRpc(
    ctx.workspaceId,
    ctx.machineId,
    'code-collab/open-turn-diff',
    args.sessionId,
    { sessionId: args.sessionId, turnId: args.entryId, path: args.path },
    ctx.getGrant,
    ctx.signal,
  )) as DiffResponse;
  if (
    response.status === 'unavailable' &&
    response.reason === 'turn_unavailable'
  )
    return fileDiff(ctx, { sessionId: args.sessionId, path: args.path });
  return toDiffResult(response, 'turn');
}

export type DirectoryEntry = { name: string; type: 'file' | 'directory' };

export async function listDir(
  ctx: MachineContext,
  args: { localProjectId: string; relativePath: string; userId: string },
): Promise<{ entries: DirectoryEntry[]; truncated: boolean }> {
  const result = await projectControl(
    ctx.workspaceId,
    ctx.machineId,
    {
      type: 'local-project/list-dir',
      localProjectId: args.localProjectId,
      relativePath: args.relativePath,
      requestedByUserId: args.userId,
      limit: 2000,
    },
    ctx.getGrant,
    ctx.signal,
  );
  if (!Array.isArray(result.entries)) throw new Error('invalid_directory');
  const entries = (result.entries as DirectoryEntry[])
    .filter(
      (entry) =>
        entry &&
        typeof entry.name === 'string' &&
        (entry.type === 'file' || entry.type === 'directory'),
    )
    .map(({ name, type }) => ({ name, type }))
    .sort((a, b) => {
      if (a.type !== b.type) return a.type === 'directory' ? -1 : 1;
      return a.name.localeCompare(b.name, undefined, { sensitivity: 'base' });
    });
  return { entries, truncated: !!result.truncated };
}

export const READ_FILE_MAX_BYTES = 2 * 1024 * 1024;

type PreviewResponse =
  | {
      status: 'ok';
      path: string;
      kind: 'text' | 'binary';
      content: EncodedText;
      mimeType?: string;
      sizeBytes: number;
    }
  | { status: 'error'; path: string; code: string; message?: string };

export type FileContent =
  | { status: 'ok'; path: string; kind: 'text'; text: string; bytes: number }
  | {
      status: 'ok';
      path: string;
      kind: 'binary';
      base64: string;
      mimeType?: string;
      bytes: number;
    }
  | { status: 'error'; path: string; code: string; message?: string };

export async function readFile(
  ctx: MachineContext,
  args: { sessionId: string; path: string },
): Promise<FileContent> {
  const response = (await sealedRpc(
    ctx.workspaceId,
    ctx.machineId,
    'file/preview',
    args.sessionId,
    {
      v: 3,
      sessionId: args.sessionId,
      path: args.path,
      maxBytes: READ_FILE_MAX_BYTES,
    },
    ctx.getGrant,
    ctx.signal,
  )) as PreviewResponse;
  if (response.status !== 'ok')
    return {
      status: 'error',
      path: response.path ?? args.path,
      code: response.code,
      message: response.message,
    };
  if (response.kind === 'binary' && response.content.encoding === 'base64')
    return {
      status: 'ok',
      path: response.path,
      kind: 'binary',
      base64: response.content.data,
      mimeType: response.mimeType,
      bytes: response.sizeBytes,
    };
  return {
    status: 'ok',
    path: response.path,
    kind: 'text',
    text: await decodeText(response.content),
    bytes: response.sizeBytes,
  };
}
