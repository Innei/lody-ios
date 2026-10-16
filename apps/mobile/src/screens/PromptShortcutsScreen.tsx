import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  NativeGroupedList,
  NativeSymbolButton,
  showToast,
} from '@lody-ios/kit';
import type {
  PromptShortcutIndexEntry,
  PromptShortcut,
} from '@lody/cloud-runtime/models/prompt-shortcuts';
import { simpleShortcut } from '@lody/cloud-runtime/models/prompt-shortcuts';
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
      if (generation.current === id) setItems(result);
    } catch {
      if (generation.current === id) {
        setError(true);
        setItems([]);
      }
    } finally {
      if (generation.current === id) setLoading(false);
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
        title: t('settings.shortcuts.add'),
        systemImage: 'plus',
        onPress: () => void edit(null),
        disabled: loading || error,
      },
    ],
    [edit, loading, error],
  );
  useSheetHeader(actions);
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      refreshing={loading}
      onRefresh={() => void refresh()}
      placeholder={loading ? t('settings.remote.loading') : ''}
      sections={[
        ...(error
          ? [
              {
                id: 'error',
                footer: t('settings.shortcuts.loadFailed'),
                rows: [{ id: 'retry', title: t('common.retry'), action: true }],
              },
            ]
          : []),
        ...(['private', 'workspace'] as const).map((visibility) => ({
          id: visibility,
          header: t(`settings.shortcuts.${visibility}`),
          footer:
            visibility === 'workspace'
              ? t('settings.shortcuts.hint')
              : undefined,
          rows: items
            .filter((item) => item.visibility === visibility)
            .map((item) => ({
              id: item.id,
              title: item.name,
              subtitle: `/shortcut:${item.slug} · ${t(simpleShortcut(item) ? 'settings.shortcuts.ready' : 'settings.shortcuts.limited')}`,
              wrapSubtitle: true,
              action: true,
              disclosure: true,
            })),
        })),
        ...(!loading && !error && !items.length
          ? [{ id: 'empty', footer: t('settings.shortcuts.empty'), rows: [] }]
          : []),
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'retry') void refresh();
        else {
          const entry = items.find((item) => item.id === id);
          if (entry) void edit(entry);
        }
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
