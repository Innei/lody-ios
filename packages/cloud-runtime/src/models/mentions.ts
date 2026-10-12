import type { PromptShortcutTarget } from './prompt-shortcuts.ts';

export type MentionCategory =
  'file' | 'skill' | 'session' | 'role' | 'issue' | 'pr' | 'cmd' | 'shortcut';
export type MentionItem = {
  path: string;
  name: string;
  kind: MentionCategory | 'directory';
  subtitle: string;
  insertText?: string;
  command?: string;
  emoji?: string;
  disabledReason?: string;
  target?: PromptShortcutTarget;
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
