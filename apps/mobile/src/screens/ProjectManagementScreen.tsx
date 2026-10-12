import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, StyleSheet, TextInput } from 'react-native';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  uuid,
  type NativeListSection,
} from '@lody-ios/kit';
import type {
  ManagedProject,
  WorktreePreflight,
  WorktreeScriptConfig,
} from '@lody/cloud-runtime/models/project-management';
import type {
  MentionCatalog,
  MentionItem,
} from '@lody/cloud-runtime/models/mentions';
import type { ProjectManagementService } from '@/cloud/project-management';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { ProjectManagementView } from '@/features/projects/ProjectManagementView';
import { useProjectManagementService } from '@/features/projects/useProjectManagementService';
import { sessionStatus } from '@/features/sessions/status';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { Screen } from '@/ui/Screen';
import { AppText } from '@/ui/AppText';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import { DirectoryScreen } from './DirectoryScreen';
import { ProjectHistoryScreen } from './ProjectHistoryScreen';

export type ProjectManagementParams = {
  workspaceId: string;
  projectId?: string;
  accountId?: string;
  service?: ProjectManagementService;
  fixture?: boolean;
};
type ProjectParams = ProjectManagementParams & { project: ManagedProject };
type ScriptParams = ProjectParams & { phase: 'setup' | 'cleanup' };

function useValidWorkspace(params: ProjectManagementParams) {
  const { selected } = useCatalog();
  const { account } = useAuth();
  const { cancel } = usePageRuntime();
  const valid =
    params.fixture === true ||
    (selected?.id === params.workspaceId &&
      (!params.accountId || params.accountId === account?.user.id));
  useEffect(() => {
    if (!valid) cancel();
  }, [valid, cancel]);
  return valid;
}

export function ProjectManagementFlow(params: ProjectManagementParams) {
  const { push, present } = usePageRuntime();
  const service = useProjectManagementService(
    params.workspaceId,
    params.service,
  );
  const forwarded = { ...params, service };
  return (
    <ProjectManagementView
      service={service}
      projectId={params.projectId}
      onOpenProject={async (project) => {
        await push(
          ProjectManagementDetailScreen,
          { ...forwarded, projectId: project.id },
          { title: project.name },
        );
      }}
      onEditScript={async (project, phase) => {
        await push(
          ProjectScriptEditorScreen,
          { ...forwarded, project, phase },
          { title: t(`projectManagement.${phase}`) },
        );
      }}
      onOpenSkills={async (project) => {
        await push(
          ProjectSkillsScreen,
          { ...forwarded, project },
          { title: t('projectManagement.skills') },
        );
      }}
      onRemove={async (project) => {
        await present(ProjectRemovalScreen, { ...forwarded, project });
      }}
      onAdd={
        params.fixture
          ? undefined
          : async () => {
              await present(DirectoryScreen, {
                workspaceId: params.workspaceId,
                browserId: uuid.v4(),
              });
            }
      }
      onHistory={
        params.fixture
          ? undefined
          : async () => {
              await push(ProjectHistoryScreen);
            }
      }
    />
  );
}

export const ProjectManagementDetailScreen =
  definePage<ProjectManagementParams>({
    id: 'project-management-detail',
    title: t('projectManagement.title'),
    Component: () => {
      const { params } = usePageRuntime<ProjectManagementParams>();
      const valid = useValidWorkspace(params);
      if (!valid) return null;
      return (
        <ProjectManagementFlow
          key={`${params.accountId}:${params.workspaceId}:${params.projectId}`}
          {...params}
        />
      );
    },
    parseRouteParams: () => {
      throw new Error('Open from project management');
    },
    presentation: { style: 'push', headerVariant: 'transparent' },
  });
export const ProjectManagementScreen = definePage({
  id: 'project-management',
  title: t('projectManagement.title'),
  Component: () => {
    const { selected } = useCatalog();
    const { account } = useAuth();
    const { cancel } = usePageRuntime();
    useEffect(() => {
      if (!selected) cancel();
    }, [selected, cancel]);
    if (!selected) return null;
    return (
      <ProjectManagementFlow
        key={`${account?.user.id}:${selected.id}`}
        workspaceId={selected.id}
        accountId={account?.user.id}
      />
    );
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});

function ScriptEditor() {
  const { params, finish, cancel } = usePageRuntime<ScriptParams>();
  const valid = useValidWorkspace(params);
  const service = useProjectManagementService(
    params.workspaceId,
    params.service,
  );
  const initial = (params.phase === 'setup'
    ? params.project.worktreeSetup
    : params.project.worktreeCleanup) ?? { scripts: {} };
  const [scripts, setScripts] = useState<WorktreeScriptConfig['scripts']>(
    initial.scripts,
  );
  const [timeout, setTimeoutValue] = useState(
    initial.timeoutMs?.toString() ?? '',
  );
  const [busy, setBusy] = useState(false),
    [error, setError] = useState('');
  const locked = useRef(false),
    active = useRef(true);
  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
    };
  }, []);
  const colors = usePalette();
  const timeoutValid =
    !timeout ||
    (/^\d+$/.test(timeout) &&
      Number.isSafeInteger(Number(timeout)) &&
      Number(timeout) > 0);
  const canSave =
    valid && params.project.owned && !params.project.removal && timeoutValid;
  const save = useCallback(async () => {
    if (locked.current || !canSave) return;
    locked.current = true;
    setBusy(true);
    setError('');
    try {
      await service({
        kind: 'save-script',
        projectId: params.project.id,
        phase: params.phase,
        config: { scripts, ...(timeout ? { timeoutMs: Number(timeout) } : {}) },
      });
      if (active.current) finish();
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
  }, [
    canSave,
    service,
    params.project.id,
    params.phase,
    scripts,
    timeout,
    finish,
  ]);
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('projectManagement.save'),
        accessibilityLabel: t('projectManagement.save'),
        identifier: 'project-script-save',
        variant: 'prominent' as const,
        tintColor: colors.accent,
        disabled: busy || !canSave,
        onPress: () => void save(),
      },
    ],
    [busy, canSave, save, colors.accent],
  );
  const left = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.cancel'),
        identifier: 'project-script-cancel',
        disabled: busy,
        onPress: cancel,
      },
    ],
    [busy, cancel],
  );
  if (!valid) return null;
  const shells: ('bash' | 'powershell')[] =
    params.project.source === 'github'
      ? ['bash', 'powershell']
      : [params.project.shell ?? 'bash'];
  return (
    <>
      <NativeNavigationHeader
        title={t(`projectManagement.${params.phase}`)}
        items={actions}
        leftItems={left}
      />
      <Screen automaticallyAdjustKeyboardInsets>
        {error ? <AppText accessibilityRole="alert">{error}</AppText> : null}
        {shells.map((shell) => (
          <FormGroup
            key={shell}
            header={shell === 'bash' ? 'Bash' : 'PowerShell'}
            footer={t('projectManagement.scriptsHint')}
          >
            <TextInput
              testID={`project-script-${shell}`}
              accessibilityLabel={t('projectManagement.scriptLabel', { shell })}
              style={[formInputStyle, styles.script, { color: colors.label }]}
              multiline
              scrollEnabled={false}
              value={scripts[shell] ?? ''}
              onChangeText={(value) =>
                setScripts((current) => ({ ...current, [shell]: value }))
              }
              editable={!busy && params.project.owned}
              maxLength={65536}
              autoCapitalize="none"
              autoCorrect={false}
            />
          </FormGroup>
        ))}
        <FormGroup
          header={t('projectManagement.timeout')}
          footer={
            timeoutValid
              ? t('projectManagement.timeoutHint')
              : t('projectManagement.invalidTimeout')
          }
        >
          <TextInput
            testID="project-script-timeout"
            accessibilityLabel={t('projectManagement.timeout')}
            value={timeout}
            onChangeText={setTimeoutValue}
            keyboardType="number-pad"
            placeholder="600000"
            maxLength={16}
            style={[formInputStyle, { color: colors.label }]}
            editable={!busy && params.project.owned}
          />
        </FormGroup>
      </Screen>
    </>
  );
}
const ProjectScriptEditorScreen = definePage<ScriptParams>({
  id: 'project-script-editor',
  title: t('projectManagement.worktree'),
  Component: ScriptEditor,
  parseRouteParams: () => {
    throw new Error('Open from project management');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});

function Removal() {
  const { params, finish, cancel } = usePageRuntime<ProjectParams>();
  const valid = useValidWorkspace(params);
  const service = useProjectManagementService(
    params.workspaceId,
    params.service,
  );
  const [preflight, setPreflight] = useState<WorktreePreflight>();
  const [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(false);
  const [cleanup, setCleanup] = useState(false),
    [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const locked = useRef(false),
    active = useRef(true);
  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
    };
  }, []);
  useEffect(() => {
    let live = true;
    setLoading(true);
    setPreflight(undefined);
    setCleanup(false);
    setError('');
    void service({ kind: 'preflight', projectId: params.project.id })
      .then((result) => {
        if (!result.preflight)
          throw new Error(t('projectManagement.preflightFailed'));
        if (live) setPreflight(result.preflight);
      })
      .catch(() => {
        if (live) setError(t('projectManagement.preflightFailed'));
      })
      .finally(() => {
        if (live) setLoading(false);
      });
    return () => {
      live = false;
    };
  }, [service, params.project.id, revision]);
  const colors = usePalette();
  const remove = useCallback(async () => {
    if (locked.current || loading || !valid || !params.project.owned) return;
    locked.current = true;
    setBusy(true);
    setError('');
    try {
      await service({
        kind: 'remove',
        projectId: params.project.id,
        cleanupWorktrees: cleanup && !!preflight,
      });
      if (active.current) finish();
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
  }, [loading, valid, params.project, service, cleanup, preflight, finish]);
  const confirm = useCallback(
    () =>
      Alert.alert(
        t('projectManagement.confirmTitle'),
        t('projectManagement.confirmMessage', { name: params.project.name }),
        [
          { text: t('common.cancel'), style: 'cancel' },
          {
            text: t('projectManagement.remove'),
            style: 'destructive',
            onPress: () => void remove(),
          },
        ],
      ),
    [params.project.name, remove],
  );
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('projectManagement.remove'),
        accessibilityLabel: t('projectManagement.remove'),
        identifier: 'project-removal-submit',
        tintColor: '#FF3B30',
        disabled: busy || loading || !params.project.owned,
        onPress: confirm,
      },
    ],
    [busy, loading, params.project.owned, confirm],
  );
  const left = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.cancel'),
        identifier: 'project-removal-cancel',
        disabled: busy,
        onPress: cancel,
      },
    ],
    [busy, cancel],
  );
  if (!valid) return null;
  const sections: NativeListSection[] = [
    {
      id: 'project-removal-impact',
      header: params.project.name,
      footer: t('projectManagement.originalDirectorySafe'),
      rows: [
        {
          id: 'project-removal-conversations',
          title: t('projectManagement.conversations'),
          value: String(params.project.conversationCount),
        },
        {
          id: 'project-removal-running',
          title: t('projectManagement.running'),
          value: String(params.project.runningSessionCount),
        },
        {
          id: 'project-removal-original',
          title: t('projectManagement.originalDirectory'),
          subtitle: params.project.rootPath,
          subtitleMono: true,
        },
      ],
    },
    {
      id: 'project-removal-option',
      header: t('projectManagement.worktree'),
      footer: t('projectManagement.cleanupHint'),
      rows: [
        {
          id: 'project-removal-cleanup',
          title: t('projectManagement.cleanupWorktrees'),
          toggle: cleanup,
          action: !!preflight && !busy && !loading,
        },
      ],
    },
  ];
  if (params.project.affectedSessions?.length)
    sections.splice(1, 0, {
      id: 'project-removal-sessions',
      header: t('projectManagement.conversations'),
      rows: params.project.affectedSessions.map((session) => ({
        id: `project-affected:${session.id}`,
        title: session.title,
        value: sessionStatus(session.status),
        image: 'bubble.left',
        imageTint: 'blue',
      })),
    });
  if (loading || error || busy)
    sections.push({
      id: 'project-removal-state',
      footer:
        error ||
        (busy
          ? t('projectManagement.removalSending')
          : t('projectManagement.checking')),
      rows: [],
    });
  if (preflight)
    for (const kind of ['clean', 'dirty', 'failed'] as const) {
      const rows = preflight[kind];
      sections.push({
        id: `project-preflight-${kind}`,
        header: t(`projectManagement.preflight.${kind}`),
        footer: rows.length ? undefined : t('projectManagement.none'),
        rows: rows.map((row) => ({
          id: `project-preflight:${kind}:${row.sessionId}`,
          title: row.title,
          subtitle: `${row.path}${'message' in row ? `\n${row.message}` : ''}`,
          subtitleMono: true,
          wrapSubtitle: true,
        })),
      });
    }
  if (!loading && !busy && !preflight)
    sections.push({
      id: 'project-preflight-retry',
      rows: [
        {
          id: 'project-preflight-retry',
          title: t('projectManagement.refresh'),
          image: 'arrow.clockwise',
          imageTint: 'blue',
          action: true,
        },
      ],
    });
  return (
    <>
      <NativeNavigationHeader
        title={t('projectManagement.remove')}
        items={actions}
        leftItems={left}
      />
      <NativeGroupedList
        style={{ flex: 1 }}
        sections={sections}
        accent={colors.accent}
        onRowPress={({ nativeEvent: { id } }) => {
          if (id === 'project-preflight-retry')
            setRevision((value) => value + 1);
        }}
        onRowToggle={({ nativeEvent: { id, value } }) => {
          if (id === 'project-removal-cleanup' && preflight && !busy)
            setCleanup(value);
        }}
      />
    </>
  );
}
const ProjectRemovalScreen = definePage<ProjectParams>({
  id: 'project-removal',
  title: t('projectManagement.remove'),
  Component: Removal,
  parseRouteParams: () => {
    throw new Error('Open from project management');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});

function Skills() {
  const { params, push } = usePageRuntime<ProjectParams>();
  const valid = useValidWorkspace(params);
  const service = useProjectManagementService(
    params.workspaceId,
    params.service,
  );
  const [skills, setSkills] = useState<MentionCatalog>(),
    [busy, setBusy] = useState(true),
    [error, setError] = useState('');
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
      const result = await service({
        kind: 'skills',
        projectId: params.project.id,
      });
      if (!result.skills) throw new Error(t('projectManagement.requestFailed'));
      if (active.current) setSkills(result.skills);
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
  }, [service, params.project.id]);
  useEffect(() => {
    void load();
  }, [load]);
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('projectManagement.refresh'),
        identifier: 'project-skills-refresh',
        accessibilityLabel: t('projectManagement.refresh'),
        disabled: busy,
        onPress: () => void load(),
      },
    ],
    [busy, load],
  );
  if (!valid) return null;
  const sections: NativeListSection[] = [];
  if (busy || error || skills?.incomplete || skills?.truncated)
    sections.push({
      id: 'project-skills-state',
      footer:
        error ||
        (busy ? t('common.loading') : t('projectManagement.skillsIncomplete')),
      rows: [],
    });
  const groups = new Map<string, MentionItem[]>();
  for (const skill of skills?.items ?? []) {
    const key = `${skill.scope ?? 'project'}:${skill.dir ?? ''}`;
    const values = groups.get(key) ?? [];
    values.push(skill);
    groups.set(key, values);
  }
  for (const [id, items] of groups)
    sections.push({
      id,
      header: t(`projectManagement.skillScope.${items[0].scope ?? 'project'}`),
      footer: items[0].dir,
      rows: items.map((item) => ({
        id: `project-skill:${item.path}`,
        title: item.name,
        subtitle: item.description || item.subtitle,
        action: !busy,
        disclosure: true,
        navigates: true,
        image: 'sparkles',
        imageTint: 'blue',
      })),
    });
  if (
    !busy &&
    !error &&
    !skills?.incomplete &&
    !skills?.truncated &&
    !skills?.items.length
  )
    sections.push({
      id: 'project-skills-empty',
      footer: t('projectManagement.skillsEmpty'),
      rows: [],
    });
  return (
    <>
      <NativeNavigationHeader
        title={t('projectManagement.skills')}
        items={actions}
      />
      <NativeGroupedList
        style={{ flex: 1 }}
        sections={sections}
        refreshing={busy}
        onRefresh={() => void load()}
        onRowPress={({ nativeEvent: { id } }) => {
          const skill = skills?.items.find(
            (item) => id === `project-skill:${item.path}`,
          );
          if (skill && !busy)
            void push(
              ProjectSkillDetailScreen,
              { ...params, skill },
              { title: skill.name },
            );
        }}
      />
    </>
  );
}
const ProjectSkillsScreen = definePage<ProjectParams>({
  id: 'project-skills',
  title: t('projectManagement.skills'),
  Component: Skills,
  parseRouteParams: () => {
    throw new Error('Open from project management');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
const ProjectSkillDetailScreen = definePage<
  ProjectParams & { skill: MentionItem }
>({
  id: 'project-skill-detail',
  title: t('projectManagement.skills'),
  Component: () => {
    const { params } = usePageRuntime<ProjectParams & { skill: MentionItem }>();
    const valid = useValidWorkspace(params);
    if (!valid) return null;
    const { skill } = params;
    return (
      <>
        <NativeNavigationHeader title={skill.name} />
        <Screen>
          <AppText variant="title">{skill.name}</AppText>
          {skill.description ? <AppText>{skill.description}</AppText> : null}
          <FormGroup header={t('projectManagement.source')}>
            <AppText style={styles.details} selectable>
              {t(`projectManagement.skillScope.${skill.scope ?? 'project'}`)}
              {'\n'}
              {skill.dir}
              {'\n'}
              {skill.path}
            </AppText>
          </FormGroup>
          {skill.author ? (
            <AppText>
              {t('projectManagement.author', { author: skill.author })}
            </AppText>
          ) : null}
          {skill.version ? (
            <AppText>
              {t('projectManagement.version', { version: skill.version })}
            </AppText>
          ) : null}
          <FormGroup header="SKILL.md">
            <AppText
              testID="project-skill-content"
              selectable
              style={styles.details}
            >
              {skill.content ?? t('projectManagement.skillContentUnavailable')}
            </AppText>
          </FormGroup>
        </Screen>
      </>
    );
  },
  parseRouteParams: () => {
    throw new Error('Open from project skills');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});

const styles = StyleSheet.create({
  script: {
    minHeight: 176,
    paddingTop: 12,
    textAlignVertical: 'top',
    fontFamily: 'Menlo',
  },
  details: { padding: 16 },
});
