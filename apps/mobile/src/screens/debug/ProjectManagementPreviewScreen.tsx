import { useCallback, useRef } from 'react';
import { definePage } from '@/lib/presentation';
import { ProjectManagementFlow } from '../ProjectManagementScreen';
import type { ProjectManagementService } from '@/cloud/project-management';
import type { ManagedProject } from '@lody/cloud-runtime/models/project-management';
import { t } from '@/lib/i18n';

const base: ManagedProject = {
  id: 'studio:local:demo',
  source: 'local',
  machineId: 'studio',
  machineName: 'Studio Mac',
  name: 'Demo Project',
  rootPath: '/Projects/demo',
  shell: 'bash',
  owned: true,
  online: true,
  sharedWithTeam: false,
  canShare: true,
  conversationCount: 3,
  runningSessionCount: 1,
  affectedSessions: [
    { id: 'plan', title: 'Plan the feature', status: 'idle' },
    { id: 'build', title: 'Build the feature', status: 'running' },
    { id: 'review', title: 'Review the feature', status: 'idle' },
  ],
  worktreeSetup: { scripts: { bash: 'pnpm install' } },
  worktreeCleanup: { scripts: {} },
};
const clone = <T,>(value: T): T => JSON.parse(JSON.stringify(value));
const clean = {
  sessionId: 'clean',
  title: 'Clean session',
  path: '/Lody/worktrees/clean',
};
const dirty = {
  sessionId: 'dirty',
  title: 'Uncommitted work',
  path: '/Lody/worktrees/dirty',
};
const failed = {
  sessionId: 'failed',
  title: 'Unavailable worktree',
  path: '/Lody/worktrees/failed',
  message: 'Synthetic inspection failure',
};

function View() {
  const projects = useRef<ManagedProject[]>([
    clone(base),
    {
      ...clone(base),
      id: 'studio:local:empty',
      name: 'Empty Skills',
      rootPath: '/Projects/empty',
    },
    {
      ...clone(base),
      id: 'shared:local:readonly',
      machineId: 'shared',
      machineName: 'Shared Mac',
      name: 'Team Project',
      rootPath: '/Projects/team',
      owned: false,
      canShare: false,
      sharedWithTeam: true,
    },
    {
      ...clone(base),
      id: 'travel:local:offline',
      machineId: 'travel',
      machineName: 'Travel Mac',
      name: 'Offline Project',
      rootPath: '/Projects/offline',
      online: false,
      worktreeSetup: undefined,
      worktreeCleanup: undefined,
      scriptErrors: { setup: 'offline', cleanup: 'offline' },
    },
    {
      ...clone(base),
      id: 'github:LodyAI/Lody',
      source: 'github',
      machineId: '',
      machineName: undefined,
      name: 'LodyAI/Lody',
      repoFullName: 'LodyAI/Lody',
      rootPath: '',
      canShare: false,
      worktreeSetup: {
        scripts: { bash: 'pnpm install', powershell: 'pnpm install' },
      },
    },
  ]);
  const failSave = useRef(true),
    failRemove = useRef(true),
    failShare = useRef(true),
    pendingReads = useRef(0);
  const service = useCallback<ProjectManagementService>(async (request) => {
    const result = () => ({ projects: clone(projects.current) });
    if (request.kind === 'list' || request.kind === 'cancel') return result();
    const project = projects.current.find(
      (item) => item.id === request.projectId,
    );
    if (!project) throw new Error(t('projectManagement.unavailable'));
    if (request.kind === 'detail') {
      if (
        project.removal?.status === 'pending' &&
        project.online &&
        ++pendingReads.current >= 2
      ) {
        project.removal.status = 'completed';
        if (project.removal.cleanupWorktrees)
          project.removal.cleanupResult = {
            completedAt: 123456789,
            deleted: [clean],
            skippedDirty: [dirty],
            failed: [{ ...failed, message: 'Synthetic cleanup failure' }],
          };
      }
      return result();
    }
    if (request.kind === 'skills')
      return {
        ...result(),
        skills: {
          truncated: false,
          incomplete: false,
          items: project.id.endsWith(':empty')
            ? []
            : [
                {
                  path: '.agents/skills/review/SKILL.md',
                  name: 'review',
                  kind: 'skill',
                  subtitle: 'Review the project',
                  insertText: '$review',
                  scope: 'project',
                  dir: '.agents/skills',
                  description: 'Review the project',
                  author: 'Lody Fixture',
                  version: '1.0',
                  content:
                    '---\nname: review\n---\nInspect the project and report actionable findings.',
                },
              ],
        },
      };
    if (!project.owned || project.removal)
      throw new Error(t('projectManagement.readOnly'));
    if (request.kind === 'preflight') {
      await new Promise((resolve) => setTimeout(resolve, 150));
      if (!project.online)
        throw new Error(t('projectManagement.preflightFailed'));
      return {
        ...result(),
        preflight: { clean: [clean], dirty: [dirty], failed: [failed] },
      };
    }
    if (request.kind === 'share') {
      if (failShare.current) {
        failShare.current = false;
        throw new Error(t('projectManagement.readOnly'));
      }
      project.sharedWithTeam = request.sharedWithTeam;
      return result();
    }
    if (request.kind === 'save-script') {
      if (failSave.current) {
        failSave.current = false;
        throw new Error(t('projectManagement.requestFailed'));
      }
      if (request.phase === 'setup')
        project.worktreeSetup = clone(request.config);
      else project.worktreeCleanup = clone(request.config);
      return result();
    }
    if (request.kind === 'remove') {
      if (failRemove.current) {
        failRemove.current = false;
        throw new Error(t('projectManagement.requestFailed'));
      }
      project.removal = {
        status: 'pending',
        requestedAt: 123456,
        cleanupWorktrees: request.cleanupWorktrees,
      };
      pendingReads.current = 0;
      return result();
    }
    throw new Error(t('projectManagement.requestFailed'));
  }, []);
  return (
    <ProjectManagementFlow
      workspaceId="offline-projects"
      fixture
      service={service}
    />
  );
}
export const ProjectManagementPreviewScreen = definePage({
  id: 'project-management-preview',
  title: t('projectManagement.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
