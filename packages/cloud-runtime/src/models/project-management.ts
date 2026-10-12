import type { Project } from './catalog.ts';
import type { MentionCatalog } from './mentions.ts';

export type WorktreeScriptConfig = {
  scripts: { bash?: string; powershell?: string };
  timeoutMs?: number;
};
export type WorktreeCleanupItem = {
  sessionId: string;
  title: string;
  path: string;
};
export type WorktreePreflight = {
  clean: WorktreeCleanupItem[];
  dirty: WorktreeCleanupItem[];
  failed: (WorktreeCleanupItem & { message: string })[];
};
export type WorktreeCleanupResult = {
  completedAt: number;
  deleted: WorktreeCleanupItem[];
  skippedDirty: WorktreeCleanupItem[];
  failed: (WorktreeCleanupItem & { message: string })[];
};
export type ManagedProject = Project & {
  source: 'local' | 'github';
  machineName?: string;
  shell?: 'bash' | 'powershell';
  owned: boolean;
  online?: boolean;
  sharedWithTeam?: boolean;
  canShare: boolean;
  conversationCount: number;
  runningSessionCount: number;
  affectedSessions?: { id: string; title: string; status: string }[];
  worktreeSetup?: WorktreeScriptConfig;
  worktreeCleanup?: WorktreeScriptConfig;
  scriptErrors?: Partial<Record<'setup' | 'cleanup', string>>;
  removal?: {
    requestedAt: number;
    status: 'pending' | 'completed' | 'unknown';
    cleanupWorktrees: boolean;
    cleanupResult?: WorktreeCleanupResult;
  };
};
export type ProjectManagementRequest =
  | { kind: 'list' }
  | { kind: 'detail' | 'preflight' | 'skills'; projectId: string }
  | {
      kind: 'save-script';
      projectId: string;
      phase: 'setup' | 'cleanup';
      config: WorktreeScriptConfig;
    }
  | { kind: 'share'; projectId: string; sharedWithTeam: boolean }
  | { kind: 'remove'; projectId: string; cleanupWorktrees: boolean }
  | { kind: 'cancel' };
export type ProjectManagementResult = {
  projects: ManagedProject[];
  cloudUnavailable?: boolean;
  preflight?: WorktreePreflight;
  skills?: MentionCatalog;
};
