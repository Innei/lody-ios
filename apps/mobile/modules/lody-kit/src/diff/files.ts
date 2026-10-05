import {
  fileDiffRaw,
  workspaceChangesRaw,
  listDirRaw,
  readFileRaw,
  turnDiffRaw,
} from '../runtime/LodyKit';

export type DiffSideKind = 'text' | 'missing' | 'binary' | 'too_large';
export type DiffContent =
  | {
      status: 'ok';
      base: 'turn' | 'current';
      path: string;
      handle: string;
      oldKind: DiffSideKind;
      newKind: DiffSideKind;
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

export type FileKind = 'text' | 'markdown' | 'image' | 'binary';
export type FileContent =
  | {
      status: 'ok';
      path: string;
      kind: FileKind;
      handle: string;
      bytes: number;
      mimeType?: string;
    }
  | { status: 'error'; path: string; code: string; message?: string };

export type DirectoryEntry = { name: string; type: 'file' | 'directory' };
export type DirectoryListing = {
  entries: DirectoryEntry[];
  truncated: boolean;
};

export const turnDiff = async (args: {
  sessionId: string;
  entryId: string;
  path: string;
}): Promise<DiffContent> => JSON.parse(await turnDiffRaw(JSON.stringify(args)));

export const fileDiff = async (args: {
  sessionId: string;
  path: string;
}): Promise<DiffContent> => JSON.parse(await fileDiffRaw(JSON.stringify(args)));

export const readFile = async (args: {
  sessionId: string;
  path: string;
}): Promise<FileContent> => JSON.parse(await readFileRaw(JSON.stringify(args)));

export const listDir = async (args: {
  workspaceId: string;
  sessionId: string;
  relativePath: string;
  userId: string;
}): Promise<DirectoryListing> =>
  JSON.parse(await listDirRaw(JSON.stringify(args)));

export function localProjectIdOf(projectId: string): string | undefined {
  const index = projectId.indexOf(':local:');
  return index > 0 ? projectId.slice(index + ':local:'.length) : undefined;
}

export type { WorkspaceChanges } from '../../data-runtime/files';
export const workspaceChanges = async (args: {
  sessionId: string;
}): Promise<import('../../data-runtime/files').WorkspaceChanges> =>
  JSON.parse(await workspaceChangesRaw(JSON.stringify(args)));
