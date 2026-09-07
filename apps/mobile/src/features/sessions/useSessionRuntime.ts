import { useEffect, useRef, useState } from 'react';
import {
  addDataRuntimeListener,
  watchSession,
  unwatchSession,
} from '@lody-ios/kit';
import { acceptEnvelope } from './acceptEnvelope';
import { localGeneration, readLocal } from '../../cloud/kv';
import { showToast } from '../../ui/toast';
import type { Envelope, Snapshot } from '../../models/session.ts';
import { t } from '../../i18n/index.ts';

export type { Snapshot } from '../../models/session.ts';

export function useSessionRuntime(
  sessionId: string,
  userId: string,
  workspaceId: string,
  enabled = true,
) {
  const key = `session:${JSON.stringify([userId, workspaceId, sessionId])}`;
  const [snapshot, setSnapshot] = useState<Snapshot>({
    status: 'syncing',
    revision: -1,
    entries: [],
  });
  const [overflow, setOverflow] = useState(false);
  const cursor = useRef({ generation: -1, revision: -1 });
  const reconnect = () => {
    if (!enabled) return;
    void watchSession(sessionId).catch(() =>
      setSnapshot((old) => ({ ...old, status: 'offline' })),
    );
  };
  useEffect(() => {
    let active = true;
    let received = false;
    let saveErrorShown = false;
    const localVersion = localGeneration();
    cursor.current = { generation: -1, revision: -1 };
    setSnapshot({ status: 'syncing', revision: -1, entries: [] });
    setOverflow(false);
    if (!enabled || !userId || !workspaceId) return;
    void readLocal<Envelope>(key).then((saved) => {
      if (
        !active ||
        received ||
        localVersion !== localGeneration() ||
        saved?.v !== 1 ||
        !Array.isArray(saved.entries)
      )
        return;
      // Cached revisions belong to an earlier replica, never the live cursor.
      setSnapshot((old) => ({ ...saved, status: old.status }));
    });
    const subscription = addDataRuntimeListener((event) => {
      if (!active || localVersion !== localGeneration()) return;
      if (event.reason === 'session_cache_failed' && !saveErrorShown) {
        saveErrorShown = true;
        showToast(t('session.toast.localSaveFailed'));
      }
      if (event.sessionId === sessionId && event.session) {
        try {
          const data = JSON.parse(event.session);
          if (data.overflow && data.v === 1) {
            setOverflow(true);
            return;
          }
          const verdict = acceptEnvelope(cursor.current, event, data);
          if (verdict === 'drop') return;
          cursor.current = {
            generation: event.generation,
            revision: data.revision,
          };
          setOverflow(false);
          if (data.status === 'live') {
            received = true;
            setSnapshot(data);
          } else {
            // Bootstrap/recovery can emit an empty or partial replica.
            setSnapshot((old) => ({ ...old, status: data.status }));
          }
        } catch {
          setSnapshot((old) => ({ ...old, status: 'offline' }));
        }
      } else if (
        ['starting', 'background', 'failed', 'stopped'].includes(event.state)
      ) {
        setSnapshot((old) => ({ ...old, status: event.state }));
      }
    });
    reconnect();
    return () => {
      active = false;
      subscription.remove();
      void unwatchSession(sessionId);
    };
  }, [key, enabled]);
  return { snapshot, overflow, cursor, reconnect };
}
