import { useEffect, useMemo, useRef, useState } from 'react';
import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import type { Session } from '@lody/cloud-runtime/models/catalog';
import type {
  SessionForkResult,
  SessionToolsResult,
} from '@lody/cloud-runtime/models/session-tools';
import {
  requestSessionTools,
  type SessionToolsSource,
} from '@/cloud/session-tools';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { showToast } from '@/ui/toast';

export type ForkSessionParams = {
  workspaceId: string;
  userId: string;
  session: Session;
  sourceTurnId: string;
  source?: SessionToolsSource;
};
export type ForkSessionCompleted = { targetSessionId: string };

function View() {
  const { params, cancel, finish } = usePageRuntime<
    ForkSessionParams,
    ForkSessionCompleted
  >();
  const source = params.source ?? requestSessionTools;
  const colors = usePalette();
  const [options, setOptions] =
    useState<Extract<SessionToolsResult, { action: 'fork-options' }>>();
  const [destination, setDestination] = useState<'shared' | 'new-worktree'>(
    'shared',
  );
  const [result, setResult] = useState<SessionForkResult>();
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [loadFailed, setLoadFailed] = useState(false);
  const alive = useRef(false);
  const running = useRef(false);
  const target = useRef('');
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const scope = {
    workspaceId: params.workspaceId,
    sessionId: params.session.id,
  };
  async function load() {
    setLoading(true);
    setLoadFailed(false);
    try {
      const next = await source({ ...scope, action: 'fork-options' });
      if (!alive.current || next.action !== 'fork-options') return;
      setOptions(next);
      target.current = next.targetSessionId;
      return next;
    } catch {
      if (alive.current) setLoadFailed(true);
    } finally {
      if (alive.current) setLoading(false);
    }
  }
  function apply(next: SessionForkResult) {
    if (!alive.current) return;
    setResult(next);
    if (next.state === 'completed') {
      if (next.partial) showToast(t('session.fork.partial'), 'info');
      finish({ targetSessionId: next.targetSessionId });
    } else if (next.state === 'preparing') {
      timer.current = setTimeout(() => void check(), 2500);
    }
  }
  async function check() {
    if (running.current || !target.current || !alive.current) return;
    running.current = true;
    setBusy(true);
    clearTimeout(timer.current);
    try {
      const next = await source({
        ...scope,
        action: 'fork-status',
        targetSessionId: target.current,
      });
      if (next.action === 'fork-status') apply(next.fork);
    } catch {
      apply({ state: 'unknown', targetSessionId: target.current });
    } finally {
      running.current = false;
      if (alive.current) setBusy(false);
    }
  }
  async function start(acknowledgeDirtySource = false) {
    if (running.current || !alive.current) return;
    running.current = true;
    setBusy(true);
    clearTimeout(timer.current);
    try {
      if (result?.state === 'failed' && !acknowledgeDirtySource) {
        if (!(await load())) return;
      }
      if (!target.current || !alive.current) return;
      const next = await source({
        ...scope,
        action: 'fork',
        spec: {
          sourceSessionId: params.session.id,
          sourceTurnId: params.sourceTurnId,
          targetSessionId: target.current,
          requestedByUserId: params.userId,
          targetContext: {
            kind: destination,
            ...(acknowledgeDirtySource
              ? { acknowledgeDirtySource: true as const }
              : {}),
          },
        },
      });
      if (next.action === 'fork') apply(next.fork);
    } catch {
      apply({ state: 'unknown', targetSessionId: target.current });
    } finally {
      running.current = false;
      if (alive.current) setBusy(false);
    }
  }
  useEffect(() => {
    alive.current = true;
    void load();
    return () => {
      alive.current = false;
      clearTimeout(timer.current);
    };
  }, [source, params.workspaceId, params.session.id]);
  const header = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.cancel'),
        accessibilityLabel: t('common.cancel'),
        onPress: cancel,
      },
    ],
    [cancel],
  );
  useSheetHeader(header);
  const waiting = result?.state === 'preparing';
  const uncertain = result?.state === 'unknown';
  const failed = result?.state === 'failed';
  const confirmation = result?.state === 'confirmation-required';
  const choosing = !result || failed;
  const sections: NativeListSection[] = [
    {
      id: 'fork-source',
      header: t('session.fork.source'),
      rows: [
        {
          id: 'fork-source-session',
          title: params.session.title,
          image: 'text.bubble',
        },
      ],
    },
  ];
  if (loading)
    sections.push({
      id: 'fork-loading',
      rows: [{ id: 'fork-loading', title: t('common.loading') }],
    });
  if (busy && !waiting && !uncertain)
    sections.push({
      id: 'fork-requesting',
      rows: [{ id: 'fork-requesting', title: t('session.fork.requesting') }],
    });
  if (choosing && options?.shared && !params.session.archived) {
    const rows = [
      {
        id: 'fork-shared',
        title: t('session.fork.shared'),
        subtitle: t('session.fork.sharedHint'),
        action: !busy,
        selected: destination === 'shared',
      },
    ];
    if (options.newWorktree)
      rows.push({
        id: 'fork-worktree',
        title: t('session.fork.worktree'),
        subtitle: t('session.fork.worktreeHint'),
        action: !busy,
        selected: destination === 'new-worktree',
      });
    sections.push({
      id: 'fork-destination',
      header: t('session.fork.destination'),
      rows,
    });
    sections.push({
      id: 'fork-send',
      rows: [
        {
          id: 'fork-start',
          title: t('session.fork.start'),
          image: 'arrow.triangle.branch',
          action: !busy,
          imageTint: 'blue',
        },
      ],
    });
  }
  if (waiting || uncertain || failed || confirmation || loadFailed) {
    let title = t('session.fork.failed');
    let subtitle = result?.message;
    if (waiting) {
      title = t('session.fork.preparing');
      subtitle = t('session.fork.waitHint');
    } else if (uncertain) {
      title = t('session.fork.unknown');
      subtitle = t('session.fork.unknownHint');
    } else if (confirmation) {
      title = t('session.fork.dirty');
      subtitle = t('session.fork.dirtyHint');
    }
    const rows: NativeListSection['rows'] = [
      { id: 'fork-state', title, subtitle, wrapSubtitle: true },
    ];
    if (waiting || uncertain)
      rows.push({
        id: 'fork-check',
        title: t('session.fork.check'),
        action: !busy,
        image: 'arrow.clockwise',
      });
    if (confirmation)
      rows.push({
        id: 'fork-confirm',
        title: t('session.fork.confirm'),
        action: !busy,
        image: 'arrow.triangle.branch',
      });
    if (loadFailed)
      rows.push({ id: 'fork-reload', title: t('common.retry'), action: !busy });
    sections.push({ id: 'fork-progress', rows });
  }
  if (!loading && !loadFailed && (!options?.shared || params.session.archived))
    sections.push({
      id: 'fork-unavailable',
      rows: [
        {
          id: 'fork-unavailable',
          title: t('session.fork.unavailable'),
          wrapSubtitle: true,
        },
      ],
    });
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      placeholder={loading ? t('common.loading') : ''}
      onRowPress={({ nativeEvent: { id } }) => {
        if (busy) return;
        if (id === 'fork-shared') setDestination('shared');
        if (id === 'fork-worktree') setDestination('new-worktree');
        if (id === 'fork-start') void start();
        if (id === 'fork-confirm') void start(true);
        if (id === 'fork-check') void check();
        if (id === 'fork-reload') void load();
      }}
    />
  );
}

export const ForkSessionScreen = definePage<
  ForkSessionParams,
  ForkSessionCompleted
>({
  id: 'fork-session',
  title: t('session.fork.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from a session');
  },
  presentation: { style: 'pageSheet', headerVariant: 'transparent' },
});
