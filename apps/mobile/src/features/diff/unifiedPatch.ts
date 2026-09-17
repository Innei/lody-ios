import { createTwoFilesPatch } from 'diff';

export function unifiedPatch(
  path: string,
  oldText: string,
  newText: string,
): string {
  return createTwoFilesPatch(`a/${path}`, `b/${path}`, oldText, newText);
}
