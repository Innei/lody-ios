export type MentionCategory =
  'file' | 'skill' | 'session' | 'role' | 'issue' | 'pr' | 'cmd';
export type MentionItem = {
  path: string;
  name: string;
  kind: MentionCategory | 'directory';
  subtitle: string;
  insertText?: string;
  scope?: 'project' | 'global' | 'system';
  dir?: string;
  description?: string;
  version?: string;
  author?: string;
  content?: string;
};
export type MentionSource = {
  workspaceId: string;
  sessionId?: string;
  projectId?: string;
  machineId?: string;
  agentConfigId?: string;
  cliType?: string;
  agentType?: string;
};
export type MentionCatalog = {
  items: MentionItem[];
  truncated: boolean;
  incomplete: boolean;
};
