import { fastModeFor, withFastMode } from '@/cloud/send/capability';
import { useComposerMentions } from '@/hooks/screens/useComposerMentions';
import { ProjectPickerScreen } from './ProjectPickerScreen';
import { useEffect, useRef, useState } from 'react';
import { PlatformColor, TextInput, View as RNView } from 'react-native';
import {
  NativeComposer,
  initialInboxProjectSort,
  type ChatDraftAttachment,
  type NativeListSection,
  sessionCreationOptions,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import type { Project, Session } from '@/models/catalog';
import type { CreationOptions } from '@/models/send';
import { capabilityFor, effortsFor } from '@/cloud/send/capability';
import { usePalette } from '@/lib/theme/palette';
import { type as typeScale } from '@/lib/theme/tokens';
import { ComposerSheet } from '@/ui/ComposerSheet';
import { AppText } from '@/ui/AppText';
import { showToast } from '@/ui/toast';
import { readLocal, writeLocal } from '@/cloud/kv';
import { usePendingSends } from '@/cloud/send/pendingSends';
import { draftTitle } from '@/features/sessions/draftTitle';
import {
  type CreatePrefs,
  CHAT_PREFS_KEY,
  createPrefsKey,
  rememberedContext,
  rememberedProject,
  rememberedModelChoice,
  restoreSelection,
  withSelection,
} from '@/features/sessions/createPrefs';
import {
  isChatProjectId,
  sortCatalogProjects,
} from '@/features/sessions/inbox';
import { PickerScreen } from './PickerScreen';
import {
  hasModelTabs,
  type ModelChoice,
  ModelScreen,
  modelSummary,
} from './ModelScreen';
import type { CreatedSession } from '../models/send.ts';
import { t } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

export type { CreatedSession } from '../models/send.ts';

type Params = {
  workspaceId: string;
  projects: Project[];
  projectId?: string;
  context?: 'project' | 'chat';
  loadOptions?: (projectId?: string) => Promise<CreationOptions>;
};

function pickTitle(loading: boolean, idle: string) {
  return loading ? t('common.reading') : idle;
}

function agentFooter(loading: boolean, hasAgent: boolean) {
  if (loading) return t('create.machineConfig.loading');
  if (hasAgent) return t('create.machineConfig.ready');
  return t('create.machineConfig.retry');
}

function createNotice({
  loading,
  hasAgent,
}: {
  loading: boolean;
  hasAgent: boolean;
}) {
  if (loading) return t('create.composer.loading');
  if (!hasAgent) return t('create.composer.needAgent');
  return '';
}

/** Chat-only rows are not projects and cannot host a project session. */
const creatable = (project: Project) => !isChatProjectId(project.id);

function View() {
  const { params, finish, push, present } = usePageRuntime<
    Params,
    CreatedSession
  >();
  const { account } = useAuth();
  const { catalog } = useCatalog();
  const colors = usePalette();
  const outbox = usePendingSends(account?.user.id ?? '', params.workspaceId);
  const locked = !!params.projectId && params.context !== 'chat';
  const [projects, setProjects] = useState(() =>
    sortCatalogProjects(
      params.projects.filter(creatable),
      catalog.sessions,
      initialInboxProjectSort,
    ),
  );
  const [context, setContext] = useState<'project' | 'chat'>(
    params.context === 'chat' ? 'chat' : 'project',
  );
  const [projectId, setProjectId] = useState(
    params.projectId ?? projects[0]?.id ?? '',
  );
  const [options, setOptions] = useState<CreationOptions>();
  const [machineId, setMachineId] = useState('');
  const [agentKey, setAgentKey] = useState('');
  const [choice, setChoice] = useState<ModelChoice>({});
  const [branch, setBranch] = useState('');
  const [restoreDraftToken, setRestoreDraftToken] = useState(0);
  const prefs = useRef<CreatePrefs | null>(null);
  const [prefsLoaded, setPrefsLoaded] = useState(false);
  const prefsKey = createPrefsKey(account?.user.id ?? '', params.workspaceId);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [revision, setRevision] = useState(0);
  const busy = useRef(false);

  const chat = context === 'chat';
  const project = projects.find((p) => p.id === projectId);
  const githubProject = projectId.startsWith('github:');
  const github = !chat && githubProject;
  const prefsTarget = chat ? CHAT_PREFS_KEY : projectId;

  useEffect(() => {
    let active = true;
    void readLocal<CreatePrefs>(prefsKey).then((saved) => {
      if (!active) return;
      prefs.current = saved;
      if (!locked && !params.context && rememberedContext(saved) === 'chat')
        setContext('chat');
      const remembered = rememberedProject(saved, params.projects);
      if (!params.projectId && remembered) setProjectId(remembered);
      setPrefsLoaded(true);
    });
    return () => {
      active = false;
    };
  }, [prefsKey, params.projectId, params.projects]);

  useEffect(() => {
    if (!prefsLoaded) return;
    if (!chat && !projectId) {
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    setOptions(undefined);
    const request = params.loadOptions
      ? params.loadOptions(chat ? undefined : projectId)
      : sessionCreationOptions(
          JSON.stringify({
            workspaceId: params.workspaceId,
            ...(chat ? {} : { projectId }),
          }),
        ).then((raw): CreationOptions => JSON.parse(raw));
    void request
      .then((value) => {
        if (!active) return;
        setOptions(value);
        const restored = restoreSelection(prefs.current, prefsTarget, value);
        setMachineId(restored.machineId);
        setAgentKey(restored.agentKey);
        const selected = value.agents.find(
          (a) => `${a.machineId}:${a.id}` === restored.agentKey,
        );
        if (selected) updateChoice(restored.choice, selected);
        else setChoice(restored.choice);
      })
      .catch((error: unknown) => {
        if (!active) return;
        showToast(
          __DEV__
            ? t('create.error.machineConfigDetail', { error: String(error) })
            : t('create.error.machineConfig'),
        );
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [params.workspaceId, projectId, chat, prefsTarget, revision, prefsLoaded]);

  // A local project pins its own machine at the projection layer, so only a
  // GitHub project actually has a machine to choose.
  const machines = [
    ...new Map(
      (options?.agents ?? []).map((a) => [
        a.machineId,
        { id: a.machineId, name: a.machineName },
      ]),
    ).values(),
  ];
  const machine = machines.find((m) => m.id === machineId) ?? machines[0];
  const agents = (options?.agents ?? []).filter(
    (a) => a.machineId === machine?.id,
  );
  const agent = agents.find((a) => `${a.machineId}:${a.id}` === agentKey);
  const capability = capabilityFor(options, agent);
  const mentions = useComposerMentions(
    account && machine
      ? {
          workspaceId: params.workspaceId,
          projectId: chat ? undefined : project?.id,
          machineId: machine.id,
        }
      : undefined,
    present,
  );

  function updateChoice(next: ModelChoice, selectedAgent = agent) {
    setChoice(next);
    if (!selectedAgent) return;
    prefs.current = withSelection(
      prefs.current,
      prefsTarget,
      {
        machineId: selectedAgent.machineId,
        agentKey: `${selectedAgent.machineId}:${selectedAgent.id}`,
        ...next,
      },
      context,
    );
    void writeLocal(prefsKey, prefs.current);
  }

  function choiceForModel(modelId?: string) {
    return rememberedModelChoice(prefs.current, agentKey, capability, modelId);
  }

  function submit(
    id: string,
    draft: string,
    startedAt: number,
    attachments: ChatDraftAttachment[],
  ) {
    const ready =
      !!agent &&
      !!options &&
      !!account &&
      (!!draft.trim() || attachments.length > 0);
    if (busy.current || !ready) {
      setRestoreDraftToken((n) => n + 1);
      return;
    }
    if (github && !branch.trim()) {
      setRestoreDraftToken((n) => n + 1);
      showToast(t('create.toast.branchRequired'));
      return;
    }
    updateChoice(choice);
    busy.current = true;
    setSending(true);
    const session: Session = {
      id: options!.sessionId,
      projectId: chat ? `${agent!.machineId}:unassigned` : projectId,
      machineId: agent!.machineId,
      cliType: agent!.cliType,
      agentType: agent!.agentType,
      title: draftTitle(draft),
      status: 'idle',
      archived: false,
      pinned: false,
      createdAt: new Date().toISOString(),
    };
    const send = {
      id,
      text: draft,
      startedAt,
      attachments,
      phase: 'waiting' as const,
      choice: {
        ...choice,
        reasoningEffortConfigId: capability?.reasoningEffortConfigId,
      },
      creation: JSON.stringify({
        workspaceId: params.workspaceId,
        sessionId: session.id,
        machineId: session.machineId,
        agentConfigId: agent!.id,
        userId: account!.user.id,
        title: session.title,
        ...(chat ? {} : { projectId }),
        ...(github ? { branch: branch.trim() } : {}),
      }),
    };
    // Publish locally before closing the sheet. Persistence gates dispatch, never navigation.
    void outbox.put({ session, send }).catch(() => {
      void outbox
        .put({
          session,
          send: {
            ...send,
            phase: 'failed',
            reason: t('send.error.draftSaveShort'),
          },
        })
        .catch(() => {});
    });
    finish({
      session,
      projectName: chat
        ? t('inbox.section.chat')
        : (project?.name ?? options?.project?.name ?? ''),
      machineName: agent!.machineName,
      ...choice,
    });
  }

  const machineRow = {
    id: 'machine',
    title: machine?.name ?? pickTitle(loading, t('create.row.selectMachine')),
    subtitle: t('create.label.machine'),
    image: 'desktopcomputer',
    action: true,
    disclosure: true,
    navigates: true,
  };
  const modelRow = {
    id: 'model',
    title: capability ? modelSummary(capability, choice) : t('model.default'),
    subtitle: t('create.label.model'),
    image: 'cpu',
    action: !!capability,
    disclosure: !!capability,
    navigates: !!capability,
  };

  function agentSection(subtitle?: string): NativeListSection {
    return {
      id: 'agent',
      footer: agentFooter(loading, !!agent),
      rows: [
        {
          id: 'agent',
          title: agent?.name ?? pickTitle(loading, t('create.row.selectAgent')),
          subtitle,
          image: 'sparkles',
          action: true,
          disclosure: true,
          navigates: true,
        },
        modelRow,
      ],
    };
  }

  const projectSections: NativeListSection[] = [
    {
      id: 'project',
      rows: [
        {
          id: 'project',
          title: project?.name ?? t('create.row.selectProject'),
          subtitle: t('create.label.project'),
          image: 'folder',
          action: true,
          disclosure: true,
          navigates: true,
        },
      ],
    },
    ...(githubProject ? [{ id: 'machine', rows: [machineRow] }] : []),
    agentSection(githubProject ? t('create.label.agent') : machine?.name),
  ];
  const chatSections: NativeListSection[] = [
    { id: 'machine', rows: [machineRow] },
    agentSection(t('create.label.agent')),
  ];
  const pages = locked
    ? undefined
    : [
        {
          id: 'project',
          title: t('create.type.project'),
          sections: projectSections,
        },
        {
          id: 'chat',
          title: t('create.type.chat'),
          sections: chatSections,
        },
      ];
  const sections = chat ? chatSections : projectSections;

  async function pickProject() {
    const result = await push(ProjectPickerScreen, {
      workspaceId: params.workspaceId,
      projects: sortCatalogProjects(
        projects,
        catalog.sessions,
        initialInboxProjectSort,
      ),
      selectedId: projectId,
    });
    if (result.status !== 'completed') return;
    const picked = result.value;
    setProjects((current) => [
      ...current.filter((p) => p.id !== picked.id),
      picked,
    ]);
    setProjectId(picked.id);
    setChoice({});
  }

  async function pickMachine() {
    if (!options) {
      setRevision((n) => n + 1);
      return;
    }
    const result = await push(
      PickerScreen,
      {
        title: t('create.row.selectMachine'),
        header: t('create.label.machine'),
        selectedId: machine?.id,
        placeholder: t('create.picker.machine.placeholder'),
        options: machines.map((m) => ({ id: m.id, title: m.name })),
      },
      { title: t('create.row.selectMachine') },
    );
    if (result.status !== 'completed') return;
    setMachineId(result.value);
    const first = options.agents.find((a) => a.machineId === result.value);
    setAgentKey(first ? `${first.machineId}:${first.id}` : '');
    updateChoice(
      rememberedModelChoice(
        prefs.current,
        first ? `${first.machineId}:${first.id}` : '',
        capabilityFor(options, first),
      ),
      first,
    );
  }

  async function pickModel() {
    if (!capability) return;
    await push(
      ModelScreen,
      { capability, value: choice, onChange: updateChoice, choiceForModel },
      // A single tab needs no segmented control, so the title names it instead.
      {
        title: hasModelTabs(capability)
          ? (agent?.name ?? t('model.title'))
          : t('create.row.selectModel'),
      },
    );
  }

  async function pickAgent() {
    if (!options) {
      setRevision((n) => n + 1);
      return;
    }
    const result = await push(
      PickerScreen,
      {
        title: t('create.row.selectAgent'),
        header: t('create.label.agent'),
        selectedId: agentKey,
        placeholder: t('create.picker.agent.placeholder'),
        options: agents.map((a) => ({
          id: `${a.machineId}:${a.id}`,
          title: a.name,
          subtitle: a.machineName,
        })),
      },
      { title: t('create.row.selectAgent') },
    );
    if (result.status !== 'completed') return;
    setAgentKey(result.value);
    const selected = options.agents.find(
      (a) => `${a.machineId}:${a.id}` === result.value,
    );
    updateChoice(
      rememberedModelChoice(
        prefs.current,
        result.value,
        capabilityFor(options, selected),
      ),
      selected,
    );
  }

  const form = (
    <ComposerSheet
      accent={colors.accent}
      sections={sections}
      pages={pages}
      selectedPage={chat ? 1 : 0}
      placeholder=""
      onPageChange={({ nativeEvent }) => {
        if (sending) return;
        if (nativeEvent.index === 1) setContext('chat');
        else setContext('project');
      }}
      onRowPress={({ nativeEvent }) => {
        if (sending) return;
        if (nativeEvent.id === 'project') void pickProject();
        if (nativeEvent.id === 'machine') void pickMachine();
        if (nativeEvent.id === 'model') void pickModel();
        if (nativeEvent.id === 'agent') void pickAgent();
      }}
    >
      {github ? (
        <RNView style={{ paddingHorizontal: 16, paddingBottom: 12, gap: 4 }}>
          <AppText variant="meta">{t('create.branch.label')}</AppText>
          <TextInput
            accessibilityLabel={t('create.branch.label')}
            placeholder={t('create.branch.placeholder')}
            placeholderTextColor={colors.tertiaryLabel}
            value={branch}
            onChangeText={setBranch}
            maxLength={255}
            autoCapitalize="none"
            autoCorrect={false}
            editable={!sending}
            style={{
              color: colors.label,
              backgroundColor: PlatformColor('tertiarySystemGroupedBackground'),
              borderRadius: 10,
              borderCurve: 'continuous',
              paddingHorizontal: 14,
              minHeight: 44,
              fontFamily: 'Menlo',
              fontSize: typeScale.mono.size,
            }}
          />
        </RNView>
      ) : null}
      <NativeComposer
        mentionItemsJSON={mentions.mentionItemsJSON}
        mentionResultJSON={mentions.mentionResultJSON}
        onMentionBrowse={mentions.onMentionBrowse}
        scrollEdge
        composerJSON={JSON.stringify({
          editable: true,
          canSend: !!agent && !!account && !loading,
          sending,
          notice: createNotice({ loading, hasAgent: !!agent }),
          reconnect: false,
          placeholder: t('create.composer.placeholder'),
        })}
        composerOptionsJSON={JSON.stringify({
          fast: fastModeFor(capability, choice)?.enabled,
          modelId: choice.modelId ?? '',
          effort: choice.effort ?? '',
          models: (capability?.models ?? []).map((item) => ({
            id: item.id,
            title: item.name,
          })),
          efforts: effortsFor(capability, choice.modelId).map((id) => ({
            id,
            title: id,
          })),
        })}
        restoreDraftToken={restoreDraftToken}
        onSend={({ nativeEvent }) =>
          submit(
            nativeEvent.id,
            nativeEvent.text,
            nativeEvent.startedAt,
            nativeEvent.attachments,
          )
        }
        onComposerOptionChange={({ nativeEvent }) => {
          if (typeof nativeEvent.fast === 'boolean') {
            updateChoice(withFastMode(capability, choice, nativeEvent.fast));
            return;
          }
          const modelId = nativeEvent.modelId || undefined;
          if (modelId !== choice.modelId) updateChoice(choiceForModel(modelId));
          else
            updateChoice({
              ...choice,
              effort: nativeEvent.effort || undefined,
            });
        }}
      />
    </ComposerSheet>
  );

  return form;
}

export const CreateSessionScreen = definePage<Params, CreatedSession>({
  id: 'create-session',
  title: t('create.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from the session list');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.62, 1],
    sheetGrabberVisible: true,
  },
});
