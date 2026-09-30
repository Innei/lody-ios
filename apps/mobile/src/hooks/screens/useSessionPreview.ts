import { useCallback, useEffect, useRef, useState } from 'react';
import { ActionSheetIOS, Alert } from 'react-native';
import {
  copyText,
  openPreviewBrowser,
  previewSimulators,
  sessionPreview,
  type SessionPreviewReply,
} from '@lody-ios/kit';
import { present } from '@/lib/presentation';
import { showToast } from '@/ui/toast';
import { t } from '../../lib/i18n/index.ts';

type Summary = { label: string; active: boolean };
type Phase = 'idle' | 'connecting' | 'unavailable';

type Simulator = { udid: string; name: string };

/** A simulator is known only after a tunnel answers as baguette. */
const chosenSimulators = new Map<string, Simulator>();

function failureText(reply: SessionPreviewReply) {
  if (reply.error === 'unsupported') return t('session.preview.unsupported');
  return reply.message ?? t('session.preview.generic');
}

function pickSimulator(devices: Simulator[]) {
  return new Promise<Simulator | 'browser' | undefined>((resolve) => {
    const options = [
      ...devices.map((device) => device.name),
      t('simulator.action.openInBrowser'),
      t('common.cancel'),
    ];
    ActionSheetIOS.showActionSheetWithOptions(
      {
        title: t('simulator.choose'),
        options,
        cancelButtonIndex: options.length - 1,
      },
      (index) => {
        if (index < devices.length) resolve(devices[index]);
        else if (index === devices.length) resolve('browser');
        else resolve(undefined);
      },
    );
  });
}

export function useSessionPreview(sessionId: string, summary?: Summary) {
  const [phase, setPhase] = useState<Phase>('idle');
  const [failure, setFailure] = useState('');
  const [simulator, setSimulator] = useState(chosenSimulators.get(sessionId));
  const busy = useRef(false);
  useEffect(() => {
    setPhase('idle');
    setSimulator(chosenSimulators.get(sessionId));
  }, [sessionId]);

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

  const open = useCallback(
    async (choose = false) => {
      const url = await create();
      if (!url) return;
      const devices = await previewSimulators(url).catch(() => []);
      if (!devices.length) {
        await openPreviewBrowser(url);
        return;
      }
      const remembered = chosenSimulators.get(sessionId);
      const current = devices.find(
        (device) => device.udid === remembered?.udid,
      );
      let choice: Simulator | 'browser' | undefined = current;
      if (choose || !current)
        choice =
          devices.length === 1 ? devices[0] : await pickSimulator(devices);
      if (choice === 'browser') {
        await openPreviewBrowser(url);
        return;
      }
      if (!choice) return;
      chosenSimulators.set(sessionId, choice);
      setSimulator(choice);
      const { SimulatorScreen } = await import('@/screens/SimulatorScreen');
      await present(
        SimulatorScreen,
        { url, udid: choice.udid, name: choice.name },
        { title: choice.name },
      );
    },
    [create, sessionId],
  );

  const onPreview = useCallback(
    (action: string) => {
      if (busy.current) return;
      busy.current = true;
      const run = async () => {
        if (action === 'open') await open();
        if (action === 'choose') await open(true);
        if (action === 'browser') {
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
    [create, open, sessionId],
  );

  const chip = summary
    ? {
        label:
          (phase === 'connecting' && t('session.preview.connecting')) ||
          (phase === 'unavailable' && t('session.preview.unavailable')) ||
          simulator?.name ||
          summary.label,
        symbol: simulator ? 'iphone' : 'safari',
        state: phase === 'idle' ? 'ready' : phase,
        accessibilityLabel:
          failure && phase === 'unavailable'
            ? `${t('session.preview.unavailable')}, ${failure}`
            : t('session.preview.open', {
                target: simulator?.name ?? summary.label,
              }),
        actions: [
          ...(simulator
            ? [
                {
                  id: 'choose',
                  title: t('simulator.chooseAnother'),
                  symbol: 'iphone.gen3',
                },
              ]
            : []),
          {
            id: 'browser',
            title: t('simulator.action.openInBrowser'),
            symbol: 'safari',
          },
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
