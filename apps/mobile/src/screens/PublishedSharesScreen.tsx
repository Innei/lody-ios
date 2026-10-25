import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert } from 'react-native';
import {
  NativeGroupedList,
  type NativeListSection,
  type NativeGroupedListProps,
} from '@lody-ios/kit';
import type {
  PublishedShare,
  PublishedSharePage,
} from '@lody/cloud-runtime/models/session-sharing';
import {
  requestPublishedShares,
  type PublishedSharesService,
} from '@/cloud/published-shares';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import { listState } from '@/features/settings/list-state';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';

const title = (entry: PublishedShare) =>
  entry.title || t('settings.shares.untitled');
const date = (value: number) => new Date(value).toLocaleString();
function errorText(cause: unknown) {
  const text = String(cause);
  for (const code of [
    'forbidden',
    'conflict',
    'write_unknown',
    'link_unavailable',
    'link_failed',
  ] as const)
    if (text.includes('shares_' + code))
      return t(`settings.shares.error.${code}`);
  return t('settings.shares.error.unavailable');
}
type DetailParams = {
  workspaceId: string;
  entry: PublishedShare;
  service: PublishedSharesService;
  actorScope: string;
};
function Detail() {
  const { params, cancel } = usePageRuntime<DetailParams>();
  const { account } = useAuth();
  const { selected } = useCatalog();
  const valid =
    params.actorScope === (account?.user.id ?? '') + ':' + (selected?.id ?? '');
  const active = useRef(valid);
  active.current = valid;
  const guard = useRef(false);
  const [entry, setEntry] = useState<PublishedShare>();
  const [busy, setBusy] = useState(true),
    [failure, setFailure] = useState(''),
    [notice, setNotice] = useState('');
  const [blocked, setBlocked] = useState(false);
  const colors = usePalette();
  const run = useCallback(
    async (action: 'detail' | 'copy' | 'open' | 'revoke') => {
      if (guard.current || !active.current || (action !== 'detail' && blocked))
        return;
      guard.current = true;
      setBusy(true);
      setNotice('');
      try {
        const result = await params.service({
          workspaceId: params.workspaceId,
          action,
          shareId: params.entry.shareId,
          rootSessionId: params.entry.rootSessionId,
          expectedRevision: entry?.revision,
        });
        if (!active.current) return;
        if (result.userId !== account?.user.id || !result.page[0])
          throw new Error('shares_scope_changed');
        setEntry(result.page[0]);
        setFailure('');
        setBlocked(false);
        if (action === 'copy') setNotice(t('settings.shares.copied'));
        if (action === 'revoke') setNotice(t('settings.shares.revoked'));
      } catch (cause) {
        if (active.current) {
          let message = errorText(cause);
          if (action === 'revoke' && !String(cause).includes('shares_'))
            message = t('settings.shares.error.write_unknown');
          setFailure(message);
          setBlocked(true);
          if (String(cause).includes('shares_forbidden')) setEntry(undefined);
        }
      } finally {
        guard.current = false;
        if (active.current) setBusy(false);
      }
    },
    [params, account?.user.id, entry?.revision, blocked],
  );
  useEffect(() => {
    active.current = valid;
    void run('detail');
    return () => {
      active.current = false;
    };
    // Read once per presentation; later reads are explicit refreshes.
  }, []);
  useEffect(() => {
    if (!valid) cancel();
  }, [valid, cancel]);
  if (!valid) return null;
  const unavailable =
    !busy && !entry
      ? {
          title: t('settings.shares.unavailable'),
          message: failure || t('settings.shares.error.unavailable'),
          symbol: 'wifi.exclamationmark',
          actionTitle: t('settings.state.tryAgain'),
        }
      : undefined;
  let feedback: NativeGroupedListProps['notice'];
  if (failure && !unavailable)
    feedback = {
      symbol: 'exclamationmark.triangle',
      text: failure,
      tint: 'warning',
      actionLabel: t('settings.state.refresh'),
      actionSymbol: 'arrow.clockwise',
    };
  else if (notice) feedback = { symbol: 'checkmark.circle', text: notice };
  const sections: NativeListSection[] = [];
  if (entry) {
    const rows: NativeListSection['rows'] = [
      {
        id: 'share-title',
        title: title(entry),
        subtitle: entry.shareId,
        wrapSubtitle: true,
      },
      {
        id: 'share-status',
        title: t(`settings.shares.status.${entry.status}`),
        subtitle: blocked ? t('settings.shares.lastConfirmed') : undefined,
        wrapSubtitle: true,
      },
      {
        id: 'share-publisher',
        title: t('settings.shares.publisher'),
        subtitle: entry.publisherUserId,
        wrapSubtitle: true,
      },
      {
        id: 'share-created',
        title: t('settings.shares.created'),
        subtitle: date(entry.createdAt),
      },
      {
        id: 'share-updated',
        title: t('settings.shares.updated'),
        subtitle: date(entry.updatedAt),
      },
      {
        id: 'share-source',
        title: t('settings.shares.source'),
        subtitle: entry.rootSessionId,
        wrapSubtitle: true,
      },
    ];
    sections.push({ id: 'details', footer: t('settings.shares.static'), rows });
    let linkHint = t('settings.shares.linkRevoked');
    if (entry.status === 'active')
      linkHint =
        entry.publisherUserId === account?.user.id
          ? t('settings.shares.linkMissing')
          : t('settings.shares.linkOtherPublisher');
    if (entry.hasLocalLink && entry.status === 'active')
      sections.push({
        id: 'link',
        rows: [
          {
            id: 'share-open',
            title: t('settings.shares.open'),
            action: !busy && !blocked,
            image: 'safari',
          },
          {
            id: 'share-copy',
            title: t('settings.shares.copy'),
            action: !busy && !blocked,
            image: 'doc.on.doc',
          },
        ],
      });
    else sections.push({ id: 'link', footer: linkHint, rows: [] });
    if (entry.status === 'active' && entry.canRevoke)
      sections.push({
        id: 'revoke',
        footer: t('settings.shares.revokeHint'),
        rows: [
          {
            id: 'share-revoke',
            title: t('settings.shares.revoke'),
            action: !busy && !blocked,
            destructive: true,
          },
        ],
      });
  }
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      loading={busy && !entry}
      unavailable={unavailable}
      onUnavailableAction={() => void run('detail')}
      notice={feedback}
      placeholder=""
      refreshing={busy && !!entry}
      onRefresh={() => void run('detail')}
      onNoticeAction={() => void run('detail')}
      onRowPress={({ nativeEvent: { id } }) => {
        if (!entry || busy || blocked) return;
        if (id === 'share-copy') void run('copy');
        if (id === 'share-open') void run('open');
        if (id === 'share-revoke')
          Alert.alert(
            t('settings.shares.revoke'),
            t('settings.shares.revokeConfirm'),
            [
              { text: t('common.cancel'), style: 'cancel' },
              {
                text: t('settings.shares.revoke'),
                style: 'destructive',
                onPress: () => void run('revoke'),
              },
            ],
          );
      }}
    />
  );
}
const PublishedShareDetailScreen = definePage<DetailParams>({
  id: 'published-share-detail',
  title: t('settings.shares.details'),
  Component: Detail,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

export function PublishedSharesView({
  workspaceId,
  service = requestPublishedShares,
}: {
  workspaceId: string;
  service?: PublishedSharesService;
}) {
  const { account } = useAuth();
  const { selected } = useCatalog();
  const { push } = usePageRuntime();
  const actorScope = (account?.user.id ?? '') + ':' + (selected?.id ?? '');
  const [snapshot, setSnapshot] = useState<PublishedSharePage>();
  const [history, setHistory] = useState<(string | null)[]>([null]);
  const [busy, setBusy] = useState(true),
    [failed, setFailed] = useState(false),
    [failure, setFailure] = useState('');
  const [syncedAt, setSyncedAt] = useState<number>();
  const generation = useRef(0);
  const retry = useRef<(string | null)[]>([null]);
  const colors = usePalette();
  const load = useCallback(
    async (cursors: (string | null)[]) => {
      const version = ++generation.current;
      retry.current = cursors;
      setBusy(true);
      setFailed(false);
      try {
        const result = await service({
          workspaceId,
          action: 'list',
          cursor: cursors.at(-1),
        });
        if (version !== generation.current) return;
        if (result.userId !== account?.user.id)
          throw new Error('shares_scope_changed');
        if (!result.isDone && cursors.includes(result.continueCursor))
          throw new Error('shares_cursor_stalled');
        setSnapshot(result);
        setHistory(cursors);
        setSyncedAt(Date.now());
        setFailure('');
      } catch (cause) {
        if (version === generation.current) {
          setFailed(true);
          setFailure(errorText(cause));
          if (String(cause).includes('shares_forbidden'))
            setSnapshot(undefined);
        }
      } finally {
        if (version === generation.current) setBusy(false);
      }
    },
    [workspaceId, service, account?.user.id],
  );
  useEffect(() => {
    void load([null]);
    return () => {
      generation.current++;
    };
  }, [load]);
  const state = listState({
    title: t('settings.shares.unavailable'),
    hasData: !!snapshot,
    loading: busy,
    failed,
    syncedAt,
  });
  let feedback = state.notice;
  if (feedback && failure) {
    let text = failure;
    if (snapshot && retry.current.at(-1) !== history.at(-1))
      text = t('settings.shares.pageFailed');
    feedback = { ...feedback, text };
  }
  const sections: NativeListSection[] = [];
  if (snapshot) {
    sections.push({
      id: 'shares',
      header: t('settings.shares.title'),
      footer: t('settings.shares.scope'),
      rows: snapshot.page.length
        ? snapshot.page.map((entry) => ({
            id: 'share:' + entry.shareId,
            title: title(entry),
            subtitle: [
              t(`settings.shares.status.${entry.status}`),
              entry.publisherUserId,
              date(entry.createdAt),
              t('settings.shares.summary', {
                count: entry.conversationCount ?? 0,
                size: Math.ceil((entry.totalBytes ?? 0) / 1024),
              }),
            ].join(' · '),
            wrapSubtitle: true,
            action: !busy && !failed,
            disclosure: true,
            navigates: true,
          }))
        : [{ id: 'shares-empty', title: t('settings.shares.empty') }],
    });
    if (history.length > 1 || !snapshot.isDone) {
      const rows: NativeListSection['rows'] = [];
      if (history.length > 1)
        rows.push({
          id: 'shares-previous',
          title: t('settings.shares.previous'),
          action: !busy,
        });
      if (!snapshot.isDone)
        rows.push({
          id: 'shares-next',
          title: t('settings.shares.next'),
          action: !busy,
        });
      sections.push({
        id: 'pagination',
        footer: t('settings.shares.page', { page: history.length }),
        rows,
      });
    }
    sections.push({
      id: 'static',
      footer: t('settings.shares.static'),
      rows: [],
    });
  }
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      loading={state.loading}
      unavailable={
        state.unavailable && {
          ...state.unavailable,
          message: failure || state.unavailable.message,
        }
      }
      notice={feedback}
      onNoticeAction={() => void load(retry.current)}
      onUnavailableAction={() => void load(retry.current)}
      refreshing={busy && !!snapshot}
      onRefresh={() => void load(history)}
      onRowPress={({ nativeEvent: { id } }) => {
        if (busy || !snapshot) return;
        if (id === 'shares-next' && !snapshot.isDone)
          void load([...history, snapshot.continueCursor]);
        if (id === 'shares-previous' && history.length > 1)
          void load(history.slice(0, -1));
        const entry = snapshot.page.find(
          (row) => 'share:' + row.shareId === id,
        );
        if (!entry || failed) return;
        const version = generation.current;
        void push(PublishedShareDetailScreen, {
          workspaceId,
          entry,
          service,
          actorScope,
        }).then(() => {
          if (version === generation.current) void load(history);
        });
      }}
    />
  );
}
function View() {
  const { account } = useAuth();
  const { selected } = useCatalog();
  if (!account || !selected) return null;
  return (
    <PublishedSharesView
      key={account.user.id + ':' + selected.id}
      workspaceId={selected.id}
    />
  );
}
export const PublishedSharesScreen = definePage({
  id: 'published-shares',
  title: t('settings.shares.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
