import { memorySettingsRaw } from '@lody-ios/kit';
import type {
  MemoryRequest,
  MemorySnapshot,
  MemoryStatus,
} from '@lody/cloud-runtime/models/memory';
import { t } from '@/lib/i18n';
export type MemoryService = (request: MemoryRequest) => Promise<MemorySnapshot>;
export const requestMemory: MemoryService = async (request) =>
  JSON.parse(
    await memorySettingsRaw(JSON.stringify(request)),
  ) as MemorySnapshot;
export function memoryError(cause: unknown): {
  text: string;
  uncertain: boolean;
  status?: MemoryStatus;
} {
  const error = String(cause);
  if (error.includes('forbidden'))
    return { text: t('settings.memory.forbidden'), uncertain: false };
  for (const status of [
    'not_installed',
    'not_running',
    'offline',
    'unknown',
    'unsupported',
    'error',
  ] as const)
    if (error.includes(`memory_${status}`))
      return {
        text: t(`settings.memory.status.${status}`),
        uncertain: false,
        status,
      };
  if (error.includes('memory_conflict'))
    return { text: t('settings.remote.conflict'), uncertain: false };
  return { text: t('settings.memory.writeUnknown'), uncertain: true };
}
