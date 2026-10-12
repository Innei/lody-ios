import { projectCommand } from '@lody-ios/kit';
import type {
  ProjectManagementRequest,
  ProjectManagementResult,
} from '@lody/cloud-runtime/models/project-management';
import { t } from '../lib/i18n/index.ts';

export type ProjectManagementService = (
  request: ProjectManagementRequest,
) => Promise<ProjectManagementResult>;

export async function requestProjectManagement(
  workspaceId: string,
  editorId: string,
  request: ProjectManagementRequest,
): Promise<ProjectManagementResult> {
  try {
    const result = JSON.parse(
      await projectCommand(JSON.stringify({ workspaceId, editorId, request })),
    );
    if (!result || !Array.isArray(result.projects))
      throw new Error('invalid_project_response');
    return result;
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : '';
    if (message.includes('project_write_unknown'))
      throw new Error(t('projectManagement.writeUnknown'));
    if (message.includes('project_read_only'))
      throw new Error(t('projectManagement.readOnly'));
    if (message.includes('project_conflict'))
      throw new Error(t('projectManagement.conflict'));
    throw new Error(t('projectManagement.requestFailed'));
  }
}
export function cancelProjectManagement(workspaceId: string, editorId: string) {
  void projectCommand(
    JSON.stringify({ workspaceId, editorId, request: { kind: 'cancel' } }),
  ).catch(() => {});
}
