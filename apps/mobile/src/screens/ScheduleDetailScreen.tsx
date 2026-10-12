import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert } from 'react-native';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  uuid,
  type NativeListSection,
} from '@lody-ios/kit';
import type { Catalog, Session } from '@lody/cloud-runtime/models/catalog';
import type {
  ScheduleContext,
  ScheduleDetail,
  ScheduleService,
} from '@lody/cloud-runtime/models/schedules';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { requestSchedules } from '@/cloud/schedules';
import {
  copy,
  dateLabel,
  frequencyLabel,
  scheduleDisplayTimeZone,
} from '@/features/schedules/model';
import {
  pendingScheduleStore,
  performScheduleWrite,
  type PendingScheduleStore,
  type ScheduleWrite,
} from '@/features/schedules/pending';
import { requestOpenSessionFromPage } from '@/features/sessions/sessionNav';
import { sessionStatus } from '@/features/sessions/status';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import { ScheduleEditorScreen } from './ScheduleEditorScreen';

export type ScheduleDetailParams = {
  scheduleId: string;
  workspaceId?: string;
  userId?: string;
  service?: ScheduleService;
  catalog?: Catalog;
  pendingStore?: PendingScheduleStore;
  openSession?: (session: Session) => void;
};
export function ScheduleDetailView({
  scheduleId,
  workspaceId,
  userId,
  service = requestSchedules,
  catalog,
  pendingStore,
  openSession,
}: Required<
  Pick<ScheduleDetailParams, 'scheduleId' | 'workspaceId' | 'userId'>
> &
  Omit<ScheduleDetailParams, 'scheduleId' | 'workspaceId' | 'userId'>) {
  const { push, present, cancel } = usePageRuntime(),
    colors = usePalette();
  const store = useMemo(
    () => pendingStore ?? pendingScheduleStore(userId, workspaceId),
    [pendingStore, userId, workspaceId],
  );
  const [detail, setDetail] = useState<ScheduleDetail>(),
    [context, setContext] = useState<ScheduleContext>(),
    [loading, setLoading] = useState(true),
    [error, setError] = useState(''),
    [busy, setBusy] = useState(false),
    [revision, setRevision] = useState(0),
    [pending, setPending] = useState<ScheduleWrite>();
  const running = useRef(false);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError('');
    void Promise.all([
      service({ workspaceId, action: 'show', scheduleId }),
      service({ workspaceId, action: 'context' }),
      store.read(),
    ])
      .then(([next, options, writes]) => {
        if (active) {
          setDetail(next as ScheduleDetail);
          setContext(options as ScheduleContext);
          setPending(writes.find((entry) => entry.scheduleId === scheduleId));
          setLoading(false);
        }
      })
      .catch((cause) => {
        if (active) {
          setLoading(false);
          setError(
            cause instanceof Error
              ? cause.message
              : copy('schedules.loadFailed'),
          );
        }
      });
    return () => {
      active = false;
    };
  }, [workspaceId, scheduleId, service, store, revision]);
  const definition = detail?.document.definition,
    machine = context?.machines.find(
      (entry) => entry.id === definition?.machineId,
    ),
    owned = definition?.ownerId === userId;
  const canRun =
    owned &&
    machine?.ownerId === userId &&
    machine.supported &&
    machine.state === 'online';
  const canEdit = owned && machine?.ownerId === userId && machine.supported;
  const history = (catalog?.sessions ?? [])
    .filter((session) => session.scheduleId === scheduleId)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .slice(0, 100);
  async function mutate(action: 'run' | 'pause' | 'resume' | 'delete') {
    if (running.current || !definition) return;
    const request: ScheduleWrite =
      pending ??
      (action === 'delete'
        ? { workspaceId, action, scheduleId }
        : { workspaceId, action, scheduleId, requestId: uuid.v4() });
    if (pending && pending.action !== action) return;
    running.current = true;
    setBusy(true);
    setError('');
    try {
      await performScheduleWrite(request, service, store);
      setPending(undefined);
      if (action === 'delete') cancel();
      else setRevision((value) => value + 1);
    } catch (cause) {
      setPending(
        (await store.read()).find((entry) => entry.scheduleId === scheduleId),
      );
      setError(
        cause instanceof Error ? cause.message : copy('schedules.saveFailed'),
      );
    } finally {
      running.current = false;
      setBusy(false);
    }
  }
  function confirm(action: 'run' | 'delete') {
    Alert.alert(
      copy(action === 'run' ? 'schedules.runNow' : 'schedules.deleteTitle'),
      copy(action === 'run' ? 'schedules.runHint' : 'schedules.deleteHint'),
      [
        { text: copy('common.cancel'), style: 'cancel' },
        {
          text: copy(
            action === 'run' ? 'schedules.runNow' : 'schedules.delete',
          ),
          style: action === 'delete' ? 'destructive' : 'default',
          onPress: () => void mutate(action),
        },
      ],
    );
  }
  const items = useMemo(
    () => [
      {
        type: 'button' as const,
        title: copy('schedules.edit'),
        accessibilityLabel: copy('schedules.edit'),
        disabled: !canEdit || busy || loading || !!pending,
        onPress: () => {
          if (!detail) return;
          void present(ScheduleEditorScreen, {
            workspaceId,
            userId,
            document: detail.document,
            service,
            pendingStore: store,
          }).then((result) => {
            if (result.status === 'completed')
              setRevision((value) => value + 1);
          });
        },
      },
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'arrow.clockwise' },
        accessibilityLabel: copy('schedules.refresh'),
        disabled: loading || busy,
        onPress: () => setRevision((value) => value + 1),
      },
    ],
    [
      canEdit,
      busy,
      loading,
      pending,
      detail,
      workspaceId,
      userId,
      service,
      store,
      present,
    ],
  );
  const sections: NativeListSection[] = [];
  if (error)
    sections.push({
      id: 'error',
      rows: [
        {
          id: 'schedule-detail-error',
          title: error,
          image: 'exclamationmark.triangle',
          imageTint: 'warning',
          wrapSubtitle: true,
        },
        { id: 'retry', title: copy('common.retry'), action: !busy },
      ],
    });
  if (detail && definition && context) {
    const agent = context.agents.find(
        (entry) => entry.id === definition.agent.agentConfigId,
      ),
      zone = scheduleDisplayTimeZone(definition.trigger, machine?.timeZone);
    sections.push({
      id: 'summary',
      rows: [
        {
          id: 'schedule-title',
          title: definition.title,
          subtitle: definition.enabled
            ? copy('schedules.status.active')
            : copy('schedules.status.paused'),
        },
        {
          id: 'prompt',
          title: copy('schedules.prompt'),
          subtitle: detail.document.prompt,
          wrapSubtitle: true,
        },
        {
          id: 'machine',
          title: copy('schedules.machine'),
          value: machine?.name ?? definition.machineId,
        },
        {
          id: 'agent',
          title: copy('schedules.agent'),
          value: agent?.name ?? definition.agent.agentConfigId,
        },
        {
          id: 'frequency',
          title: copy('schedules.frequency'),
          value: frequencyLabel(definition, zone),
        },
        { id: 'timezone', title: copy('schedules.timeZone'), value: zone },
        {
          id: 'destination',
          title: copy('schedules.destination'),
          value: copy(`schedules.destination.${definition.destination.kind}`),
        },
      ],
    });
    if (detail.runtime?.blockedCode)
      sections.push({
        id: 'blocked',
        footer: copy('schedules.blockedHint'),
        rows: [
          {
            id: 'schedule-blocked',
            title: copy('schedules.status.blocked'),
            wrapSubtitle: true,
            image: 'exclamationmark.triangle',
            imageTint: 'warning',
          },
        ],
      });
    const timing = detail.runtime?.nextScheduledAt
      ? [detail.runtime.nextScheduledAt]
      : detail.next;
    if (definition.enabled && timing.length)
      sections.push({
        id: 'next',
        header: copy('schedules.nextRuns'),
        rows: timing.map((ms, index) => ({
          id: `detail-next:${index}`,
          title: dateLabel(ms, zone),
        })),
      });
    let unavailable = '';
    if (!owned) unavailable = copy('schedules.ownerOnly');
    else if (!machine || machine.ownerId !== userId)
      unavailable = copy('schedules.ownedMachine');
    else if (!machine.supported) unavailable = copy('schedules.upgrade');
    else if (machine.state !== 'online')
      unavailable = copy('schedules.machineOffline');
    const toggle = definition.enabled ? 'pause' : 'resume';
    if (pending)
      sections.push({
        id: 'pending',
        footer: copy('schedules.pendingHint'),
        rows: [
          {
            id: 'pending-retry',
            title: copy('schedules.retryPending'),
            value: copy(`schedules.action.${pending.action}`),
            action: !busy,
          },
        ],
      });
    sections.push({
      id: 'actions',
      footer: unavailable || copy('schedules.runRequestedHint'),
      rows: [
        {
          id: 'run',
          title: copy('schedules.runNow'),
          image: 'play',
          action: !!canRun && !busy && !pending,
        },
        {
          id: toggle,
          title: copy(`schedules.action.${toggle}`),
          image: definition.enabled ? 'pause' : 'play.circle',
          action:
            !!owned && (definition.enabled || !!canRun) && !busy && !pending,
        },
        {
          id: 'delete',
          title: copy('schedules.delete'),
          image: 'trash',
          action: !!owned && !busy && !pending,
          destructive: true,
        },
      ],
    });
    sections.push({
      id: 'history',
      header: copy('schedules.history'),
      rows: history.map((session) => ({
        id: `schedule-history:${session.id}`,
        title: session.title || copy('schedules.openRun'),
        subtitle: `${sessionStatus(session.status)} · ${dateLabel(Date.parse(session.createdAt), zone)}`,
        action: true,
        disclosure: true,
        navigates: true,
      })),
      footer: history.length ? undefined : copy('schedules.noRuns'),
    });
  }
  return (
    <>
      <NativeNavigationHeader
        title={definition?.title ?? copy('schedules.title')}
        items={items}
      />
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        sections={sections}
        placeholder={loading ? copy('schedules.loading') : ''}
        refreshing={loading}
        onRefresh={() => setRevision((value) => value + 1)}
        onRowPress={({ nativeEvent: { id } }) => {
          if (id === 'retry') {
            setRevision((value) => value + 1);
            return;
          }
          if (id === 'run' || id === 'delete') {
            confirm(id);
            return;
          }
          if (id === 'pause' || id === 'resume') {
            void mutate(id);
            return;
          }
          if (id === 'pending-retry' && pending) {
            if ('draft' in pending) {
              void present(ScheduleEditorScreen, {
                workspaceId,
                userId,
                document: detail?.document,
                service,
                pending,
                pendingStore: store,
              }).then(() => setRevision((value) => value + 1));
            } else
              void mutate(
                pending.action as 'run' | 'pause' | 'resume' | 'delete',
              );
            return;
          }
          const session = history.find(
            (entry) => `schedule-history:${entry.id}` === id,
          );
          if (session) {
            if (openSession) openSession(session);
            else void requestOpenSessionFromPage(workspaceId, userId, session);
          }
        }}
      />
    </>
  );
}
function View() {
  const { params, cancel } = usePageRuntime<ScheduleDetailParams>(),
    { account } = useAuth(),
    { selected, catalog } = useCatalog();
  const workspaceId = params.workspaceId ?? selected?.id,
    userId = params.userId ?? account?.user.id;
  const valid =
    !!params.service || (!!workspaceId && workspaceId === selected?.id);
  useEffect(() => {
    if (!valid || !workspaceId || !userId) cancel();
  }, [valid, workspaceId, userId, cancel]);
  if (!valid || !workspaceId || !userId) return null;
  return (
    <ScheduleDetailView
      {...params}
      workspaceId={workspaceId}
      userId={userId}
      catalog={params.catalog ?? catalog}
    />
  );
}
export const ScheduleDetailScreen = definePage<ScheduleDetailParams>({
  id: 'schedule-detail',
  title: copy('schedules.title'),
  Component: View,
  parseRouteParams: ({ scheduleId }) => {
    if (typeof scheduleId !== 'string')
      throw new Error('Schedule id is required');
    return { scheduleId };
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
