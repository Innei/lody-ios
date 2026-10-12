export type RoleRunConfig = {
  modelId?: string;
  modeId?: string;
  configOptionValues?: Record<string, string | boolean>;
  memory?: { providerId: string; memoryId: string };
};

export type AgentRoleOption = {
  id: string;
  name: string;
  description?: string;
  machineId: string;
  agentConfigId: string;
  agentName: string;
  cliType?: string;
  agentType?: string;
  revision: number;
  runConfig: RoleRunConfig;
  available: boolean;
  unavailableReason?:
    | 'agent_config_missing'
    | 'agent_config_machine_mismatch'
    | 'run_config_unsupported';
};

export type McpServerOption = {
  id: string;
  name: string;
  transport: 'stdio' | 'http';
  enabledByDefault: boolean;
};

export type RunOptionsCatalog = {
  roles: AgentRoleOption[];
  mcpServers: McpServerOption[];
  worktreeAvailable?: boolean;
  unavailable?: boolean;
};

export type RunOptionsRequest = {
  workspaceId: string;
  userId: string;
  machineId?: string;
  agentConfigId?: string;
  projectId?: string;
};

export type RunOptionsChoice = {
  mcpServerIds?: string[];
  agentRoleId?: string | null;
  agentRoleRevision?: number;
  frozenRole?: RoleRunConfig;
};
