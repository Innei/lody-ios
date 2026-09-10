export type MentionCategory = 'file' | 'skill';
export type MentionItem = {
  path: string;
  name: string;
  kind: 'file' | 'directory' | 'skill';
  subtitle: string;
  insertText?: string;
};
export type MentionSource = {
  workspaceId: string;
  sessionId?: string;
  projectId?: string;
  machineId?: string;
};
export type MentionCatalog = {
  items: MentionItem[];
  truncated: boolean;
  incomplete: boolean;
};
