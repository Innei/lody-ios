import { useEffect, useMemo, useRef, useState } from 'react';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  uuid,
  type NativeListRow,
  type NativeListSection,
} from '@lody-ios/kit';
import type {
  ScheduleContext,
  ScheduleDocument,
  ScheduleDraft,
  ScheduleProposalDetail,
  ScheduleProposalRef,
  ScheduleService,
} from '@lody/cloud-runtime/models/schedules';
import {
  copy,
  defaultAgent,
  draftFromProposal,
  frequencyLabel,
  newScheduleDraft,
  rezoneScheduleTrigger,
  saveBlockers,
  scheduleForDestinationSession,
  scheduleUsesElevatedPermissions,
} from '@/features/schedules/model';
import {
  pendingScheduleStore,
  performScheduleWrite,
  type PendingScheduleStore,
  type ScheduleWrite,
} from '@/features/schedules/pending';
import { requestSchedules } from '@/cloud/schedules';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { PickerScreen, type PickerOption } from './PickerScreen';
import { ScheduleFieldScreen } from './ScheduleFieldScreen';
import { ScheduleRuleScreen } from './ScheduleRuleScreen';

export type ScheduleEditorParams = {
  workspaceId: string;
  userId: string;
  document?: ScheduleDocument;
  proposal?: ScheduleProposalRef;
  service?: ScheduleService;
  context?: ScheduleContext;
  pending?: ScheduleWrite;
  pendingStore?: PendingScheduleStore;
};
function documentDraft(document: ScheduleDocument): ScheduleDraft {
  const {
    scheduleId: _id,
    ownerId: _owner,
    enabled: _enabled,
    activationId: _activation,
    activeFrom: _from,
    createdAt: _created,
    updatedAt: _updated,
    createdBy: _by,
    ...draft
  } = document.definition;
  return { ...draft, prompt: document.prompt };
}
function View() {
  const { params, finish, cancel, push, present } = usePageRuntime<
      ScheduleEditorParams,
      { scheduleId: string }
    >(),
    colors = usePalette();
  const { selected } = useCatalog();
  const service = params.service ?? requestSchedules;
  const store = useMemo(
    () =>
      params.pendingStore ??
      pendingScheduleStore(params.userId, params.workspaceId),
    [params.pendingStore, params.userId, params.workspaceId],
  );
  const [context, setContext] = useState<ScheduleContext | undefined>(
    params.context,
  );
  const editing = !!params.document || params.pending?.action === 'edit';
  const [draft, setDraft] = useState<ScheduleDraft | undefined>(() => {
    if (params.pending && 'draft' in params.pending)
      return params.pending.draft;
    if (params.document) return documentDraft(params.document);
    return undefined;
  });
  const [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [revision, setRevision] = useState(0);
  const [pending, setPending] = useState<ScheduleWrite | undefined>(
    params.pending,
  );
  const [worktree, setWorktree] = useState<boolean>();
  const saving = useRef(false),
    identity = useRef(
      params.pending?.scheduleId ??
        params.document?.definition.scheduleId ??
        params.proposal?.proposalId ??
        uuid.v4(),
    );
  const request = useRef<ScheduleWrite | undefined>(params.pending);
  const scoped = !!params.service || selected?.id === params.workspaceId;
  useEffect(() => {
    if (!scoped) cancel();
  }, [scoped, cancel]);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError('');
    void (async () => {
      const next =
        params.context ??
        ((await service({
          workspaceId: params.workspaceId,
          action: 'context',
        })) as ScheduleContext);
      let initial = params.document
        ? documentDraft(params.document)
        : newScheduleDraft(next, params.userId);
      if (params.proposal) {
        const source = (await service({
          workspaceId: params.workspaceId,
          action: 'proposal',
          ref: params.proposal,
        })) as ScheduleProposalDetail;
        if (source.proposal.outcome === 'dismissed')
          throw new Error(copy('schedules.proposalMissing'));
        if (
          source.proposal.outcome === 'created' &&
          source.proposal.scheduleId
        ) {
          await store.remove(source.proposal.scheduleId);
          if (active) finish({ scheduleId: source.proposal.scheduleId });
          return;
        }
        initial = draftFromProposal(source, next);
      }
      const restored =
        params.pending ??
        (await store.read()).find(
          (entry) =>
            entry.scheduleId === identity.current &&
            (entry.action === 'create' || entry.action === 'edit'),
        );
      if (active) {
        setContext(next);
        setDraft(restored && 'draft' in restored ? restored.draft : initial);
        setPending(restored);
        request.current = restored;
        setLoading(false);
      }
    })().catch((cause) => {
      if (active) {
        setError(
          cause instanceof Error ? cause.message : copy('schedules.loadFailed'),
        );
        setLoading(false);
      }
    });
    return () => {
      active = false;
    };
  }, [
    params.workspaceId,
    params.userId,
    params.context,
    params.document,
    params.proposal,
    params.pending,
    service,
    store,
    revision,
    finish,
  ]);
  const project = draft?.project;
  const projectId =
    project?.kind === 'local'
      ? `${draft?.machineId}:local:${project.localProjectId}`
      : undefined;
  useEffect(() => {
    let active = true;
    setWorktree(undefined);
    if (projectId)
      void service({
        workspaceId: params.workspaceId,
        action: 'worktree',
        projectId,
      })
        .then((result) => {
          if (active && 'available' in result) setWorktree(result.available);
        })
        .catch(() => {
          if (active) setWorktree(false);
        });
    return () => {
      active = false;
    };
  }, [projectId, params.workspaceId, service]);
  const locked =
    busy ||
    !!pending ||
    (!!params.document && params.document.definition.ownerId !== params.userId);
  const blockers =
    draft && context
      ? saveBlockers(
          draft,
          context,
          params.userId,
          params.document?.definition.ownerId,
        )
      : [];
  async function save() {
    if (saving.current || !draft || !context || (!pending && blockers.length))
      return;
    const write: ScheduleWrite = request.current ?? {
      workspaceId: params.workspaceId,
      action: editing ? 'edit' : 'create',
      scheduleId: identity.current,
      requestId: params.proposal
        ? `proposal-${params.proposal.proposalId}`
        : uuid.v4(),
      draft,
      ...(params.proposal ? { proposal: params.proposal } : {}),
    };
    request.current = write;
    saving.current = true;
    setBusy(true);
    setError('');
    try {
      await performScheduleWrite(write, service, store);
      finish({ scheduleId: identity.current });
    } catch (cause) {
      const remains = (await store.read()).find(
        (entry) => entry.scheduleId === identity.current,
      );
      setPending(remains);
      request.current = remains;
      setError(
        cause instanceof Error ? cause.message : copy('schedules.saveFailed'),
      );
    } finally {
      saving.current = false;
      setBusy(false);
    }
  }
  let saveLabel = copy(editing ? 'schedules.save' : 'schedules.create');
  if (pending) saveLabel = copy('schedules.retrySave');
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: saveLabel,
        accessibilityLabel: saveLabel,
        identifier: 'schedule-save',
        variant: 'prominent' as const,
        disabled:
          busy || loading || !draft || (!pending && blockers.length > 0),
        onPress: () => void save(),
      },
    ],
    [
      saveLabel,
      params.document,
      busy,
      loading,
      draft,
      blockers.length,
      context,
      store,
      service,
    ],
  );
  const left = useMemo(
    () => [
      {
        type: 'button' as const,
        title: copy('common.cancel'),
        accessibilityLabel: copy('common.cancel'),
        disabled: busy,
        onPress: cancel,
      },
    ],
    [busy, cancel],
  );
  if (!scoped) return null;
  const machine = context?.machines.find(
      (entry) => entry.id === draft?.machineId,
    ),
    agent = context?.agents.find(
      (entry) => entry.id === draft?.agent.agentConfigId,
    );
  const ruleZone =
    draft?.trigger.kind === 'cron'
      ? draft.trigger.timeZone
      : (machine?.timeZone ?? 'UTC');
  const capability = context?.capabilities.find(
    (entry) =>
      entry.machineId === agent?.machineId &&
      entry.cliType === agent?.cliType &&
      entry.agentType === agent?.agentType,
  );
  function field(id: string, title: string, value?: string): NativeListRow {
    return {
      id,
      title,
      value,
      action: !locked,
      disclosure: !locked,
      navigates: !locked,
    };
  }
  const sections: NativeListSection[] = [];
  if (error)
    sections.push({
      id: 'error',
      rows: [
        {
          id: 'schedule-editor-error',
          title: error,
          wrapSubtitle: true,
          image: 'exclamationmark.triangle',
          imageTint: 'warning',
        },
        ...(!draft
          ? [{ id: 'retry', title: copy('common.retry'), action: true }]
          : []),
      ],
    });
  if (pending)
    sections.push({
      id: 'pending',
      footer: copy('schedules.pendingHint'),
      rows: [{ id: 'pending-note', title: copy('schedules.pendingTitle') }],
    });
  if (draft && context) {
    const info = [
      field(
        'name',
        copy('schedules.name'),
        draft.title || copy('schedules.enterName'),
      ),
      {
        ...field('prompt', copy('schedules.prompt')),
        subtitle: draft.prompt || copy('schedules.enterPrompt'),
        wrapSubtitle: true,
      },
    ];
    sections.push({
      id: 'definition',
      header: params.proposal ? copy('schedules.proposalReview') : undefined,
      footer: params.proposal ? copy('schedules.proposalHint') : undefined,
      rows: info,
    });
    const configuration = [
      field(
        'machine',
        copy('schedules.machine'),
        machine?.name ?? copy('schedules.choose'),
      ),
      field(
        'agent',
        copy('schedules.agent'),
        agent?.name ?? copy('schedules.choose'),
      ),
    ];
    if (context.roles.length)
      configuration.push(
        field('role', copy('schedules.role'), copy('schedules.chooseRole')),
      );
    if (capability?.models.length)
      configuration.push(
        field(
          'model',
          copy('schedules.model'),
          capability.models.find((entry) => entry.id === draft.agent.modelId)
            ?.name ??
            draft.agent.modelId ??
            copy('schedules.agentDefault'),
        ),
      );
    if (capability?.modes.length)
      configuration.push(
        field(
          'mode',
          copy('schedules.permissions'),
          capability.modes.find((entry) => entry.id === draft.agent.modeId)
            ?.name ??
            draft.agent.modeId ??
            copy('schedules.agentDefault'),
        ),
      );
    for (const option of capability?.configOptions ?? []) {
      if (
        option.category === 'model' ||
        (option.category === 'mode' && capability?.modes.length)
      )
        continue;
      const value =
        draft.agent.configOptionValues?.[option.id] ?? option.currentValue;
      if (option.type === 'boolean')
        configuration.push({
          id: `config:${option.id}`,
          title: option.name,
          toggle: value === true,
          action: !locked,
        });
      else
        configuration.push(
          field(
            `config:${option.id}`,
            option.name,
            option.options.find((entry) => entry.id === value)?.name ??
              String(value ?? copy('schedules.agentDefault')),
          ),
        );
    }
    sections.push({
      id: 'configuration',
      header: copy('schedules.configuration'),
      footer:
        machine?.state === 'online'
          ? undefined
          : copy('schedules.machineOfflineSave'),
      rows: configuration,
    });
    if (scheduleUsesElevatedPermissions(draft.agent))
      sections.push({
        id: 'permissions',
        footer: copy('schedules.elevatedHint'),
        rows: [
          {
            id: 'elevated',
            title: copy('schedules.elevated'),
            image: 'exclamationmark.shield',
            imageTint: 'warning',
          },
        ],
      });
    const destination = draft.destination;
    sections.push({
      id: 'timing',
      rows: [
        field(
          'rule',
          copy('schedules.frequency'),
          frequencyLabel(draft, ruleZone),
        ),
        field(
          'destination',
          copy('schedules.destination'),
          copy(`schedules.destination.${destination.kind}`),
        ),
        ...(destination.kind === 'existing_session'
          ? [
              field(
                'session',
                copy('schedules.chat'),
                context.sessions.find(
                  (entry) => entry.id === destination.sessionId,
                )?.title ?? copy('schedules.choose'),
              ),
            ]
          : []),
      ],
    });
    if (destination.kind === 'new_session') {
      const selectedProject = context.projects.find(
        (entry) =>
          entry.project.kind === project?.kind &&
          ((entry.project.kind === 'local' &&
            project?.kind === 'local' &&
            entry.machineId === draft.machineId &&
            entry.project.localProjectId === project.localProjectId) ||
            (entry.project.kind === 'github' &&
              project?.kind === 'github' &&
              entry.project.repoFullName === project.repoFullName)),
      );
      const rows = [
        field(
          'project',
          copy('schedules.project'),
          selectedProject?.name ??
            (project?.kind === 'github'
              ? project.repoFullName
              : copy('schedules.noProject')),
        ),
      ];
      if (project)
        rows.push(
          field(
            'branch',
            copy('schedules.branch'),
            project.branch ?? copy('schedules.defaultBranch'),
          ),
        );
      if (project?.kind === 'local')
        rows.push({
          id: 'worktree',
          title: copy('schedules.worktree'),
          toggle: project.useWorktree === true,
          action: !locked && worktree === true,
        });
      let worktreeFooter;
      if (project?.kind === 'local' && worktree !== true)
        worktreeFooter = copy('schedules.worktreeUnavailable');
      if (project?.kind === 'local' && worktree === undefined)
        worktreeFooter = copy('schedules.checkingWorktree');
      sections.push({ id: 'project', footer: worktreeFooter, rows });
    }
    sections.push({
      id: 'policies',
      rows: [
        {
          id: 'misfire',
          action: !locked,
          title: copy('schedules.missedRuns'),
          value: copy(`schedules.misfire.${draft.misfirePolicy.kind}`),
          options: locked
            ? []
            : ['skip', 'run_once'].map((kind) => ({
                id: kind,
                title: copy(`schedules.misfire.${kind}`),
                selected: draft.misfirePolicy.kind === kind,
              })),
        },
        {
          id: 'overlap',
          action: !locked,
          title: copy('schedules.overlap'),
          value: copy(`schedules.overlap.${draft.overlapPolicy}`),
          options: locked
            ? []
            : ['skip', 'queue_one'].map((kind) => ({
                id: kind,
                title: copy(`schedules.overlap.${kind}`),
                selected: draft.overlapPolicy === kind,
              })),
        },
      ],
    });
    if (blockers.length)
      sections.push({
        id: 'blockers',
        header: copy('schedules.beforeSave'),
        rows: blockers.map((title, index) => ({
          id: `schedule-blocker:${index}`,
          title,
          wrapSubtitle: true,
          image: 'exclamationmark.circle',
          imageTint: 'warning',
        })),
      });
  }
  async function pick(
    title: string,
    options: PickerOption[],
    selectedId?: string,
  ) {
    const result = await push(
      PickerScreen,
      { title, options, selectedId },
      { title },
    );
    return result.status === 'completed' ? result.value : undefined;
  }
  async function edit(id: string) {
    if (id === 'retry') {
      setRevision((value) => value + 1);
      return;
    }
    if (locked || !draft || !context) return;
    if (id === 'name' || id === 'prompt') {
      const key = id === 'name' ? 'title' : 'prompt';
      const result = await present(ScheduleFieldScreen, {
        title: copy(`schedules.${id}`),
        value: draft[key],
        multiline: id === 'prompt',
        maxLength: id === 'prompt' ? 32768 : 200,
      });
      if (result.status === 'completed')
        setDraft({ ...draft, [key]: result.value });
    }
    if (id === 'rule') {
      const result = await push(ScheduleRuleScreen, {
        trigger: draft.trigger,
        timeZone: ruleZone,
      });
      if (result.status === 'completed')
        setDraft({ ...draft, trigger: result.value });
    }
    if (id === 'machine') {
      const chosen = await pick(
        copy('schedules.machine'),
        context.machines.map((entry) => ({
          id: entry.id,
          title: entry.name,
          subtitle: copy(`schedules.machineState.${entry.state}`),
        })),
        draft.machineId,
      );
      if (chosen) {
        const next = context.agents.find((entry) => entry.machineId === chosen),
          zone =
            context.machines.find((entry) => entry.id === chosen)?.timeZone ??
            'UTC';
        setDraft({
          ...draft,
          machineId: chosen,
          agent: next ? defaultAgent(next, context) : { agentConfigId: '' },
          project: undefined,
          trigger: rezoneScheduleTrigger(draft.trigger, zone),
        });
      }
    }
    if (id === 'agent') {
      const chosen = await pick(
        copy('schedules.agent'),
        context.agents
          .filter((entry) => entry.machineId === draft.machineId)
          .map((entry) => ({ id: entry.id, title: entry.name })),
        draft.agent.agentConfigId,
      );
      const next = context.agents.find((entry) => entry.id === chosen);
      if (next) setDraft({ ...draft, agent: defaultAgent(next, context) });
    }
    if (id === 'role') {
      const chosen = await pick(
        copy('schedules.role'),
        context.roles.map((entry) => ({
          id: entry.id,
          title: entry.name,
          subtitle: context.machines.find(
            (machine) => machine.id === entry.machineId,
          )?.name,
        })),
      );
      const next = context.roles.find((entry) => entry.id === chosen);
      if (next)
        setDraft({
          ...draft,
          machineId: next.machineId,
          agent: { agentConfigId: next.agentConfigId, ...next.runConfig },
          project: undefined,
          trigger: rezoneScheduleTrigger(
            draft.trigger,
            context.machines.find((entry) => entry.id === next.machineId)
              ?.timeZone ?? 'UTC',
          ),
        });
    }
    if (id === 'model' || id === 'mode') {
      const choices = id === 'model' ? capability?.models : capability?.modes;
      const key = id === 'model' ? 'modelId' : 'modeId';
      const chosen = await pick(
        copy(id === 'model' ? 'schedules.model' : 'schedules.permissions'),
        [
          { id: 'agent-default', title: copy('schedules.agentDefault') },
          ...(choices ?? []).map((entry) => ({
            id: entry.id,
            title: entry.name,
            subtitle: entry.description,
          })),
        ],
        draft.agent[key] ?? 'agent-default',
      );
      if (chosen !== undefined)
        setDraft({
          ...draft,
          agent: {
            ...draft.agent,
            [key]: chosen === 'agent-default' ? undefined : chosen,
          },
        });
    }
    if (id.startsWith('config:')) {
      const option = capability?.configOptions?.find(
        (entry) => `config:${entry.id}` === id,
      );
      if (option?.type === 'select') {
        const chosen = await pick(
          option.name,
          option.options.map((entry) => ({
            id: entry.id,
            title: entry.name,
            subtitle: entry.description,
          })),
          String(
            draft.agent.configOptionValues?.[option.id] ??
              option.currentValue ??
              '',
          ),
        );
        if (chosen !== undefined)
          setDraft({
            ...draft,
            agent: {
              ...draft.agent,
              configOptionValues: {
                ...draft.agent.configOptionValues,
                [option.id]: chosen,
              },
            },
          });
      }
    }
    if (id === 'destination') {
      const chosen = await pick(
        copy('schedules.destination'),
        ['new_session', 'own_session', 'existing_session'].map((kind) => ({
          id: kind,
          title: copy(`schedules.destination.${kind}`),
        })),
        draft.destination.kind,
      );
      if (chosen === 'new_session')
        setDraft({ ...draft, destination: { kind: chosen } });
      if (chosen === 'own_session')
        setDraft({
          ...draft,
          project: undefined,
          destination: {
            kind: chosen,
            epoch:
              draft.destination.kind === 'own_session'
                ? draft.destination.epoch
                : 0,
          },
        });
      if (chosen === 'existing_session')
        setDraft({
          ...draft,
          project: undefined,
          destination: { kind: chosen, sessionId: '' },
        });
    }
    if (id === 'session') {
      const chosen = await pick(
        copy('schedules.chat'),
        context.sessions
          .filter((entry) => entry.ownerId === params.userId)
          .map((entry) => ({
            id: entry.id,
            title: entry.title || copy('schedules.openRun'),
            subtitle: context.machines.find(
              (machine) => machine.id === entry.machineId,
            )?.name,
          })),
      );
      const target = context.sessions.find((entry) => entry.id === chosen);
      if (target)
        setDraft(scheduleForDestinationSession(draft, target, context));
    }
    if (id === 'project') {
      const chosen = await pick(copy('schedules.project'), [
        { id: 'none', title: copy('schedules.noProject') },
        { id: 'github', title: copy('schedules.githubRepo') },
        ...context.projects
          .filter(
            (entry) => !entry.machineId || entry.machineId === draft.machineId,
          )
          .map((entry) => ({ id: entry.id, title: entry.name })),
      ]);
      if (chosen === 'none') setDraft({ ...draft, project: undefined });
      else if (chosen === 'github') {
        const result = await present(ScheduleFieldScreen, {
          title: copy('schedules.githubRepo'),
          value: '',
          hint: copy('schedules.repoHint'),
        });
        if (result.status === 'completed')
          setDraft({
            ...draft,
            project: {
              kind: 'github',
              repoFullName: result.value.trim(),
              branch: 'main',
            },
          });
      } else {
        const next = context.projects.find((entry) => entry.id === chosen);
        if (next) setDraft({ ...draft, project: next.project });
      }
    }
    if (id === 'branch' && draft.project) {
      const result = await present(ScheduleFieldScreen, {
        title: copy('schedules.branch'),
        value: draft.project.branch ?? '',
        hint: copy('schedules.branchHint'),
      });
      if (result.status === 'completed')
        setDraft({
          ...draft,
          project: {
            ...draft.project,
            branch: result.value.trim() || undefined,
          } as ScheduleDraft['project'],
        });
    }
  }
  let title = copy('schedules.create');
  if (editing) title = copy('schedules.edit');
  if (params.proposal) title = copy('schedules.proposalReview');
  return (
    <>
      <NativeNavigationHeader title={title} items={actions} leftItems={left} />
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        placeholder={loading ? copy('schedules.loading') : ''}
        sections={sections}
        onRowPress={({ nativeEvent }) => void edit(nativeEvent.id)}
        onRowToggle={({ nativeEvent: { id, value } }) => {
          if (locked || !draft) return;
          if (id === 'worktree' && draft.project?.kind === 'local' && worktree)
            setDraft({
              ...draft,
              project: { ...draft.project, useWorktree: value },
            });
          if (id.startsWith('config:'))
            setDraft({
              ...draft,
              agent: {
                ...draft.agent,
                configOptionValues: {
                  ...draft.agent.configOptionValues,
                  [id.slice(7)]: value,
                },
              },
            });
        }}
        onRowAction={({ nativeEvent: { id, actionId } }) => {
          if (locked || !draft) return;
          if (id === 'misfire')
            setDraft({
              ...draft,
              misfirePolicy: {
                kind: actionId as ScheduleDraft['misfirePolicy']['kind'],
              },
            });
          if (id === 'overlap')
            setDraft({
              ...draft,
              overlapPolicy: actionId as ScheduleDraft['overlapPolicy'],
            });
        }}
      />
    </>
  );
}
export const ScheduleEditorScreen = definePage<
  ScheduleEditorParams,
  { scheduleId: string }
>({
  id: 'schedule-editor',
  title: copy('schedules.edit'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from scheduled tasks');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
