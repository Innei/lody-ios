export type RoleAgent = {
  machineId: string;
  machineName: string;
  id: string;
  name: string;
};
export type RoleTarget = {
  machineId: string;
  agentConfigId: string;
  alias?: string;
  machineName: string;
  agentName: string;
  state: 'configured' | 'machineUnavailable' | 'agentUnavailable';
};
export type AgentRoleItem = {
  id: string;
  ownerUserId: string;
  visibility: 'private' | 'workspace';
  name: string;
  description: string;
  promptPrefix: string;
  revision: number;
  updatedAt: number;
  targets: RoleTarget[];
};
export type AgentRoleSnapshot = { roles: AgentRoleItem[]; agents: RoleAgent[] };
export type RoleFields = Pick<
  AgentRoleItem,
  'name' | 'description' | 'promptPrefix' | 'visibility'
>;
export type AgentRoleRequest = { workspaceId: string } & (
  | { action: 'list' }
  | {
      action: 'save';
      id: string;
      base: AgentRoleItem | null;
      fields: RoleFields;
      target?: { machineId: string; agentConfigId: string };
    }
  | { action: 'delete'; base: AgentRoleItem }
);
