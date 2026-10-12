import { useEffect, useMemo, useSyncExternalStore } from 'react';
import {
  subagentIdentityKey,
  type SubagentIdentity,
} from '@lody/cloud-runtime/models/subagent-history';
import type { SubagentHistoryService } from '../../cloud/subagent-history.ts';
import { createSubagentHistoryController } from './controller.ts';

export function useSubagentHistory(
  identity: SubagentIdentity,
  service: SubagentHistoryService,
) {
  const key = subagentIdentityKey(identity);
  const controller = useMemo(
    () => createSubagentHistoryController(service),
    [service, key],
  );
  const snapshot = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
  );
  useEffect(() => {
    void controller.start(identity);
    return () => controller.dispose();
  }, [controller]);
  return { ...snapshot, controller, service };
}
