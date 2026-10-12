import { useEffect, useMemo, useSyncExternalStore } from 'react';
import { archiveSession } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { useConnection } from '@/cloud/catalog/connection';
import {
  createAutoArchiveObserver,
  getAutoArchivePreferencesStore,
} from './autoArchive';
import { showToast } from '@/ui/toast';
import { t } from '@/lib/i18n';

export function useAutoArchivePreferences(userId: string) {
  const store = getAutoArchivePreferencesStore(userId);
  const snapshot = useSyncExternalStore(
    store.subscribe,
    store.getSnapshot,
    store.getSnapshot,
  );
  return { ...snapshot, update: store.update };
}

export function AutoArchiveWatcher() {
  const { account } = useAuth();
  const { catalog, selected } = useCatalog();
  const connection = useConnection();
  const userId = account?.user.id ?? '';
  const workspaceId = selected?.id ?? '';
  const { ready, preferences } = useAutoArchivePreferences(userId);
  const observer = useMemo(createAutoArchiveObserver, [userId, workspaceId]);
  useEffect(() => {
    if (!userId || !workspaceId || !ready || connection.state !== 'live')
      return;
    for (const session of observer.observe(
      catalog.sessions,
      userId,
      preferences,
    )) {
      void archiveSession(
        JSON.stringify({ workspaceId, sessionId: session.id, archived: true }),
      ).catch(() => showToast(t('session.toast.autoArchiveFailed')));
    }
  }, [
    catalog,
    userId,
    workspaceId,
    ready,
    preferences,
    observer,
    connection.state,
  ]);
  return null;
}
