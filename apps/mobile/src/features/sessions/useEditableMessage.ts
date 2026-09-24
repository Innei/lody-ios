import { useEffect, useState } from 'react';
import { readSessionEdit } from '@lody-ios/kit';
import type { Snapshot } from '@/models/session';

export function useEditableMessage(
  sessionId: string,
  snapshot: Snapshot,
  enabled: boolean,
  catalogVersion?: number,
) {
  const [editable, setEditable] = useState('');
  const latestIndex = snapshot.entries.findLastIndex(
    (entry) => entry.role === 'user' && entry.status !== 'queued',
  );
  const latest = snapshot.entries[latestIndex];
  const preceding = snapshot.entries[latestIndex - 1];
  const goal = snapshot.entries.findLast((entry) =>
    entry.items.some((item) => item.type === 'goal'),
  );
  const eligibility = `${latest?.id}:${latest?.status}:${preceding?.id}:${preceding?.finished}:${goal?.id}:${goal?.rev}`;
  useEffect(() => {
    let active = true;
    setEditable('');
    if (!enabled || !latest) return;
    void readSessionEdit(
      JSON.stringify({
        action: 'read',
        sessionId,
        expectedUserTurnId: latest.id,
      }),
    )
      .then((result) => {
        if (active && JSON.parse(result).state === 'ready')
          setEditable(latest.id);
      })
      .catch(() => {});
    return () => {
      active = false;
    };
  }, [sessionId, enabled, eligibility, catalogVersion]);
  return enabled && editable === latest?.id ? editable : '';
}
