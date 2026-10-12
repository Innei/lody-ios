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
type Phase = 'idle' | 'connecting' | 'stopping' | 'unavailable';
const previewServices = { sessionPreview, openPreviewBrowser, copyText };

function failureText(reply: SessionPreviewReply, stopping = false) {
  if (reply.error === 'unsupported') return t('session.preview.unsupported');
  return (
    reply.message ??
    t(stopping ? 'session.preview.stopGeneric' : 'session.preview.generic')
  );
}

export function useSessionPreview(
  sessionId: string,
  summary?: Summary,
  services = previewServices,
) {
  const [phase, setPhase] = useState<Phase>('idle');
  const [failure, setFailure] = useState('');
  const [hidden, setHidden] = useState<string>();
  const key = JSON.stringify([sessionId, summary?.label]);
  const current = useRef({ key });
  if (current.current.key !== key) current.current = { key };
  const generation = current.current;
  const busy = useRef<typeof generation | undefined>(undefined);
  const previousActive = useRef(summary?.active);
  useEffect(() => {
    setPhase('idle');
    setFailure('');
    setHidden(undefined);
  }, [key]);
  useEffect(() => {
    if (!previousActive.current && summary?.active) setHidden(undefined);
    previousActive.current = summary?.active;
  }, [summary?.active]);
  useEffect(() => {
    current.current = generation;
    return () => {
      if (current.current === generation) current.current = { key: '' };
    };
  }, [generation]);

  const create = useCallback(async () => {
    setPhase('connecting');
    setFailure('');
    const reply: SessionPreviewReply = await services
      .sessionPreview(sessionId)
      .catch(() => ({ error: 'failed' }));
    if (current.current !== generation) return undefined;
    if (reply.url) {
      setPhase('idle');
      return reply.url;
    }
    setPhase('unavailable');
    setFailure(failureText(reply));
    Alert.alert(t('session.preview.failed'), failureText(reply));
    return undefined;
  }, [generation, services, sessionId]);

  const onPreview = useCallback(
    (action: string) => {
      if (busy.current === generation || current.current !== generation) return;
      if (action === 'dismiss' && !summary?.active) {
        setHidden(key);
        return;
      }
      const stopping = action === 'stop' || action === 'dismiss';
      if (!stopping && !['open', 'browser', 'copy'].includes(action)) return;
      busy.current = generation;
      const run = async () => {
        if (action === 'open' || action === 'browser') {
          const url = await create();
          if (url) await services.openPreviewBrowser(url);
        }
        if (action === 'copy') {
          const url = await create();
          if (url) {
            await services.copyText(url);
            showToast(t('session.preview.copied'), 'info');
          }
        }
        if (stopping) {
          setPhase('stopping');
          setFailure('');
          const reply = await services
            .sessionPreview(sessionId, 'revoke')
            .catch(() => ({ error: 'failed' }) as SessionPreviewReply);
          if (current.current !== generation) return;
          setPhase('idle');
          if (reply.error)
            Alert.alert(
              t('session.preview.stopFailed'),
              failureText(reply, true),
            );
          else {
            setHidden(key);
            showToast(t('session.preview.stopped'), 'info');
          }
        }
      };
      void run()
        .catch(() => {
          if (current.current !== generation) return;
          setPhase('idle');
          Alert.alert(
            t('session.preview.failed'),
            t('session.preview.generic'),
          );
        })
        .finally(() => {
          if (busy.current === generation) busy.current = undefined;
        });
    },
    [create, generation, key, services, sessionId, summary?.active],
  );

  if (!summary || hidden === key) return { chip: undefined, onPreview };

  const chip = {
    label:
      (phase === 'connecting' && t('session.preview.connecting')) ||
      (phase === 'stopping' && t('session.preview.stopping')) ||
      (phase === 'unavailable' && t('session.preview.unavailable')) ||
      summary.label,
    symbol: 'safari',
    state: phase === 'idle' ? 'ready' : phase,
    accessibilityLabel:
      failure && phase === 'unavailable'
        ? `${t('session.preview.unavailable')}, ${failure}`
        : t('session.preview.open', { target: summary.label }),
    actions: [
      {
        id: 'copy',
        title: t('session.preview.copyLink'),
        symbol: 'link',
      },
      {
        id: summary.active ? 'stop' : 'dismiss',
        title: summary.active
          ? t('session.preview.stop')
          : t('session.preview.dismiss'),
        symbol: 'xmark',
        destructive: summary.active,
        close: true,
      },
    ],
  };

  return { chip, onPreview };
}
