import {
  readLocalValue,
  writeLocalValue,
  clearLocalValues,
} from '@lody-ios/kit';
export type { SavedAccount } from '../models/auth.ts';
export type { SavedCatalog } from '../models/catalog.ts';
let generation = 0;
let writes = Promise.resolve();
export const localGeneration = () => generation;
export function parseLocal<T>(value: string | null | undefined): T | null {
  try {
    return value ? (JSON.parse(value) as T) : null;
  } catch {
    return null;
  }
}
export async function readLocal<T>(key: string): Promise<T | null> {
  try {
    const value = await readLocalValue(key);
    return parseLocal<T>(value);
  } catch {
    return null;
  }
}
export function writeLocal(key: string, value: unknown, current = generation) {
  const write = writes.then(() => {
    if (current === generation)
      return writeLocalValue(key, JSON.stringify(value));
  });
  writes = write.catch(() => {});
  return write;
}
export async function clearLocal() {
  generation++;
  const clear = writes.then(() => clearLocalValues());
  writes = clear.catch(() => {});
  await clear;
}
export const catalogKey = (userId: string, workspaceId: string) =>
  `catalog:${userId}:${workspaceId}`;
export const selectionKey = (userId: string) => `workspace:${userId}`;
