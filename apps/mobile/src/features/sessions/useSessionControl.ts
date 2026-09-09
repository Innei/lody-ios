import { useRef, useState } from 'react';
import { controlSessionTurn } from '@lody-ios/kit';
import type { Session } from '@/models/catalog';
import type { Snapshot } from '@/models/session';
import { showToast } from '@/ui/toast';
import { t } from '@/lib/i18n';
import { sessionState } from './status';

export function useSessionControl(
  session: Session,
  snapshot: Snapshot,
  overflow: boolean,
  steerable: boolean,
  request = controlSessionTurn,
) {
  const turnId = snapshot.entries.findLast(
    (entry) => entry.role === 'assistant' && !entry.finished,
  )?.id;
  const inFlight = useRef(false);
  const [busy, setBusy] = useState('');
  const [stoppedTurn, setStoppedTurn] = useState('');
  const stopping = !!turnId && stoppedTurn === turnId;
  const canControl =
    !!turnId &&
    snapshot.status === 'live' &&
    !session.archived &&
    !overflow &&
    !busy &&
    !stopping;

  async function act(action: 'stop' | 'steer', messageId?: string) {
    if (!canControl || inFlight.current) return;
    inFlight.current = true;
    setBusy(messageId ?? 'stop');
    try {
      const result = JSON.parse(
        await request(
          JSON.stringify({
            action,
            sessionId: session.id,
            machineId: session.machineId,
            turnId,
            messageId,
          }),
        ),
      );
      if (result.state === 'stopped') setStoppedTurn(turnId!);
    } catch {
      showToast(t('native.chat.composer.controlError'));
    } finally {
      inFlight.current = false;
      setBusy('');
    }
  }

  return {
    running:
      !!turnId || ['live', 'attention'].includes(sessionState(session.status)),
    canStop: canControl,
    controlling: !!busy || stopping,
    stopping: busy === 'stop' || stopping,
    steerID: busy === 'stop' ? '' : busy,
    steerInterrupts: !steerable,
    stop: () => void act('stop'),
    steer: (id: string) => void (steerable ? act('steer', id) : act('stop')),
  };
}
