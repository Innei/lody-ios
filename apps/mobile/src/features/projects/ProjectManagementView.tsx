import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  type NativeListSection,
} from '@lody-ios/kit';
import type {
  ManagedProject,
  ProjectManagementResult,
} from '@lody/cloud-runtime/models/project-management';
import type { ProjectManagementService } from '@/cloud/project-management';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';

const removalHint = {
  completed: 'projectManagement.completedHint',
  pending: 'projectManagement.pendingHint',
  unknown: 'projectManagement.writeUnknown',
} as const;

export function ProjectManagementView({
  service,
  projectId,
  onOpenProject,
  onEditScript,
  onOpenSkills,
  onRemove,
  onAdd,
  onHistory,
}: {
  service: ProjectManagementService;
  projectId?: string;
  onOpenProject: (project: ManagedProject) => Promise<void>;
  onEditScript: (
    project: ManagedProject,
    phase: 'setup' | 'cleanup',
  ) => Promise<void>;
  onOpenSkills: (project: ManagedProject) => Promise<void>;
  onRemove: (project: ManagedProject) => Promise<void>;
  onAdd?: () => Promise<void>;
  onHistory?: () => Promise<void>;
}) {
  const colors = usePalette();
  const [result, setResult] = useState<ProjectManagementResult>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const locked = useRef(false),
    active = useRef(true);
  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
    };
  }, []);
  const load = useCallback(async () => {
    if (locked.current) return;
    locked.current = true;
    setBusy(true);
    setError('');
    try {
      const next = await service(
        projectId ? { kind: 'detail', projectId } : { kind: 'list' },
      );
      if (active.current) setResult(next);
    } catch (cause) {
      if (active.current)
        setError(
          cause instanceof Error
            ? cause.message
            : t('projectManagement.requestFailed'),
        );
    } finally {
      locked.current = false;
      if (active.current) setBusy(false);
    }
  }, [service, projectId]);
  useEffect(() => {
    void load();
  }, [load]);
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('projectManagement.refresh'),
        accessibilityLabel: t('projectManagement.refresh'),
        identifier: 'project-management-refresh',
        icon: { type: 'sfSymbol' as const, name: 'arrow.clockwise' },
        disabled: busy,
        onPress: () => void load(),
      },
    ],
    [busy, load],
  );
  const project = result?.projects.find((item) => item.id === projectId);
  const sections: NativeListSection[] = [];
  if (busy || error || result?.cloudUnavailable)
    sections.push({
      id: 'project-management-state',
      footer:
        error ||
        (busy ? t('common.loading') : t('projectManagement.cloudUnavailable')),
      rows: [],
    });
  if (!projectId) {
    if (onAdd || onHistory)
      sections.push({
        id: 'project-management-existing',
        rows: [
          ...(onAdd
            ? [
                {
                  id: 'project-management-add',
                  title: t('projectManagement.add'),
                  image: 'folder.badge.plus',
                  imageTint: 'blue',
                  action: !busy,
                },
              ]
            : []),
          ...(onHistory
            ? [
                {
                  id: 'project-management-history',
                  title: t('settings.history.title'),
                  image: 'clock.arrow.circlepath',
                  imageTint: 'blue',
                  action: !busy,
                  disclosure: true,
                  navigates: true,
                },
              ]
            : []),
        ],
      });
    const groups = new Map<string, ManagedProject[]>();
    for (const item of result?.projects ?? []) {
      const key = item.source === 'github' ? 'github' : item.machineId;
      const rows = groups.get(key) ?? [];
      rows.push(item);
      groups.set(key, rows);
    }
    for (const [id, projects] of groups)
      sections.push({
        id,
        header:
          id === 'github'
            ? t('projectManagement.github')
            : projects[0].machineName,
        rows: projects.map((item) => ({
          id: `managed-project:${item.id}`,
          title: item.name,
          subtitle: item.rootPath || item.repoFullName,
          subtitleMono: true,
          value: item.removal
            ? t(`projectManagement.removal.${item.removal.status}`)
            : undefined,
          image: item.source === 'github' ? 'network' : 'folder',
          imageTint: 'blue',
          action: !busy,
          disclosure: true,
          navigates: true,
        })),
      });
    if (
      !busy &&
      !error &&
      !result?.cloudUnavailable &&
      !result?.projects.length
    )
      sections.push({
        id: 'project-management-empty',
        footer: t('projectManagement.empty'),
        rows: [],
      });
  } else if (project) {
    const editable = project.owned && !project.removal && !busy;
    let permissionHint;
    if (!project.owned)
      permissionHint = t(
        project.source === 'github'
          ? 'projectManagement.unavailable'
          : 'projectManagement.readOnly',
      );
    let connection = t('projectManagement.connectionUnknown');
    if (project.online === true) connection = t('projectManagement.online');
    if (project.online === false) connection = t('projectManagement.offline');
    sections.push({
      id: 'project-management-info',
      header: project.name,
      footer: permissionHint,
      rows: [
        {
          id: 'project-source',
          title: t('projectManagement.source'),
          value:
            project.source === 'github'
              ? t('projectManagement.github')
              : project.machineName,
        },
        {
          id: 'project-path',
          title:
            project.source === 'github'
              ? t('projectManagement.repository')
              : t('projectManagement.originalDirectory'),
          subtitle: project.rootPath || project.repoFullName,
          subtitleMono: true,
        },
        {
          id: 'project-conversations',
          title: t('projectManagement.conversations'),
          value: String(project.conversationCount),
        },
        ...(project.source === 'local'
          ? [
              {
                id: 'project-connection',
                title: t('projectManagement.connection'),
                value: connection,
              },
            ]
          : []),
      ],
    });
    if (project.source === 'local')
      sections.push({
        id: 'project-management-visibility',
        header: t('projectManagement.visibility'),
        footer: t('projectManagement.visibilityHint'),
        rows: [
          {
            id: 'project-shared',
            title: t('projectManagement.shared'),
            toggle: project.sharedWithTeam === true,
            action: editable && project.canShare,
            value:
              project.sharedWithTeam === undefined
                ? t('projectManagement.connectionUnknown')
                : undefined,
          },
        ],
      });
    if (!project.removal)
      sections.push({
        id: 'project-management-scripts',
        header: t('projectManagement.worktree'),
        footer: t('projectManagement.scriptsHint'),
        rows: [
          {
            id: 'project-setup',
            title: t('projectManagement.setup'),
            subtitle: project.scriptErrors?.setup
              ? t('projectManagement.scriptUnavailable')
              : undefined,
            action: editable && !!project.worktreeSetup,
            disclosure: true,
            navigates: true,
          },
          {
            id: 'project-cleanup',
            title: t('projectManagement.cleanup'),
            subtitle: project.scriptErrors?.cleanup
              ? t('projectManagement.scriptUnavailable')
              : undefined,
            action: editable && !!project.worktreeCleanup,
            disclosure: true,
            navigates: true,
          },
          {
            id: 'project-skills',
            title: t('projectManagement.skills'),
            image: 'sparkles',
            imageTint: 'blue',
            action: !busy,
            disclosure: true,
            navigates: true,
          },
        ],
      });
    if (project.removal) {
      sections.push({
        id: 'project-management-removal',
        header: t(`projectManagement.removal.${project.removal.status}`),
        footer: t(removalHint[project.removal.status]),
        rows: [],
      });
      const cleanup = project.removal.cleanupResult;
      if (cleanup) {
        for (const kind of ['deleted', 'skippedDirty', 'failed'] as const) {
          const rows = cleanup[kind];
          sections.push({
            id: `project-cleanup-${kind}`,
            header: t(`projectManagement.cleanupResult.${kind}`),
            footer: rows.length ? undefined : t('projectManagement.none'),
            rows: rows.map((row) => ({
              id: `project-cleanup:${kind}:${row.sessionId}`,
              title: row.title,
              subtitle: `${row.path}${'message' in row ? `\n${row.message}` : ''}`,
              wrapSubtitle: true,
              subtitleMono: true,
            })),
          });
        }
      }
    } else if (project.source === 'local')
      sections.push({
        id: 'project-management-remove',
        footer: t('projectManagement.originalDirectorySafe'),
        rows: [
          {
            id: 'project-remove',
            title: t('projectManagement.remove'),
            image: 'trash',
            destructive: true,
            action: editable,
          },
        ],
      });
  } else if (!busy && !error)
    sections.push({
      id: 'project-management-unavailable',
      footer: t('projectManagement.unavailable'),
      rows: [],
    });
  const navigate = async (action: () => Promise<void>) => {
    if (locked.current) return;
    await action();
    if (active.current) await load();
  };
  return (
    <>
      <NativeNavigationHeader
        title={project?.name ?? t('projectManagement.title')}
        items={actions}
      />
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        sections={sections}
        refreshing={busy}
        onRefresh={() => void load()}
        onRowToggle={({ nativeEvent: { id, value } }) => {
          if (id !== 'project-shared' || !project || locked.current) return;
          locked.current = true;
          setBusy(true);
          setError('');
          void service({
            kind: 'share',
            projectId: project.id,
            sharedWithTeam: value,
          })
            .then(async () => {
              locked.current = false;
              if (active.current) await load();
            })
            .catch((cause) => {
              if (active.current)
                setError(
                  cause instanceof Error
                    ? cause.message
                    : t('projectManagement.requestFailed'),
                );
            })
            .finally(() => {
              locked.current = false;
              if (active.current) setBusy(false);
            });
        }}
        onRowPress={({ nativeEvent: { id } }) => {
          if (busy || locked.current) return;
          if (id === 'project-management-add' && onAdd) {
            void navigate(onAdd);
            return;
          }
          if (id === 'project-management-history' && onHistory) {
            void navigate(onHistory);
            return;
          }
          const next = result?.projects.find(
            (item) => id === `managed-project:${item.id}`,
          );
          if (next) {
            void navigate(() => onOpenProject(next));
            return;
          }
          if (!project) return;
          if (id === 'project-skills')
            void navigate(() => onOpenSkills(project));
          if (!project.owned || project.removal) return;
          if (id === 'project-setup' && project.worktreeSetup)
            void navigate(() => onEditScript(project, 'setup'));
          if (id === 'project-cleanup' && project.worktreeCleanup)
            void navigate(() => onEditScript(project, 'cleanup'));
          if (id === 'project-remove') void navigate(() => onRemove(project));
        }}
      />
    </>
  );
}
