import { useEffect, useMemo, useState } from 'react';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  type NativeListSection,
} from '@lody-ios/kit';
import type { Catalog } from '@lody/cloud-runtime/models/catalog';
import type {
  ScheduleContext,
  ScheduleList,
  ScheduleService,
} from '@lody/cloud-runtime/models/schedules';
import { previewSchedule } from '@lody/cloud-runtime/protocol/schedule-time';
import {
  copy,
  dateLabel,
  frequencyLabel,
  matchingScheduleRuntime,
  scheduleDisplayTimeZone,
  statusLabel,
} from '@/features/schedules/model';
import {
  pendingScheduleStore,
  type PendingScheduleStore,
  type ScheduleWrite,
} from '@/features/schedules/pending';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { requestSchedules } from '@/cloud/schedules';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import { ScheduleDetailScreen } from './ScheduleDetailScreen';
import { ScheduleEditorScreen } from './ScheduleEditorScreen';

export function SchedulesView({
  workspaceId,
  userId,
  service = requestSchedules,
  catalog,
  pendingStore,
}: {
  workspaceId: string;
  userId: string;
  service?: ScheduleService;
  catalog?: Catalog;
  pendingStore?: PendingScheduleStore;
}) {
  const { push, present } = usePageRuntime(),
    colors = usePalette();
  const store = useMemo(
    () => pendingStore ?? pendingScheduleStore(userId, workspaceId),
    [pendingStore, userId, workspaceId],
  );
  const [snapshot, setSnapshot] = useState<ScheduleList>(),
    [context, setContext] = useState<ScheduleContext>(),
    [pending, setPending] = useState<ScheduleWrite[]>([]),
    [loading, setLoading] = useState(true),
    [error, setError] = useState(''),
    [revision, setRevision] = useState(0),
    [query, setQuery] = useState('');
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError('');
    void Promise.all([
      service({ workspaceId, action: 'list' }),
      service({ workspaceId, action: 'context' }),
      store.read(),
    ])
      .then(([data, options, writes]) => {
        if (active) {
          setSnapshot(data as ScheduleList);
          setContext(options as ScheduleContext);
          setPending(writes);
          setLoading(false);
        }
      })
      .catch((cause) => {
        if (active) {
          setError(
            cause instanceof Error
              ? cause.message
              : copy('schedules.loadFailed'),
          );
          setLoading(false);
        }
      });
    return () => {
      active = false;
    };
  }, [workspaceId, service, store, revision]);
  const items = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'plus' },
        accessibilityLabel: copy('schedules.create'),
        identifier: 'schedule-create',
        disabled: loading || !context,
        onPress: () => {
          void present(ScheduleEditorScreen, {
            workspaceId,
            userId,
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
        disabled: loading,
        onPress: () => setRevision((value) => value + 1),
      },
    ],
    [loading, context, workspaceId, userId, service, store, present],
  );
  const sections: NativeListSection[] = [];
  if (error)
    sections.push({
      id: 'error',
      rows: [
        {
          id: 'schedule-list-error',
          title: error,
          image: 'exclamationmark.triangle',
          imageTint: 'warning',
          wrapSubtitle: true,
        },
        { id: 'retry', title: copy('common.retry'), action: true },
      ],
    });
  if (pending.length)
    sections.push({
      id: 'pending',
      header: copy('schedules.pendingTitle'),
      footer: copy('schedules.pendingHint'),
      rows: pending.map((request) => ({
        id: `pending:${request.scheduleId}`,
        title:
          'draft' in request
            ? request.draft.title
            : copy(`schedules.action.${request.action}`),
        subtitle: copy('schedules.retryPending'),
        action: true,
        disclosure: true,
        navigates: true,
      })),
    });
  const rows = (snapshot?.rows ?? []).filter((row) => {
    const machine = context?.machines.find(
        (entry) => entry.id === row.machineId,
      ),
      agent = context?.agents.find((entry) => entry.id === row.agentConfigId);
    return [
      row.title,
      machine?.name,
      agent?.name,
      frequencyLabel(
        row,
        scheduleDisplayTimeZone(row.trigger, machine?.timeZone),
      ),
    ]
      .join(' ')
      .toLocaleLowerCase()
      .includes(query.trim().toLocaleLowerCase());
  });
  if (snapshot && context)
    sections.push({
      id: 'schedules',
      rows: rows.map((row) => {
        const machine = context.machines.find(
            (entry) => entry.id === row.machineId,
          ),
          runtime = matchingScheduleRuntime(row, snapshot.runtimes),
          zone = scheduleDisplayTimeZone(row.trigger, machine?.timeZone);
        const next =
          runtime?.nextScheduledAt ??
          previewSchedule(row.trigger, row.activeFrom, Date.now(), 1)[0];
        const subtitle = [
          statusLabel(row, snapshot.runtimes),
          machine?.name ?? row.machineId,
          frequencyLabel(row, zone),
        ];
        if (row.enabled && next !== undefined)
          subtitle.push(
            copy('schedules.nextAt', { date: dateLabel(next, zone) }),
          );
        return {
          id: `schedule:${row.scheduleId}`,
          title: row.title,
          subtitle: subtitle.join(' · '),
          wrapSubtitle: true,
          image: 'calendar.badge.clock',
          imageTint: row.enabled ? 'blue' : 'secondary',
          action: true,
          disclosure: true,
          navigates: true,
        };
      }),
    });
  let placeholder = '';
  if (loading && !snapshot) placeholder = copy('schedules.loading');
  else if (!loading && !error && !rows.length)
    placeholder = copy(query ? 'schedules.noMatches' : 'schedules.empty');
  return (
    <>
      <NativeNavigationHeader title={copy('schedules.title')} items={items} />
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        sections={sections}
        searchPlaceholder={copy('schedules.search')}
        onSearchChange={({ nativeEvent }) => setQuery(nativeEvent.text)}
        placeholder={placeholder}
        refreshing={loading}
        onRefresh={() => setRevision((value) => value + 1)}
        onRowPress={({ nativeEvent: { id } }) => {
          if (id === 'retry') {
            setRevision((value) => value + 1);
            return;
          }
          const write = pending.find(
            (entry) => `pending:${entry.scheduleId}` === id,
          );
          if (write && 'draft' in write) {
            void present(ScheduleEditorScreen, {
              workspaceId,
              userId,
              service,
              pending: write,
              pendingStore: store,
            }).then(() => setRevision((value) => value + 1));
            return;
          }
          const scheduleId =
            write?.scheduleId ??
            rows.find((entry) => `schedule:${entry.scheduleId}` === id)
              ?.scheduleId;
          if (scheduleId)
            void push(ScheduleDetailScreen, {
              scheduleId,
              workspaceId,
              userId,
              service,
              catalog,
              pendingStore: store,
            }).then(() => setRevision((value) => value + 1));
        }}
      />
    </>
  );
}
function View() {
  const { account } = useAuth(),
    { selected, catalog } = useCatalog(),
    { cancel } = usePageRuntime();
  useEffect(() => {
    if (!account || !selected) cancel();
  }, [account, selected, cancel]);
  if (!account || !selected) return null;
  return (
    <SchedulesView
      key={selected.id}
      workspaceId={selected.id}
      userId={account.user.id}
      catalog={catalog}
    />
  );
}
export const SchedulesScreen = definePage({
  id: 'schedules',
  title: copy('schedules.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
