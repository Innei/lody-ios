import { Stack } from 'expo-router';
import { agentName } from '@/features/sessions/status';
import { relativeTime } from '@/ui/time';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, PlatformColor } from 'react-native';
import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import {
  cancelProjectHistory,
  requestProjectHistory,
} from '@/cloud/project-history';
import { definePage } from '@/lib/presentation';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import type {
  HistoryRequest,
  HistoryResult,
  HistoryService,
  HistoryTarget,
} from '@/models/project-history';
import { t, tp } from '../lib/i18n/index.ts';

type Params = {
  workspaceId: string;
  target?: HistoryTarget;
  project?: HistoryTarget;
  service?: HistoryService;
};
const targetId = (target: HistoryTarget) =>
  JSON.stringify([
    target.machineId,
    target.localProjectId,
    target.provider.cliType,
    target.provider.agentType,
  ]);

export function ProjectHistoryView({
  workspaceId,
  target,
  project,
  service,
}: Params) {
  const { push } = usePageRuntime();
  const [browserId] = useState(() => `history-${Date.now()}-${Math.random()}`);
  const alive = useRef(false),
    locked = useRef(false);
  const [busy, setBusy] = useState(true);
  const [operation, setOperation] = useState<'load' | 'import' | 'resolve'>(
    'load',
  );
  const [targets, setTargets] = useState<HistoryTarget[]>([]);
  const [result, setResult] = useState<HistoryResult | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const call = useCallback(
    (request: HistoryRequest) =>
      service
        ? service(request)
        : requestProjectHistory(workspaceId, browserId, request),
    [service, workspaceId, browserId],
  );

  const run = useCallback(
    async (
      work: () => Promise<void>,
      kind: 'load' | 'import' | 'resolve' = 'load',
    ) => {
      if (locked.current || !alive.current) return;
      locked.current = true;
      setOperation(kind);
      setBusy(true);
      setError('');
      setNotice('');
      try {
        await work();
      } catch (cause) {
        if (alive.current)
          setError(
            cause instanceof Error
              ? cause.message
              : t('settings.history.loadFailed'),
          );
      } finally {
        locked.current = false;
        if (alive.current) setBusy(false);
      }
    },
    [],
  );
  const load = useCallback(
    () =>
      run(async () => {
        const value = await call(
          target ? { kind: 'sync', target } : { kind: 'targets' },
        );
        if (!alive.current) return;
        if (Array.isArray(value)) setTargets(value);
        else {
          setResult(value);
          setSelected(new Set());
        }
      }),
    [call, target, run],
  );
  const headerItems = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'arrow.clockwise' },
        accessibilityLabel: t('settings.history.sync'),
        tintColor: PlatformColor('systemBlue'),
        disabled: busy,
        onPress: () => void load(),
      },
    ],
    [busy, load],
  );
  useSheetHeader(headerItems);
  useEffect(() => {
    alive.current = true;
    void load();
    return () => {
      alive.current = false;
      if (!service) cancelProjectHistory(workspaceId, browserId);
    };
  }, []);

  const importSelected = () =>
    run(async () => {
      if (!target) return;
      const ids = [...selected];
      const failures: NonNullable<HistoryResult['failures']> = [];
      for (let start = 0; start < ids.length; start += 5) {
        if (!alive.current) return;
        const batch = ids.slice(start, start + 5);
        const value = await call({
          kind: 'import',
          target,
          acpSessionIds: batch,
        });
        if (!alive.current) return;
        if (Array.isArray(value))
          throw new Error(t('settings.history.writeFailed'));
        setResult(value);
        failures.push(...(value.failures ?? []));
        const failed = new Set(failures.map((item) => item.acpSessionId));
        setSelected(
          (current) =>
            new Set(
              [...current].filter(
                (id) => !batch.includes(id) || failed.has(id),
              ),
            ),
        );
        setNotice(
          t('settings.history.progress', {
            done: Math.min(start + 5, ids.length),
            total: ids.length,
          }),
        );
      }
      if (failures.length)
        setError(
          tp('settings.history.partialFailure', failures.length, {
            count: failures.length,
          }),
        );
    }, 'import');
  function resolve(acpSessionId: string) {
    const session = result?.sessions.find(
      (item) => item.acpSessionId === acpSessionId,
    );
    if (!target || !session?.importedSessionId || locked.current) return;
    const sessionId = session.importedSessionId;
    Alert.alert(
      t('settings.history.replaceTitle'),
      t('settings.history.replaceHint'),
      [
        { text: t('common.cancel'), style: 'cancel' },
        {
          text: t('settings.history.replace'),
          style: 'destructive',
          onPress: () =>
            void run(async () => {
              const value = await call({
                kind: 'resolve',
                target,
                acpSessionId,
                sessionId,
              });
              if (!alive.current) return;
              if (Array.isArray(value))
                throw new Error(t('settings.history.writeFailed'));
              setResult(value);
              setNotice(t('settings.history.resolved'));
            }, 'resolve'),
        },
      ],
    );
  }

  const available =
    result?.sessions.filter(
      (item) => item.status !== 'imported' && item.status !== 'sync_conflict',
    ) ?? [];
  const allSelected =
    available.length > 0 &&
    available.every((item) => selected.has(item.acpSessionId));
  const loadingText = t(
    target
      ? 'settings.history.loadingSessions'
      : 'settings.history.loadingProjects',
  );
  const busyText = {
    load: loadingText,
    import: t('settings.history.importing'),
    resolve: t('settings.history.replacing'),
  }[operation];
  const sections: NativeListSection[] = [];
  if (target) {
    sections.push({
      id: 'history-info',
      header: target.projectName,
      footer: [
        target.machineName,
        target.rootPath,
        busy ? busyText : notice,
        error,
      ]
        .filter(Boolean)
        .join('\n'),
      rows: [],
    });
    let sessionFooter: string | undefined;
    if (!busy && !error && result) {
      sessionFooter = t(
        result.sessions.length
          ? 'settings.history.importHint'
          : 'settings.history.emptySessions',
      );
    }
    sections.push({
      id: 'history-sessions',
      footer: sessionFooter,
      rows: (result?.sessions ?? []).map((session) => {
        let value = selected.has(session.acpSessionId)
          ? t('settings.history.selected')
          : undefined;
        if (session.status === 'imported')
          value = t('settings.history.imported');
        if (session.status === 'sync_conflict')
          value = t('settings.history.conflict');
        return {
          id: `history-session:${session.acpSessionId}`,
          title: session.title || t('settings.history.untitled'),
          subtitle: session.updatedAt
            ? relativeTime(session.updatedAt)
            : undefined,
          value,
          image: selected.has(session.acpSessionId)
            ? 'checkmark.circle.fill'
            : 'bubble.left.and.bubble.right',
          imageTint: 'blue',
          action: !busy && session.status !== 'imported',
        };
      }),
    });
  } else {
    if (!project || busy || error)
      sections.push({
        id: 'history-help',
        footer: error || (busy ? busyText : t('settings.history.hint')),
        rows: [],
      });
    if (project) {
      const agents = targets.filter(
        (item) =>
          item.machineId === project.machineId &&
          item.localProjectId === project.localProjectId,
      );
      sections.push({
        id: 'history-agents',
        header: t('settings.history.chooseAgent'),
        footer: `${project.machineName}\n${project.rootPath}`,
        rows: agents.map((item) => ({
          id: `history-target:${targetId(item)}`,
          title: agentName(item.provider.agentType),
          subtitle: t(`settings.history.provider.${item.provider.cliType}`),
          image: 'bubble.left.and.bubble.right',
          imageTint: 'blue',
          disclosure: true,
          navigates: true,
          action: !busy,
        })),
      });
    } else {
      const machines = new Map<string, Map<string, HistoryTarget[]>>();
      for (const item of targets) {
        const projects =
          machines.get(item.machineId) ?? new Map<string, HistoryTarget[]>();
        const agents = projects.get(item.localProjectId) ?? [];
        agents.push(item);
        projects.set(item.localProjectId, agents);
        machines.set(item.machineId, projects);
      }
      for (const [machineId, projects] of machines) {
        const groups = [...projects.values()].sort((a, b) =>
          a[0].projectName.localeCompare(b[0].projectName),
        );
        sections.push({
          id: machineId,
          header: groups[0][0].machineName,
          rows: groups.map((agents) => {
            const item = agents[0];
            return {
              id: `history-project:${JSON.stringify([item.machineId, item.localProjectId])}`,
              title: item.projectName,
              subtitle: item.rootPath,
              value: tp('settings.history.agentCount', agents.length, {
                count: agents.length,
              }),
              image: 'folder',
              imageTint: 'blue',
              disclosure: true,
              navigates: true,
              action: !busy,
            };
          }),
        });
      }
    }
    if (!busy && !error && !targets.length)
      sections.push({
        id: 'history-empty',
        footer: t('settings.history.emptyTargets'),
        rows: [],
      });
  }
  return (
    <>
      {target ? (
        <Stack.Toolbar placement="bottom">
          <Stack.Toolbar.Button
            tintColor={PlatformColor('systemBlue')}
            disabled={busy || available.length === 0}
            onPress={() => {
              if (locked.current) return;
              setSelected(
                allSelected
                  ? new Set()
                  : new Set(available.map((item) => item.acpSessionId)),
              );
            }}
          >
            {t(
              allSelected
                ? 'settings.history.deselectAll'
                : 'settings.history.selectAll',
            )}
          </Stack.Toolbar.Button>
          <Stack.Toolbar.Spacer />
          <Stack.Toolbar.Button
            variant="prominent"
            tintColor={PlatformColor('systemBlue')}
            disabled={busy || selected.size === 0}
            onPress={() => void importSelected()}
          >
            {t('settings.history.import', { count: selected.size })}
          </Stack.Toolbar.Button>
        </Stack.Toolbar>
      ) : null}
      <NativeGroupedList
        style={{ flex: 1 }}
        sections={sections}
        refreshing={busy && operation === 'load'}
        onRefresh={() => void load()}
        onRowPress={({ nativeEvent: { id } }) => {
          if (busy || locked.current) return;
          const nextProject = targets.find(
            (item) =>
              `history-project:${JSON.stringify([item.machineId, item.localProjectId])}` ===
              id,
          );
          if (nextProject) {
            void push(
              ProjectHistoryDetailScreen,
              { workspaceId, project: nextProject, service },
              { title: nextProject.projectName },
            );
            return;
          }
          const next = targets.find(
            (item) => `history-target:${targetId(item)}` === id,
          );
          if (next) {
            void push(
              ProjectHistoryDetailScreen,
              { workspaceId, target: next, service },
              { title: agentName(next.provider.agentType) },
            );
            return;
          }
          const session = result?.sessions.find(
            (item) => `history-session:${item.acpSessionId}` === id,
          );
          if (!session || session.status === 'imported') return;
          if (session.status === 'sync_conflict') {
            resolve(session.acpSessionId);
            return;
          }
          setSelected((current) => {
            const next = new Set(current);
            if (next.has(session.acpSessionId))
              next.delete(session.acpSessionId);
            else next.add(session.acpSessionId);
            return next;
          });
        }}
      />
    </>
  );
}

const ProjectHistoryDetailScreen = definePage<Params>({
  id: 'project-history-detail',
  title: t('settings.history.title'),
  Component: () => {
    const { params, cancel } = usePageRuntime<Params>();
    const { selected } = useCatalog();
    const valid = !!params.service || selected?.id === params.workspaceId;
    useEffect(() => {
      if (!valid) cancel();
    }, [valid, cancel]);
    if (!valid) return null;
    return <ProjectHistoryView key={params.workspaceId} {...params} />;
  },
  parseRouteParams: () => {
    throw new Error('Open from project history');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
export const ProjectHistoryScreen = definePage({
  id: 'project-history',
  title: t('settings.history.title'),
  Component: () => {
    const { selected } = useCatalog();
    const { cancel } = usePageRuntime();
    useEffect(() => {
      if (!selected) cancel();
    }, [selected, cancel]);
    if (!selected) return null;
    return <ProjectHistoryView key={selected.id} workspaceId={selected.id} />;
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
