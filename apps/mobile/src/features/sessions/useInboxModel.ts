import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  initialInboxView,
  saveInboxView,
  initialInboxProjectSort,
  saveInboxProjectSort,
  projectSorts,
  readInboxExpansion,
  saveInboxExpansion,
  readInboxPinOrder,
  saveInboxPinOrder,
} from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/lib/theme/palette';
import { listPlaceholder, searchPlaceholder } from '@/ui/listState';
import { showToast } from '@/ui/toast';
import { t } from '@/lib/i18n';
import { useSessionListCatalog } from './useSessionListCatalog';
import {
  activityAt,
  inboxSections,
  isChatSectionRow,
  projectSections,
  reconcilePinOrder,
  searchSections,
  type ProjectSort,
} from './inbox';
import { requestNewSession } from './sessionNav';
import { listRowAction } from './sessionActions';

export const inboxViews = [
  { mode: 0, key: 'inbox.settings.view.projects', icon: 'folder' },
  { mode: 1, key: 'inbox.settings.view.activity', icon: 'clock' },
  { mode: 2, key: 'inbox.settings.view.chat', icon: 'bubble.left' },
] as const;

export const inboxSorts = [
  { id: 'name' as const, key: 'inbox.settings.sort.name', icon: 'textformat' },
  {
    id: 'activity' as const,
    key: 'inbox.settings.sort.activity',
    icon: 'clock',
  },
  {
    id: 'urgency' as const,
    key: 'inbox.settings.sort.urgency',
    icon: 'exclamationmark.circle',
  },
] as const;

export function useInboxModel() {
  const { account, localReady } = useAuth();
  const colors = usePalette();
  const {
    catalog: sourceCatalog,
    selected,
    setWorkspaceId,
    loading,
    connected,
  } = useCatalog();
  const catalog = useSessionListCatalog(
    sourceCatalog,
    account?.user.id ?? '',
    selected?.id ?? '',
  );
  const [mode, setMode] = useState(initialInboxView);
  const [sort, setSort] = useState<ProjectSort>(initialInboxProjectSort);
  const [expanded, setExpanded] = useState(readInboxExpansion);
  const [query, setQuery] = useState('');
  const creating = useRef(false);
  const searching = !!query.trim();
  const userId = account?.user.id ?? '';
  const workspaceId = selected?.id ?? '';
  const pinOrder = useMemo(() => {
    const stored =
      userId && workspaceId ? readInboxPinOrder(userId, workspaceId) : [];
    const pinnedIds = catalog.sessions
      .filter((session) => session.pinned)
      .map((session) => session.id);
    return reconcilePinOrder(stored, pinnedIds, (id) => {
      const session = catalog.sessions.find((item) => item.id === id);
      return session ? activityAt(session) : 0;
    });
  }, [catalog, userId, workspaceId]);
  useEffect(() => {
    if (!userId || !workspaceId) return;
    const stored = readInboxPinOrder(userId, workspaceId);
    if (stored.join('\0') === pinOrder.join('\0')) return;
    saveInboxPinOrder(userId, workspaceId, pinOrder);
  }, [pinOrder, userId, workspaceId]);
  const sections = useMemo(() => {
    if (mode === 0)
      return projectSections(
        catalog,
        colors.accent,
        expanded,
        undefined,
        sort,
        pinOrder,
      );
    return inboxSections(catalog, {
      accent: colors.accent,
      chatOnly: mode === 2,
      pinOrder,
    });
  }, [mode, sort, catalog, colors.accent, expanded, pinOrder]);
  const setView = useCallback((next: (typeof inboxViews)[number]['mode']) => {
    setMode(next);
    saveInboxView(next);
  }, []);
  const setProjectSort = useCallback((next: ProjectSort) => {
    setSort(next);
    saveInboxProjectSort(projectSorts.indexOf(next));
  }, []);
  const newSession = useCallback(async () => {
    if (creating.current) return;
    if (!selected) {
      showToast(t('tabs.toast.signInFirst'));
      return;
    }
    creating.current = true;
    try {
      await requestNewSession(
        selected.id,
        catalog,
        undefined,
        undefined,
        t('tabs.newSession'),
      );
    } finally {
      creating.current = false;
    }
  }, [catalog, selected]);
  return {
    account,
    catalog,
    colors,
    connected,
    loading,
    mode,
    newSession,
    query,
    ready: localReady && !!account,
    searching,
    sections: searching
      ? searchSections(catalog, query, colors.accent)
      : sections,
    placeholder: searching
      ? searchPlaceholder({ signedIn: true, query, loading, connected })
      : listPlaceholder({ loading, connected }),
    consumeRowPress: (id: string, expanded = true) => {
      if (id === 'view:chat') {
        setView(2);
        return true;
      }
      if (id.startsWith('toggle:')) {
        const projectId = id.slice(7);
        saveInboxExpansion(projectId, expanded);
        setExpanded((previous) => ({ ...previous, [projectId]: expanded }));
        return true;
      }
      return isChatSectionRow(id);
    },
    rowAction: (id: string, actionId: string) => {
      if (selected) listRowAction(selected, catalog, id, actionId);
    },
    selected,
    setExpanded,
    setProjectSort,
    setQuery,
    setView,
    setWorkspaceId,
    sort,
  };
}

export type InboxModel = ReturnType<typeof useInboxModel>;
