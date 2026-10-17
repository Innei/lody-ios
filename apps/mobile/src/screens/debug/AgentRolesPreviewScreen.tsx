import { useCallback, useEffect, useRef } from 'react';
import type {
  AgentRoleItem,
  AgentRoleSnapshot,
} from '@lody/cloud-runtime/models/agent-roles';
import type { AgentRoleService } from '@/cloud/agent-roles';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { definePage } from '@/lib/presentation';
import { AppText } from '@/ui/AppText';
import { AgentRolesView } from '../AgentRolesScreen';
import { switchSettingsBaselineAccount } from './settingsBaseline';
function View() {
  const { account } = useAuth();
  const cleanup = useRef<(() => void) | null>(null);
  useEffect(() => () => cleanup.current?.(), []);
  const target = {
    machineId: 'm1',
    agentConfigId: 'a1',
    machineName: 'Studio',
    agentName: 'Coder',
    state: 'configured' as const,
  };
  const role = (
    id: string,
    name: string,
    patch: Partial<AgentRoleItem> = {},
  ): AgentRoleItem => ({
    id,
    name,
    ownerUserId: 'me',
    visibility: 'private',
    description: 'Review changes',
    promptPrefix: 'Keep changes focused.',
    revision: 1,
    updatedAt: 1,
    targets: [target],
    ...patch,
  });
  const data = useRef<AgentRoleSnapshot>({
    roles: [
      role('review', 'Reviewer'),
      role('search', 'Search', {
        ownerUserId: 'other',
        visibility: 'workspace',
      }),
      role('missing', 'Needs setup', {
        targets: [
          {
            ...target,
            agentConfigId: 'missing',
            agentName: 'Missing agent',
            state: 'agentUnavailable',
          },
        ],
      }),
      role('multi', 'Everywhere', {
        targets: [
          target,
          {
            ...target,
            machineId: 'm2',
            machineName: 'Laptop',
            agentConfigId: 'a2',
          },
        ],
      }),
    ],
    agents: [
      { id: 'a1', name: 'Coder', machineId: 'm1', machineName: 'Studio' },
      { id: 'a2', name: 'Reviewer', machineId: 'm2', machineName: 'Laptop' },
    ],
  });
  const failList = useRef(true),
    failSave = useRef(true),
    failDelete = useRef(true);
  const service = useCallback<AgentRoleService>(async (request) => {
    if (request.action === 'list' && failList.current) {
      failList.current = false;
      throw new Error('offline');
    }
    if (request.action === 'save') {
      if (request.fields.name === 'Switch') {
        cleanup.current = switchSettingsBaselineAccount();
        return new Promise<AgentRoleSnapshot>(() => {});
      }
      if (
        data.current.roles.some(
          (role) =>
            role.id !== request.id && role.name === request.fields.name.trim(),
        )
      )
        throw new Error('role_duplicate');
      if (request.base && failSave.current) {
        failSave.current = false;
        throw new Error('role_conflict');
      }
      if (request.base)
        data.current.roles = data.current.roles.map((role) =>
          role.id === request.id
            ? {
                ...role,
                ...request.fields,
                revision: role.revision + 1,
                updatedAt: 2,
              }
            : role,
        );
      else {
        const agent = data.current.agents.find(
          (agent) => agent.id === request.target?.agentConfigId,
        )!;
        data.current.roles.push({
          id: request.id,
          ownerUserId: 'me',
          revision: 1,
          updatedAt: 1,
          ...request.fields,
          targets: [
            {
              ...target,
              machineId: agent.machineId,
              agentConfigId: agent.id,
              machineName: agent.machineName,
              agentName: agent.name,
            },
          ],
        });
      }
    }
    if (request.action === 'delete') {
      data.current.roles = data.current.roles.filter(
        (role) => role.id !== request.base.id,
      );
      if (failDelete.current) {
        failDelete.current = false;
        throw new Error('role_write_unknown');
      }
    }
    return structuredClone(data.current);
  }, []);
  if (cleanup.current && account?.user.id === 'settings-baseline-user')
    return <AppText testID="role-scope-switched">Account changed</AppText>;
  return (
    <AgentRolesView workspaceId="offline-roles" userId="me" service={service} />
  );
}
export const AgentRolesPreviewScreen = definePage({
  id: 'agent-roles-preview',
  title: 'Agent Roles',
  Component: View,
  presentation: { headerVariant: 'transparent' },
});
