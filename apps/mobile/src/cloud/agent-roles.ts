import { agentRolesRaw } from '@lody-ios/kit';
import type {
  AgentRoleRequest,
  AgentRoleSnapshot,
} from '@lody/cloud-runtime/models/agent-roles';
import { t } from '@/lib/i18n';
export type AgentRoleService = (
  request: AgentRoleRequest,
) => Promise<AgentRoleSnapshot>;
export function roleError(cause: unknown): {
  message: string;
  uncertain: boolean;
} {
  const value = String(cause);
  const keys = {
    role_read_only: 'settings.roles.readOnly',
    role_conflict: 'settings.remote.conflict',
    role_duplicate: 'settings.roles.duplicate',
    role_forbidden: 'settings.roles.accessDenied',
    role_target_unavailable: 'settings.roles.targetUnavailable',
    role_invalid: 'settings.roles.invalid',
  } as const;
  for (const [code, key] of Object.entries(keys))
    if (value.includes(code)) return { message: t(key), uncertain: false };
  // A native timeout may have followed a durable write; require a fresh read.
  return { message: t('settings.roles.unknown'), uncertain: true };
}
export const requestAgentRoles: AgentRoleService = async (request) => {
  const value: unknown = JSON.parse(
    await agentRolesRaw(JSON.stringify(request)),
  );
  if (
    !value ||
    typeof value !== 'object' ||
    !Array.isArray((value as AgentRoleSnapshot).roles) ||
    !Array.isArray((value as AgentRoleSnapshot).agents)
  )
    throw new Error('role_response_invalid');
  return value as AgentRoleSnapshot;
};
