import {
  addDataRuntimeListener,
  watchCatalog,
  unwatchCatalog,
  type DataRuntimeEvent,
} from '@lody-ios/kit';
import type { Catalog } from '../../models/catalog.ts';
let nextOwner = 0;
export function subscribeCatalog(
  workspace: string,
  userId: string,
  onEvent: (event: DataRuntimeEvent, catalog?: Catalog) => void,
) {
  const owner = String(++nextOwner);
  let active = true;
  const subscription = addDataRuntimeListener((event) => {
    if (!active || event.owner !== owner) return;
    if (!event.catalog) {
      onEvent(event);
      return;
    }
    try {
      const data = JSON.parse(event.catalog);
      if (
        !Array.isArray(data.projects) ||
        !Array.isArray(data.sessions) ||
        !Array.isArray(data.machineIds)
      )
        throw new Error('Invalid catalog');
      onEvent(event, data);
    } catch {
      onEvent({ ...event, state: 'failed', reason: 'invalid_catalog' });
    }
  });
  void watchCatalog(workspace, owner, userId).catch(() => {
    if (active)
      onEvent({
        owner,
        generation: 0,
        state: 'failed',
        reason: 'native_start_failed',
        acknowledgements: 0,
      });
  });
  return () => {
    active = false;
    subscription.remove();
    void unwatchCatalog(owner);
  };
}
