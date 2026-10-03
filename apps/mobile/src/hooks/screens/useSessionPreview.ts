import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert } from 'react-native';
import {
  copyText,
  openPreviewBrowser,
  sessionPreview,
  type SessionPreviewReply,
} from '@lody-ios/kit';
import { showToast } from '@/ui/toast';
import { t } from '../../lib/i18n/index.ts';

type Summary = { label: string; active: boolean };
type Phase = 'idle' | 'connecting' | 'unavailable';

function failureText(reply: SessionPreviewReply) {
  if (reply.error === 'unsupported') return t('session.preview.unsupported');
  return reply.message ?? t('session.preview.generic');
}

export function useSessionPreview(sessionId: string, summary?: Summary) {
  const [phase, setPhase] = useState<Phase>('idle');
  const [failure, setFailure] = useState('');
  const busy = useRef(false);
  useEffect(() => setPhase('idle'), [sessionId]);

  const create = useCallback(async () => {
    setPhase('connecting');
    const reply: SessionPreviewReply = await sessionPreview(sessionId).catch(
      () => ({ error: 'failed' }),
    );
    if (reply.url) {
      setPhase('idle');
      return reply.url;
    }
    setPhase('unavailable');
    setFailure(failureText(reply));
    Alert.alert(t('session.preview.failed'), failureText(reply));
    return undefined;
  }, [sessionId]);

  const onPreview = useCallback(
    (action: string) => {
      if (busy.current) return;
      busy.current = true;
      const run = async () => {
        if (action === 'open' || action === 'browser') {
          const url = await create();
          if (url) await openPreviewBrowser(url);
        }
        if (action === 'copy') {
          const url = await create();
          if (url) {
            copyText(url);
            showToast(t('session.preview.copied'), 'info');
          }
        }
        if (action === 'stop') {
          const reply = await sessionPreview(sessionId, 'revoke').catch(
            () => ({ error: 'failed' }) as SessionPreviewReply,
          );
          if (reply.error)
            Alert.alert(t('session.preview.failed'), failureText(reply));
          else showToast(t('session.preview.stopped'), 'info');
        }
      };
      void run().finally(() => {
        busy.current = false;
      });
    },
    [create, sessionId],
  );

  const chip = summary
    ? {
        label:
          (phase === 'connecting' && t('session.preview.connecting')) ||
          (phase === 'unavailable' && t('session.preview.unavailable')) ||
          summary.label,
        symbol: 'safari',
        state: phase === 'idle' ? 'ready' : phase,
        accessibilityLabel:
          failure && phase === 'unavailable'
            ? `${t('session.preview.unavailable')}, ${failure}`
            : t('session.preview.open', { target: summary.label }),
        actions: [
          { id: 'copy', title: t('session.preview.copyLink'), symbol: 'link' },
          ...(summary.active
            ? [
                {
                  id: 'stop',
                  title: t('session.preview.stop'),
                  symbol: 'stop.circle',
                  destructive: true,
                },
              ]
            : []),
        ],
      }
    : undefined;

  return { chip, onPreview };
}
