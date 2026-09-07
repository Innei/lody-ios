import { projectPickerPage } from './ProjectPickerScreen';
import { useEffect, useRef, useState } from 'react';
import { TextInput, View } from 'react-native';
import {
  NativeGroupedList,
  NativeComposer,
  type ChatDraftAttachment,
  type NativeListSection,
  sessionCreationOptions,
} from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { useAuth } from '@/cloud/auth/AuthProvider';
import type { Project, Session } from '@/models/catalog';
import type { CreationOptions } from '@/models/send';
import { capabilityFor } from '@/cloud/send/capability';
import { usePalette } from '@/theme/palette';
import { type as typeScale } from '@/theme/tokens';
import { AppText } from '@/ui/AppText';
import { showToast } from '@/ui/toast';
import { readLocal, writeLocal } from '@/cloud/kv';
import { usePendingSends } from '@/cloud/send/pendingSends';
import { draftTitle } from './draftTitle';
import {
  type CreatePrefs,
  createPrefsKey,
  rememberedProject,
  restoreSelection,
  withSelection,
} from './createPrefs';
import { pickerPage } from './PickerScreen';
import {
  hasModelTabs,
  type ModelChoice,
  modelPage,
  modelSummary,
} from './ModelScreen';
import type { CreatedSession } from '../../models/send.ts';
import { t } from '../../i18n/index.ts';

export type { CreatedSession } from '../../models/send.ts';

type Params = {
  workspaceId: string;
  projects: Project[];
  projectId?: string;
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

/** Unassigned projects carry no working directory, so no session can start there. */
const creatable = (project: Project) => !project.id.endsWith(':unassigned');

function CreateSessionScreen() {
  const { params, finish, push } = usePageRuntime<Params, CreatedSession>();
  const { account } = useAuth();
  const colors = usePalette();
  const outbox = usePendingSends(account?.user.id ?? '', params.workspaceId);
  const [projects, setProjects] = useState(() =>
    params.projects.filter(creatable),
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

  const project = projects.find((p) => p.id === projectId);
  const github = projectId.startsWith('github:');

  useEffect(() => {
    let active = true;
    void readLocal<CreatePrefs>(prefsKey).then((saved) => {
      if (!active) return;
      prefs.current = saved;
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
    if (!projectId) {
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    setOptions(undefined);
    void sessionCreationOptions(
      JSON.stringify({ workspaceId: params.workspaceId, projectId }),
    )
      .then((raw) => {
        if (!active) return;
        const value: CreationOptions = JSON.parse(raw);
        setOptions(value);
        const restored = restoreSelection(prefs.current, projectId, value);
        setMachineId(restored.machineId);
        setAgentKey(restored.agentKey);
        setChoice(restored.choice);
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
  }, [params.workspaceId, projectId, revision, prefsLoaded]);

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

  useEffect(() => {
    if (!options || !agent) return;
    prefs.current = withSelection(prefs.current, projectId, {
      machineId: agent.machineId,
      agentKey,
      ...choice,
    });
    void writeLocal(prefsKey, prefs.current);
  }, [options, agent, agentKey, choice, projectId, prefsKey]);

  function submit(
    id: string,
    draft: string,
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
    busy.current = true;
    setSending(true);
    const session: Session = {
      id: options!.sessionId,
      projectId,
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
      attachments,
      phase: 'waiting' as const,
      choice: {
        ...choice,
        reasoningEffortConfigId: capability?.reasoningEffortConfigId,
      },
      creation: JSON.stringify({
        workspaceId: params.workspaceId,
        projectId,
        sessionId: session.id,
        machineId: session.machineId,
        agentConfigId: agent!.id,
        userId: account!.user.id,
        title: session.title,
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
    finish({ session, ...choice });
  }

  const sections: NativeListSection[] = [
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
    ...(github
      ? [
          {
            id: 'machine',
            rows: [
              {
                id: 'machine',
                title:
                  machine?.name ??
                  pickTitle(loading, t('create.row.selectMachine')),
                subtitle: t('create.label.machine'),
                image: 'desktopcomputer',
                action: true,
                disclosure: true,
                navigates: true,
              },
            ],
          },
        ]
      : []),
    {
      id: 'agent',
      // Model and mode live in the session's inputConfig and are inherited from
      // the previous user turn; a new session has none, so the machine decides.
      footer: agentFooter(loading, !!agent),
      rows: [
        {
          id: 'agent',
          title: agent?.name ?? pickTitle(loading, t('create.row.selectAgent')),
          subtitle: github ? t('create.label.agent') : machine?.name,
          image: 'sparkles',
          action: true,
          disclosure: true,
          navigates: true,
        },
        {
          id: 'model',
          title: capability
            ? modelSummary(capability, choice)
            : t('model.default'),
          subtitle: t('create.label.model'),
          image: 'cpu',
          action: !!capability,
          disclosure: !!capability,
          navigates: !!capability,
        },
      ],
    },
  ];

  async function pickProject() {
    const result = await push(projectPickerPage, {
      workspaceId: params.workspaceId,
      projects,
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
      pickerPage,
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
    setChoice({});
  }

  async function pickModel() {
    if (!capability) return;
    await push(
      modelPage,
      { capability, value: choice, onChange: setChoice },
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
      pickerPage,
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
    setChoice({});
  }

  const form = (
    <View style={{ flex: 1 }}>
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        transparent
        sections={sections}
        placeholder=""
        onRowPress={({ nativeEvent }) => {
          if (sending) return;
          if (nativeEvent.id === 'project') void pickProject();
          if (nativeEvent.id === 'machine') void pickMachine();
          if (nativeEvent.id === 'model') void pickModel();
          if (nativeEvent.id === 'agent') void pickAgent();
        }}
      />
      {github ? (
        <View style={{ paddingHorizontal: 16, paddingBottom: 12, gap: 4 }}>
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
              backgroundColor: colors.card,
              borderRadius: 10,
              borderCurve: 'continuous',
              paddingHorizontal: 14,
              minHeight: 44,
              fontFamily: 'Menlo',
              fontSize: typeScale.mono.size,
            }}
          />
        </View>
      ) : null}
      <NativeComposer
        composerJSON={JSON.stringify({
          editable: true,
          canSend: !!agent && !!account && !loading,
          sending,
          notice: createNotice({ loading, hasAgent: !!agent }),
          reconnect: false,
          placeholder: t('create.composer.placeholder'),
        })}
        composerOptionsJSON={JSON.stringify({
          modelId: choice.modelId ?? '',
          effort: choice.effort ?? '',
          models: (capability?.models ?? []).map((item) => ({
            id: item.id,
            title: item.name,
          })),
          efforts: (choice.modelId
            ? (capability?.reasoningEfforts[choice.modelId] ?? [])
            : []
          ).map((id) => ({ id, title: id })),
        })}
        restoreDraftToken={restoreDraftToken}
        onSend={({ nativeEvent }) =>
          submit(nativeEvent.id, nativeEvent.text, nativeEvent.attachments)
        }
        onComposerOptionChange={({ nativeEvent }) =>
          setChoice((current) => ({
            ...current,
            modelId: nativeEvent.modelId || undefined,
            effort: nativeEvent.effort || undefined,
          }))
        }
      />
    </View>
  );

  return form;
}

export const createSessionPage = definePage<Params, CreatedSession>({
  id: 'create-session',
  title: t('create.title'),
  Component: CreateSessionScreen,
  parseRouteParams: () => {
    throw new Error('请从会话列表打开');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.62, 1],
    sheetGrabberVisible: true,
  },
});
