import type {
  ScheduleRequest,
  ScheduleService,
} from '@lody/cloud-runtime/models/schedules';
import {
  scheduleId,
  validateScheduleDraft,
} from '@lody/cloud-runtime/protocol/schedules';
import { localGeneration, readLocal, writeLocal } from '../../cloud/kv.ts';

export type ScheduleWrite = Extract<ScheduleRequest, { scheduleId: string }> & {
  action: 'create' | 'edit' | 'run' | 'pause' | 'resume' | 'delete';
};
export type PendingScheduleStore = {
  read: () => Promise<ScheduleWrite[]>;
  put: (request: ScheduleWrite) => Promise<void>;
  remove: (id: string) => Promise<void>;
};
let updates = Promise.resolve();
export function pendingScheduleStore(
  userId: string,
  workspaceId: string,
): PendingScheduleStore {
  const key = `schedule-pending:${userId}:${workspaceId}`,
    generation = localGeneration();
  async function read() {
    const saved = await readLocal<ScheduleWrite[]>(key);
    if (!Array.isArray(saved)) return [];
    return saved.filter((request) => {
      if (
        !request ||
        request.workspaceId !== workspaceId ||
        !scheduleId(request.scheduleId) ||
        !['create', 'edit', 'run', 'pause', 'resume', 'delete'].includes(
          request.action,
        )
      )
        return false;
      if (
        request.action !== 'delete' &&
        !('requestId' in request && scheduleId(request.requestId))
      )
        return false;
      if ('draft' in request) {
        try {
          validateScheduleDraft(request.draft);
        } catch {
          return false;
        }
      }
      return true;
    });
  }
  function update(change: (rows: ScheduleWrite[]) => ScheduleWrite[]) {
    const operation = updates.then(async () => {
      if (generation === localGeneration())
        await writeLocal(key, change(await read()), generation);
    });
    updates = operation.catch(() => {});
    return operation;
  }
  return {
    read,
    put: (request) =>
      update((rows) => [
        ...rows.filter((row) => row.scheduleId !== request.scheduleId),
        request,
      ]),
    remove: (id) =>
      update((rows) => rows.filter((row) => row.scheduleId !== id)),
  };
}
export async function performScheduleWrite(
  request: ScheduleWrite,
  service: ScheduleService,
  store: PendingScheduleStore,
) {
  await store.put(request);
  try {
    const result = await service(request);
    await store.remove(request.scheduleId);
    return result;
  } catch (cause) {
    const code = (cause as { code?: string })?.code;
    if (
      code &&
      code !== 'schedule_write_unknown' &&
      code !== 'schedule_unavailable'
    )
      await store.remove(request.scheduleId);
    throw cause;
  }
}
export function memoryScheduleStore(): PendingScheduleStore {
  let rows: ScheduleWrite[] = [];
  return {
    read: async () => rows,
    put: async (request) => {
      rows = [
        ...rows.filter((row) => row.scheduleId !== request.scheduleId),
        request,
      ];
    },
    remove: async (id) => {
      rows = rows.filter((row) => row.scheduleId !== id);
    },
  };
}
