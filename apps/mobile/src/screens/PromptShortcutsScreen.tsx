import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { NativeGroupedList, showToast } from '@lody-ios/kit';
import type {
  PromptShortcutIndexEntry,
  PromptShortcut,
} from '@lody/cloud-runtime/models/prompt-shortcuts';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import {
  requestShortcuts,
  type ShortcutService,
} from '@/cloud/prompt-shortcuts';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { listState } from '@/features/settings/list-state';
import { shortcutSections } from '@/features/settings/prompt-shortcuts';
import { PromptShortcutEditorScreen } from './PromptShortcutEditorScreen';

export function PromptShortcutsView({
  workspaceId,
  userId,
  service = requestShortcuts,
}: {
  workspaceId: string;
  userId: string;
  service?: ShortcutService;
}) {
  const [items, setItems] = useState<PromptShortcutIndexEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [pulled, setPulled] = useState(false);
  const [loadedAt, setLoadedAt] = useState<number>();
  const [loaded, setLoaded] = useState(false);
  const generation = useRef(0);
  const { present } = usePageRuntime();
  const colors = usePalette();
  const refresh = useCallback(async () => {
    const id = ++generation.current;
    setLoading(true);
    setError(false);
    try {
      const result = await service({ workspaceId, action: 'list' });
      if (!Array.isArray(result)) throw new Error('invalid_shortcuts');
      if (generation.current === id) {
        setItems(result);
        setLoaded(true);
        setLoadedAt(Date.now());
      }
    } catch {
      if (generation.current === id) setError(true);
    } finally {
      if (generation.current === id) {
        setLoading(false);
        setPulled(false);
      }
    }
  }, [workspaceId, service]);
  useEffect(() => {
    void refresh();
    return () => {
      generation.current++;
    };
  }, [refresh]);
  const edit = useCallback(
    async (entry: PromptShortcutIndexEntry | null) => {
      const id = generation.current;
      try {
        const value = entry
          ? ((await service({
              workspaceId,
              action: 'read',
              entry,
            })) as PromptShortcut)
          : undefined;
        if (generation.current !== id) return;
        const result = await present(PromptShortcutEditorScreen, {
          workspaceId,
          userId,
          entry,
          value,
          service,
        });
        if (result.status === 'completed') void refresh();
      } catch {
        showToast(t('settings.shortcuts.changed'), 'error');
        void refresh();
      }
    },
    [workspaceId, userId, service, present, refresh],
  );
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'plus' },
        accessibilityLabel: t('settings.shortcuts.add'),
        onPress: () => void edit(null),
        disabled: !loaded || loading || error,
      },
    ],
    [edit, loading, loaded, error],
  );
  useSheetHeader(actions);
  const state = listState({
    title: t('settings.unavailable.shortcuts'),
    hasData: loaded,
    loading,
    failed: error,
    syncedAt: loadedAt,
  });
  const reload = () => void refresh();
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      refreshing={pulled && loading}
      onRefresh={() => {
        setPulled(true);
        reload();
      }}
      loading={state.loading}
      notice={state.notice}
      unavailable={state.unavailable}
      onNoticeAction={reload}
      onUnavailableAction={reload}
      placeholder={loaded && !items.length ? t('settings.shortcuts.empty') : ''}
      sections={shortcutSections(items, userId)}
      onRowPress={({ nativeEvent: { id } }) => {
        const entry = items.find((item) => item.id === id);
        if (entry) void edit(entry);
      }}
    />
  );
}
function View() {
  const { account } = useAuth();
  const { selected } = useCatalog();
  if (!selected || !account) return null;
  return (
    <PromptShortcutsView
      key={`${account.user.id}:${selected.id}`}
      workspaceId={selected.id}
      userId={account.user.id}
    />
  );
}
export const PromptShortcutsScreen = definePage({
  id: 'prompt-shortcuts',
  title: t('settings.shortcuts.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
