import { useMemo, useState } from 'react';
import { NativeGroupedList, NativeNavigationHeader } from '@lody-ios/kit';
import type { Catalog, Session } from '@lody/cloud-runtime/models/catalog';
import type {
  ScheduleContext,
  ScheduleDocument,
  ScheduleDraft,
  ScheduleProposal,
  ScheduleRow,
  ScheduleService,
} from '@lody/cloud-runtime/models/schedules';
import { canonicalScheduleJson } from '@lody/cloud-runtime/protocol/schedules';
import { previewSchedule } from '@lody/cloud-runtime/protocol/schedule-time';
import {
  memoryScheduleStore,
  type PendingScheduleStore,
} from '@/features/schedules/pending';
import { copy } from '@/features/schedules/model';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { SchedulesView } from '../SchedulesScreen';
import { ScheduleDetailScreen } from '../ScheduleDetailScreen';
import { ScheduleEditorScreen } from '../ScheduleEditorScreen';

const userId = 'schedule-fixture-user',
  workspaceId = 'offline-schedules';
const context: ScheduleContext = {
  machines: [
    {
      id: 'studio',
      name: 'Studio Mac',
      ownerId: userId,
      timeZone: 'Asia/Shanghai',
      supported: true,
      state: 'online',
    },
    {
      id: 'offline',
      name: 'Offline Mac',
      ownerId: userId,
      timeZone: 'America/New_York',
      supported: true,
      state: 'offline',
    },
    {
      id: 'old',
      name: 'Older CLI',
      ownerId: userId,
      timeZone: 'UTC',
      supported: false,
      state: 'online',
    },
    {
      id: 'shared',
      name: 'Shared Mac',
      ownerId: 'another-owner',
      timeZone: 'UTC',
      supported: true,
      state: 'online',
    },
  ],
  agents: [
    {
      id: 'codex',
      name: 'Codex',
      machineId: 'studio',
      machineName: 'Studio Mac',
      cliType: 'builtin',
      agentType: 'codex',
    },
    {
      id: 'claude',
      name: 'Claude',
      machineId: 'studio',
      machineName: 'Studio Mac',
      cliType: 'builtin',
      agentType: 'claude',
    },
    {
      id: 'offline-agent',
      name: 'Offline Agent',
      machineId: 'offline',
      machineName: 'Offline Mac',
      cliType: 'builtin',
      agentType: 'codex',
    },
  ],
  capabilities: [
    {
      machineId: 'studio',
      cliType: 'builtin',
      agentType: 'codex',
      models: [
        { id: 'model-a', name: 'Model A' },
        { id: 'model-b', name: 'Model B' },
      ],
      modes: [
        { id: 'agent', name: 'Ask before risky actions' },
        { id: 'danger-full-access', name: 'Full access' },
      ],
      configOptions: [
        {
          id: 'fast',
          name: 'Fast mode',
          type: 'boolean',
          currentValue: false,
          options: [],
        },
      ],
      reasoningEfforts: {},
      steer: false,
    },
  ],
  roles: [
    {
      id: 'reviewer',
      name: 'Review assistant',
      machineId: 'studio',
      agentConfigId: 'codex',
      runConfig: { modelId: 'model-b', modeId: 'agent' },
    },
  ],
  projects: [
    {
      id: 'studio:local:demo',
      name: 'Demo Project',
      machineId: 'studio',
      project: { kind: 'local', localProjectId: 'demo' },
    },
    {
      id: 'github:example/demo',
      name: 'example/demo',
      machineId: '',
      project: { kind: 'github', repoFullName: 'example/demo', branch: 'main' },
    },
  ],
  sessions: [
    {
      id: 'existing-chat',
      title: 'Existing review conversation',
      machineId: 'studio',
      agentConfigId: 'codex',
      ownerId: userId,
    },
  ],
};
const initial: ScheduleDraft = {
  title: 'Morning review',
  prompt:
    'Review the latest changes and explain anything that needs attention.',
  machineId: 'studio',
  trigger: {
    kind: 'cron',
    expression: '0 9 * * 1-5',
    timeZone: 'Asia/Shanghai',
  },
  agent: {
    agentConfigId: 'codex',
    modeId: 'agent',
    modelId: 'model-a',
    configOptionValues: { fast: false },
  },
  destination: { kind: 'new_session' },
  misfirePolicy: { kind: 'run_once' },
  overlapPolicy: 'queue_one',
  retryPolicy: { dispatchMaxAttempts: 5, dispatchMaxAgeMs: 86_400_000 },
};
const proposal: ScheduleProposal = {
  proposalId: 'proposal-review',
  title: 'Proposed weekly review',
  prompt: 'Summarize the project each Monday.',
  rule: { kind: 'weekly', weekdays: [1], hour: 9, minute: 0 },
  destination: { kind: 'own_session' },
  target: { agentRoleId: 'reviewer' },
};
function document(
  id: string,
  draft = initial,
  ownerId = userId,
  enabled = true,
): ScheduleDocument {
  const { prompt, ...definition } = draft;
  return {
    definition: {
      ...definition,
      scheduleId: id,
      ownerId,
      enabled,
      activationId: `activation-${id}`,
      activeFrom: Date.parse('2026-09-01T00:00:00Z'),
      createdAt: Date.parse('2026-09-01T00:00:00Z'),
      updatedAt: Date.parse('2026-09-01T00:00:00Z'),
      createdBy: ownerId,
    },
    prompt,
    timeline: [],
  };
}
function row(document: ScheduleDocument): ScheduleRow {
  const d = document.definition;
  return {
    scheduleId: d.scheduleId,
    title: d.title,
    ownerId: d.ownerId,
    machineId: d.machineId,
    enabled: d.enabled,
    activationId: d.activationId,
    activeFrom: d.activeFrom,
    trigger: d.trigger,
    destination: d.destination,
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
    agentConfigId: d.agent.agentConfigId,
    elevatedPermissions: d.agent.modeId === 'danger-full-access',
    definitionFingerprint: 'a'.repeat(64),
  };
}
const result: Session = {
  id: 'result-chat',
  title: 'Morning review result',
  machineId: 'studio',
  projectId: 'studio:unassigned',
  createdAt: '2026-09-25T01:00:00Z',
  status: 'completed',
  archived: false,
  pinned: false,
  scheduleId: 'morning',
};
const catalog: Catalog = {
  projects: [],
  sessions: [result],
  machineIds: ['studio', 'offline', 'old', 'shared'],
};
function previewService(report: (message: string) => void) {
  const docs = new Map([
    ['morning', document('morning')],
    [
      'offline',
      document('offline', {
        ...initial,
        title: 'Offline task',
        machineId: 'offline',
        agent: { agentConfigId: 'offline-agent' },
      }),
    ],
    [
      'old',
      document(
        'old',
        { ...initial, title: 'Upgrade required', machineId: 'old' },
        userId,
        false,
      ),
    ],
    [
      'shared',
      document(
        'shared',
        { ...initial, title: 'Another owner’s task', machineId: 'shared' },
        'another-owner',
      ),
    ],
  ]);
  const acknowledged = new Map<string, string>();
  let loseAcknowledgement = true,
    createdProposal: ScheduleProposal = { ...proposal };
  const service: ScheduleService = async (request) => {
    if (request.action === 'context') return context;
    if (request.action === 'list')
      return { rows: [...docs.values()].map(row), runtimes: [] };
    if (request.action === 'worktree') return { available: true };
    if (request.action === 'proposal')
      return {
        proposal: createdProposal,
        conversation: {
          ...context.sessions[0],
          runConfig: { agentConfigId: 'codex', modeId: 'agent' },
        },
      };
    const previous = docs.get(request.scheduleId);
    if (request.action === 'show') {
      if (!previous)
        throw Object.assign(new Error(copy('schedules.notFound')), {
          code: 'schedule_not_found',
        });
      return {
        document: previous,
        next: previewSchedule(
          previous.definition.trigger,
          previous.definition.activeFrom,
          Date.now(),
        ),
      };
    }
    if (previous && previous.definition.ownerId !== userId)
      throw Object.assign(new Error(copy('schedules.ownerOnly')), {
        code: 'schedule_owner_only',
      });
    const key =
      request.action === 'delete'
        ? `delete:${request.scheduleId}`
        : `${request.scheduleId}:${request.requestId}`;
    const prior = acknowledged.get(key),
      fingerprint = canonicalScheduleJson(request);
    if (prior) {
      if (prior !== fingerprint)
        throw Object.assign(new Error(copy('schedules.retryConflict')), {
          code: 'schedule_idempotency_conflict',
        });
      return { ok: true, scheduleId: request.scheduleId };
    }
    if (request.action === 'run' || request.action === 'resume') {
      const machine = context.machines.find(
        (entry) => entry.id === previous?.definition.machineId,
      );
      if (!machine?.supported)
        throw Object.assign(new Error(copy('schedules.upgrade')), {
          code: 'schedule_upgrade',
        });
      if (machine.state !== 'online')
        throw Object.assign(new Error(copy('schedules.machineOffline')), {
          code: 'schedule_machine_offline',
        });
    }
    if (request.action === 'create' || request.action === 'edit') {
      const next = document(
        request.scheduleId,
        request.draft,
        previous?.definition.ownerId ?? userId,
        previous?.definition.enabled ?? true,
      );
      docs.set(request.scheduleId, next);
      if (request.proposal)
        createdProposal = {
          ...createdProposal,
          outcome: 'created',
          scheduleId: request.scheduleId,
        };
      report('Task saved');
    } else if (request.action === 'delete') {
      docs.delete(request.scheduleId);
      report('Task deleted');
    } else if (
      previous &&
      (request.action === 'pause' || request.action === 'resume')
    ) {
      docs.set(request.scheduleId, {
        ...previous,
        definition: {
          ...previous.definition,
          enabled: request.action === 'resume',
        },
      });
      report(request.action === 'pause' ? 'Task paused' : 'Task resumed');
    } else if (request.action === 'run') report('Run requested');
    acknowledged.set(key, fingerprint);
    if (
      loseAcknowledgement &&
      (request.action === 'create' || request.action === 'edit')
    ) {
      loseAcknowledgement = false;
      throw Object.assign(new Error(copy('schedules.writeUnknown')), {
        code: 'schedule_write_unknown',
      });
    }
    return { ok: true, scheduleId: request.scheduleId };
  };
  return { service, docs };
}
type PreviewParams = { service: ScheduleService; store: PendingScheduleStore };
const ScheduleListPreviewScreen = definePage<PreviewParams>({
  id: 'schedule-list-preview',
  title: copy('schedules.title'),
  Component: () => {
    const { params } = usePageRuntime<PreviewParams>();
    return (
      <SchedulesView
        workspaceId={workspaceId}
        userId={userId}
        service={params.service}
        catalog={catalog}
        pendingStore={params.store}
      />
    );
  },
  parseRouteParams: () => {
    throw new Error('Open from schedules preview');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
const ScheduleResultPreviewScreen = definePage({
  id: 'schedule-result-preview',
  title: 'Result conversation',
  Component: () => (
    <NativeGroupedList
      style={{ flex: 1 }}
      sections={[
        {
          id: 'result',
          rows: [
            {
              id: 'schedule-result-ready',
              title: 'Morning review result',
              subtitle:
                'This result was opened from the production task history.',
            },
          ],
        },
      ]}
      onRowPress={() => {}}
    />
  ),
  presentation: { style: 'push', headerVariant: 'transparent' },
});
function View() {
  const { push, present } = usePageRuntime(),
    [report, setReport] = useState('Offline schedules ready');
  const fixture = useMemo(() => previewService(setReport), []),
    store = useMemo(memoryScheduleStore, []);
  return (
    <>
      <NativeNavigationHeader title="Scheduled task verification" />
      <NativeGroupedList
        style={{ flex: 1 }}
        sections={[
          {
            id: 'ready',
            rows: [{ id: 'schedules-preview-ready', title: report }],
          },
          {
            id: 'scenes',
            rows: [
              {
                id: 'schedules-list',
                title: 'Task list and search',
                action: true,
                disclosure: true,
                navigates: true,
              },
              {
                id: 'schedules-edit',
                title: 'Task editor and retry',
                action: true,
                disclosure: true,
                navigates: true,
              },
              {
                id: 'schedules-proposal',
                title: 'Review Agent proposal',
                action: true,
                disclosure: true,
                navigates: true,
              },
              {
                id: 'schedules-offline',
                title: 'Offline machine restriction',
                action: true,
                disclosure: true,
                navigates: true,
              },
              {
                id: 'schedules-owner',
                title: 'Owner restriction',
                action: true,
                disclosure: true,
                navigates: true,
              },
              {
                id: 'schedules-upgrade',
                title: 'Machine upgrade restriction',
                action: true,
                disclosure: true,
                navigates: true,
              },
              {
                id: 'schedules-history',
                title: 'Result history',
                action: true,
                disclosure: true,
                navigates: true,
              },
            ],
          },
        ]}
        onRowPress={({ nativeEvent: { id } }) => {
          if (id === 'schedules-list')
            void push(ScheduleListPreviewScreen, {
              service: fixture.service,
              store,
            });
          if (id === 'schedules-edit')
            void present(ScheduleEditorScreen, {
              workspaceId,
              userId,
              document: fixture.docs.get('morning'),
              context,
              service: fixture.service,
              pendingStore: store,
            });
          if (id === 'schedules-proposal')
            void present(ScheduleEditorScreen, {
              workspaceId,
              userId,
              proposal: {
                sessionId: 'existing-chat',
                entryId: 'proposal-entry',
                itemIndex: 0,
                proposalId: proposal.proposalId,
              },
              context,
              service: fixture.service,
              pendingStore: store,
            }).then((outcome) => {
              if (outcome.status === 'completed')
                setReport('Proposal confirmed');
            });
          const targets: Record<string, string> = {
            'schedules-offline': 'offline',
            'schedules-owner': 'shared',
            'schedules-upgrade': 'old',
            'schedules-history': 'morning',
          };
          const scheduleId = targets[id];
          if (scheduleId)
            void push(ScheduleDetailScreen, {
              scheduleId,
              workspaceId,
              userId,
              service: fixture.service,
              catalog,
              pendingStore: store,
              openSession: () => {
                void push(ScheduleResultPreviewScreen, undefined);
              },
            });
        }}
      />
    </>
  );
}
export const SchedulePreviewScreen = definePage({
  id: 'schedule-preview',
  title: 'Scheduled task verification',
  Component: View,
  presentation: { headerVariant: 'transparent', style: 'push' },
});
