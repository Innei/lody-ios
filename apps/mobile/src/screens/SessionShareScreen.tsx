import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  Share,
  View as Container,
  ActivityIndicator,
} from 'react-native';
import {
  NativeGroupedList,
  copyText,
  type NativeListSection,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePalette } from '@/lib/theme/palette';
import { AppText } from '@/ui/AppText';
import { t } from '@/lib/i18n';
import { sessionShareSource, type ShareSource } from '@/cloud/session-sharing';
import type {
  ShareAction,
  ShareState,
  ShareProgress,
} from '@/models/session-sharing';

export type SessionShareParams = {
  workspaceId: string;
  sessionId: string;
  source?: ShareSource;
};
let nextEditor = 0;
function View() {
  const { params, cancel } = usePageRuntime<SessionShareParams>();
  const source = params.source ?? sessionShareSource;
  const colors = usePalette();
  const [editorId] = useState(() => `ios-share-${Date.now()}-${++nextEditor}`);
  const [data, setData] = useState<ShareState | null>(null);
  const [selected, setSelected] = useState<string[]>([params.sessionId]);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState(false);
  const [notice, setNotice] = useState('');
  const [progress, setProgress] = useState<ShareProgress | null>(null);
  const alive = useRef(false);
  const running = useRef(false);
  const retryAction = useRef<ShareAction>('read');
  const request = (action: ShareAction) =>
    source.request({
      workspaceId: params.workspaceId,
      sessionId: params.sessionId,
      editorId,
      action,
      selected,
      omissionText: t('share.fileOmitted'),
    });
  async function run(action: ShareAction) {
    if (running.current) return;
    running.current = true;
    retryAction.current = action;
    setBusy(true);
    setError(false);
    setNotice('');
    try {
      const next = await request(action);
      if (!alive.current) return;
      if (action === 'publish' && next?.entry?.status !== 'active')
        throw new Error('share_not_published');
      setData(next);
      if (next) setSelected(next.selected);
      if (action === 'publish') {
        let message = t('share.published');
        if (next?.url) {
          try {
            copyText(next.url);
            message = t('share.publishedCopied');
          } catch {
            /* The published link remains available for manual copy. */
          }
        }
        setNotice(message);
      }
      if (action === 'reset') setNotice(t('share.resetDone'));
      if (action === 'revoke') setNotice(t('share.revoked'));
    } catch {
      if (alive.current) setError(true);
      // A failed response may follow a successful commit. Query before offering a retry.
      if (action !== 'read') {
        try {
          const next = await request('read');
          if (alive.current && next) {
            setData(next);
            if (next.pending) setSelected(next.selected);
          }
        } catch {
          /* Preserve the selection and visible failure. */
        }
      }
    } finally {
      running.current = false;
      if (alive.current) {
        setBusy(false);
        setProgress(null);
      }
    }
  }
  useEffect(() => {
    alive.current = true;
    const unsubscribe = source.subscribe((value) => {
      if (value.editorId === editorId && alive.current) setProgress(value);
    });
    void run('read');
    return () => {
      alive.current = false;
      unsubscribe();
      void source
        .request({
          workspaceId: params.workspaceId,
          sessionId: params.sessionId,
          editorId,
          action: 'close',
        })
        .catch(() => {});
    };
  }, [source, editorId, params.workspaceId, params.sessionId]);
  const header = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.done'),
        accessibilityLabel: t('common.done'),
        onPress: cancel,
      },
    ],
    [cancel],
  );
  useSheetHeader(header);
  const entry = data?.entry;
  const active = entry?.status === 'active';
  const canPublish =
    !!data && (!entry || entry.status === 'revoked' || !!entry.canManage);
  const children =
    data?.candidates.filter((s) => s.id !== params.sessionId) ?? [];
  const available = data?.candidates.map((s) => s.id) ?? [];
  const selectionAvailable = selected.every((id) => available.includes(id));
  const sections: NativeListSection[] = [];
  if (data) {
    sections.push({
      id: 'share-scope',
      header:
        data.candidates.find((s) => s.id === params.sessionId)?.title ||
        t('share.title'),
      footer: `${t('share.publicNotice')}\n${t('share.snapshotNotice')}\n${t('share.attachments')}`,
      rows: [
        {
          id: 'share-status',
          title: t(active ? 'share.shared' : 'share.private'),
          image: active ? 'link' : 'lock',
          imageTint: 'blue',
        },
      ],
    });
    if (children.length && canPublish)
      sections.push({
        id: 'share-children',
        rows: [
          {
            id: 'share-include-children',
            title: t('share.children', {
              count: Math.min(children.length, 31),
            }),
            toggle: selected.length > 1,
            action: !busy && !data.pending,
          },
        ],
        footer: children.length > 31 ? t('share.limit') : undefined,
      });
    if (data.url)
      sections.push({
        id: 'share-link',
        rows: [
          {
            id: 'share-copy',
            title: t('share.copy'),
            image: 'doc.on.doc',
            action: !busy,
          },
          {
            id: 'share-system',
            title: t('share.send'),
            image: 'square.and.arrow.up',
            action: !busy,
          },
        ],
      });
    if (active && !data.url)
      sections.push({
        id: 'share-key',
        rows: [{ id: 'share-key-missing', title: t('share.keyMissing') }],
      });
    if (canPublish)
      sections.push({
        id: 'share-publish-section',
        footer: active ? t('share.updateNotice') : undefined,
        rows: [
          {
            id: 'share-publish',
            title: t(data.pending ? 'common.retry' : 'share.publish'),
            action: !busy && selectionAvailable,
            ...(active && !data.pending ? { title: t('share.update') } : {}),
            image: 'arrow.up.doc',
          },
        ],
      });
    if (!selectionAvailable)
      sections.push({
        id: 'share-unavailable-section',
        rows: [
          { id: 'share-unavailable', title: t('share.sourceUnavailable') },
        ],
      });
    if (data.pending)
      sections.push({
        id: 'share-discard-section',
        rows: [
          { id: 'share-discard', title: t('share.discard'), action: !busy },
        ],
      });
    if (active) {
      const rows = [];
      if (entry.canManage)
        rows.push({
          id: 'share-reset',
          title: t('share.reset'),
          action: !busy,
          image: 'arrow.clockwise',
        });
      if (entry.canRevoke)
        rows.push({
          id: 'share-revoke',
          title: t('share.revoke'),
          action: !busy,
          destructive: true,
          image: 'link.badge.plus',
        });
      if (rows.length) sections.push({ id: 'share-manage', rows });
    }
  }
  if (notice)
    sections.unshift({
      id: 'share-notice',
      rows: [
        {
          id: 'share-notice-text',
          title: notice,
          image: 'checkmark.circle',
          imageTint: 'blue',
        },
      ],
    });
  if (error)
    sections.unshift({
      id: 'share-error',
      footer: t('share.failed'),
      rows: [
        {
          id: 'share-reload',
          title: t('common.retry'),
          action: !busy,
          image: 'arrow.clockwise',
        },
      ],
    });
  const confirm = (action: 'reset' | 'revoke') =>
    Alert.alert(t(`share.${action}`), t(`share.${action}Confirm`), [
      { text: t('common.cancel'), style: 'cancel' },
      {
        text: t(`share.${action}`),
        style: 'destructive',
        onPress: () => void run(action),
      },
    ]);
  return (
    <Container style={{ flex: 1, backgroundColor: colors.background }}>
      {busy ? (
        <Container style={{ padding: 24, gap: 12, alignItems: 'center' }}>
          <ActivityIndicator />
          <AppText testID="share-progress" accessibilityLiveRegion="polite">
            {progress
              ? t(`share.${progress.phase}`, { percent: progress.percent ?? 0 })
              : t('share.loading')}
          </AppText>
          {progress ? (
            <AppText variant="secondary">{t('share.keepOpen')}</AppText>
          ) : null}
        </Container>
      ) : null}
      <NativeGroupedList
        style={{ flex: 1 }}
        transparent
        sections={sections}
        onRowToggle={({ nativeEvent }) => {
          if (!busy && !data?.pending)
            setSelected(
              nativeEvent.value
                ? [params.sessionId, ...children.slice(0, 31).map((s) => s.id)]
                : [params.sessionId],
            );
        }}
        onRowPress={({ nativeEvent: { id } }) => {
          if (busy) return;
          if (id === 'share-publish') void run('publish');
          if (id === 'share-reload') void run(retryAction.current);
          if (id === 'share-discard') void run('discard');
          if (id === 'share-copy' && data?.url) {
            try {
              copyText(data.url);
              setNotice(t('share.copied'));
            } catch {
              setError(true);
            }
          }
          if (id === 'share-system' && data?.url)
            void Share.share({ url: data.url }).catch(() => setError(true));
          if (id === 'share-reset') confirm('reset');
          if (id === 'share-revoke') confirm('revoke');
        }}
      />
    </Container>
  );
}
export const SessionShareScreen = definePage<SessionShareParams>({
  id: 'session-share',
  title: t('share.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from a session');
  },
  presentation: { style: 'pageSheet', headerVariant: 'transparent' },
});
