import { useCallback, useEffect, useId, useRef, useState } from 'react';
import { ActionSheetIOS, Alert } from 'react-native';
import {
  copyText,
  openPreviewBrowser,
  previewSimulators,
  sessionPreview,
  type SessionPreviewReply,
  type SimulatorSource,
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

const previewService = { sessionPreview, previewSimulators };

export function useSessionPreview(
  sessionId: string,
  summary?: Summary,
  service = previewService,
) {
  const streamId = useId();
  const [stream, setStream] = useState<SimulatorSource>();
  const [phase, setPhase] = useState<Phase>('idle');
  const [failure, setFailure] = useState('');
  const [simulator, setSimulator] = useState(chosenSimulators.get(sessionId));
  const busy = useRef(false);
  useEffect(() => {
    setPhase('idle');
    setStream(undefined);
    setSimulator(chosenSimulators.get(sessionId));
  }, [sessionId]);

  const create = useCallback(async () => {
    setPhase('connecting');
    const reply: SessionPreviewReply = await service
      .sessionPreview(sessionId)
      .catch(() => ({ error: 'failed' }));
    if (reply.url) {
      setPhase('idle');
      return reply.url;
    }
    setPhase('unavailable');
    setFailure(failureText(reply));
    Alert.alert(t('session.preview.failed'), failureText(reply));
    return undefined;
  }, [service, sessionId]);

  const expand = useCallback(async (source: SimulatorSource) => {
    const { SimulatorScreen } = await import('@/screens/SimulatorScreen');
    await present(SimulatorScreen, source, { title: source.name });
  }, []);

  const open = useCallback(
    async (choose = false) => {
      if (!choose && stream) return expand(stream);
      const url = await create();
      if (!url) return;
      const devices = await service.previewSimulators(url).catch(() => []);
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
      const source = { url, ...choice, streamId: `${streamId}:${choice.udid}` };
      setStream(source);
      await expand(source);
    },
    [create, expand, service, sessionId, stream, streamId],
  );

  const onPreview = useCallback(
    (action: string) => {
      if (action === 'close') {
        setStream(undefined);
        return;
      }
      if (busy.current) return;
      busy.current = true;
      const run = async () => {
        if (action === 'expand' && stream) await expand(stream);
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
          const reply = await service
            .sessionPreview(sessionId, 'revoke')
            .catch(() => ({ error: 'failed' }) as SessionPreviewReply);
          if (reply.error)
            Alert.alert(t('session.preview.failed'), failureText(reply));
          else {
            setStream(undefined);
            showToast(t('session.preview.stopped'), 'info');
          }
        }
      };
      void run().finally(() => {
        busy.current = false;
      });
    },
    [create, expand, open, service, sessionId, stream],
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

  return {
    chip,
    onPreview,
    simulatorPreviewJSON: stream ? JSON.stringify(stream) : '',
  };
}
