import { scheduleCommand as nativeScheduleCommand } from '@lody-ios/kit';
import type {
  ScheduleRequest,
  ScheduleResult,
  ScheduleService,
} from '@lody/cloud-runtime/models/schedules';
import { t, type TranslationKey } from '../lib/i18n/index.ts';

const errors: Record<string, string> = {
  schedule_owner_only: 'schedules.ownerOnly',
  schedule_owned_machine: 'schedules.ownedMachine',
  schedule_machine_missing: 'schedules.machineMissing',
  schedule_machine_offline: 'schedules.machineOffline',
  schedule_upgrade: 'schedules.upgrade',
  schedule_agent_missing: 'schedules.agentMissing',
  schedule_project_machine: 'schedules.projectMachine',
  schedule_destination_mismatch: 'schedules.destinationMismatch',
  schedule_destination_project: 'schedules.destinationProject',
  schedule_deleted: 'schedules.notFound',
  schedule_not_found: 'schedules.notFound',
  schedule_exists: 'schedules.exists',
  schedule_write_unknown: 'schedules.writeUnknown',
  schedule_idempotency_conflict: 'schedules.retryConflict',
  schedule_proposal_missing: 'schedules.proposalMissing',
  schedule_workspace_changed: 'schedules.workspaceChanged',
  schedule_config_invalid: 'schedules.configInvalid',
  schedule_invalid_time: 'schedules.invalidTime',
  schedule_invalid: 'schedules.invalidDraft',
  schedule_worktree_unavailable: 'schedules.worktreeUnavailable',
};
export const requestSchedules: ScheduleService = async (
  request: ScheduleRequest,
): Promise<ScheduleResult> => {
  try {
    const value = JSON.parse(
      await nativeScheduleCommand(JSON.stringify(request)),
    ) as ScheduleResult;
    if (!value || typeof value !== 'object')
      throw new Error('schedule_invalid');
    if (
      'scheduleId' in request &&
      request.action !== 'show' &&
      !(
        'ok' in value &&
        value.ok === true &&
        'scheduleId' in value &&
        value.scheduleId === request.scheduleId
      )
    )
      throw new Error('schedule_write_unknown');
    return value;
  } catch (cause) {
    const code = Object.keys(errors).find((key) => String(cause).includes(key));
    const write = !['context', 'list', 'show', 'proposal', 'worktree'].includes(
      request.action,
    );
    let key = write ? 'schedules.saveFailed' : 'schedules.loadFailed';
    if (code) key = errors[code];
    const error = new Error(t(key as TranslationKey));
    Object.assign(error, { code: code ?? 'schedule_unavailable' });
    throw error;
  }
};
