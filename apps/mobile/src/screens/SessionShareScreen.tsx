import { useEffect, useMemo, useRef, useState } from 'react';
import { Share } from 'react-native';
import { NativeSessionShare, copyText } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
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
        disabled: busy && !!data,
      },
    ],
    [cancel, busy, !!data],
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
  let progressText = t('share.loading');
  if (progress)
    progressText = t(`share.${progress.phase}`, {
      percent: progress.percent ?? 0,
    });
  const strings = Object.fromEntries(
    (
      [
        'shared',
        'private',
        'publicNotice',
        'snapshotNotice',
        'attachments',
        'limit',
        'copy',
        'send',
        'keyMissing',
        'publish',
        'update',
        'updateNotice',
        'sourceUnavailable',
        'discard',
        'reset',
        'revoke',
        'resetConfirm',
        'revokeConfirm',
        'failed',
        'keepOpen',
        'content',
        'manage',
      ] as const
    ).map((key) => [key, t(`share.${key}`)]),
  );
  strings.children = t('share.children', {
    count: Math.min(children.length, 31),
  });
  strings.retry = t('common.retry');
  strings.cancel = t('common.cancel');
  return (
    <NativeSessionShare
      style={{ flex: 1 }}
      configurationJSON={JSON.stringify({
        title:
          data?.candidates.find((s) => s.id === params.sessionId)?.title ||
          t('share.title'),
        loaded: !!data,
        active,
        canPublish,
        canReset: !!entry?.canManage,
        canRevoke: !!entry?.canRevoke,
        hasLink: !!data?.url,
        childrenCount: children.length,
        includeChildren: selected.length > 1,
        selectionAvailable,
        pending: !!data?.pending,
        busy,
        error,
        notice,
        progressText,
        percent: progress?.phase === 'uploading' ? progress.percent : undefined,
        strings,
      })}
      onAction={({ nativeEvent: { action, value } }) => {
        if (busy) return;
        switch (action) {
          case 'includeChildren':
            if (!data?.pending)
              setSelected(
                value
                  ? [
                      params.sessionId,
                      ...children.slice(0, 31).map((s) => s.id),
                    ]
                  : [params.sessionId],
              );
            break;
          case 'retry':
            void run(retryAction.current);
            break;
          case 'publish':
          case 'discard':
          case 'reset':
          case 'revoke':
            void run(action);
            break;
          case 'copy':
            if (data?.url) {
              try {
                copyText(data.url);
                setNotice(t('share.copied'));
              } catch {
                retryAction.current = 'read';
                setError(true);
              }
            }
            break;
          case 'share':
            if (data?.url)
              void Share.share({ url: data.url }).catch(() => {
                retryAction.current = 'read';
                setError(true);
              });
            break;
        }
      }}
    />
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
