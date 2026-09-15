import { prepareChatEntries, type PreparedChatEntries } from '@lody-ios/kit';
import { localGeneration, readLocal } from '../../cloud/kv';
import type { Envelope, Snapshot } from '../../models/session';
import { changedFiles } from './transcript/changes';

export type PreparedSessionHistory = {
  key: string;
  generation: number;
  snapshot: Snapshot;
  entriesJSON: string;
  nativeEntries: PreparedChatEntries;
};

export function sessionHistoryKey(
  userId: string,
  workspaceId: string,
  sessionId: string,
) {
  return `session:${JSON.stringify([userId, workspaceId, sessionId])}`;
}

export function sessionEntriesJSON(snapshot: Snapshot) {
  return JSON.stringify(
    snapshot.entries.map((entry) => ({
      ...entry,
      fileDiffs: changedFiles(entry),
    })),
  );
}

export async function prepareSessionHistory(
  userId: string,
  workspaceId: string,
  sessionId: string,
) {
  if (!userId || !workspaceId) return;
  const key = sessionHistoryKey(userId, workspaceId, sessionId);
  const generation = localGeneration();
  const saved = await readLocal<Envelope>(key);
  if (
    generation !== localGeneration() ||
    saved?.v !== 1 ||
    !Array.isArray(saved.entries)
  )
    return;
  try {
    const snapshot = { ...saved, status: 'syncing' };
    const entriesJSON = sessionEntriesJSON(snapshot);
    const nativeEntries = await prepareChatEntries(entriesJSON);
    if (generation !== localGeneration()) return;
    return { key, generation, snapshot, entriesJSON, nativeEntries };
  } catch {
    // An unreadable cache must not prevent opening or synchronizing a session.
    return;
  }
}
