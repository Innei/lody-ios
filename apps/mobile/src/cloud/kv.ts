import {
  readLocalValue,
  writeLocalValue,
  localStoreGeneration,
} from '@lody-ios/kit';

export const localGeneration = () => localStoreGeneration();
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
export function writeLocal(
  key: string,
  value: unknown,
  current = localGeneration(),
) {
  return writeLocalValue(key, JSON.stringify(value), current);
}
