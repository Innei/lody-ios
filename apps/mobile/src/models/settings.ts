export type QuickReply = {
  id: string;
  label: string;
  message: string;
};

export type RemoteSetting = {
  kind: 'machine' | 'agent' | 'mcp';
  id: string;
  name: string;
  machineId?: string;
  machineName?: string;
  readOnly?: boolean;
  detail?: string;
  prompt?: string;
  enabledByDefault?: boolean;
};

export type SettingsRequest = {
  workspaceId: string;
  kind: RemoteSetting['kind'];
  edit?: {
    item: RemoteSetting;
    name: string;
    prompt?: string;
    enabledByDefault?: boolean;
  };
};
