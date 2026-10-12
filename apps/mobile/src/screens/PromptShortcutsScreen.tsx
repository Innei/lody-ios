import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert } from 'react-native';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  sessionCreationOptions,
  type NativeListSection,
} from '@lody-ios/kit';
import type { PromptShortcutIndexEntry } from '@lody/cloud-runtime/models/prompt-shortcuts';
import type { CreationOptions } from '@lody/cloud-runtime/models/send';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import {
  requestPromptShortcuts,
  shortcutErrorMessage,
  type PromptShortcutService,
} from '@/cloud/prompt-shortcuts';
import {
  promptShortcutScopeOptions,
  type PromptShortcutScopeOptions,
} from '@/features/prompt-shortcuts/scope';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { PromptShortcutEditorScreen } from './PromptShortcutEditorScreen';

export function PromptShortcutsView({
  workspaceId,
  userId,
  options,
  service = requestPromptShortcuts,
  loadMentions,
  fixture = false,
}: {
  workspaceId: string;
  userId: string;
  options: PromptShortcutScopeOptions;
  service?: PromptShortcutService;
  loadMentions?: typeof import('@lody-ios/kit').getMentionCatalog;
  fixture?: boolean;
}) {
  const { present } = usePageRuntime();
  const colors = usePalette();
  const [entries, setEntries] = useState<PromptShortcutIndexEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [query, setQuery] = useState('');
  const generation = useRef(0);
  const identity = `${userId}:${workspaceId}`;
  const current = useRef(identity);
  current.current = identity;
  const refresh = async () => {
    const id = ++generation.current;
    setLoading(true);
    setError('');
    try {
      const result = await service({ workspaceId, action: 'list' });
      if (current.current === identity && generation.current === id)
        setEntries(result.entries);
    } catch (cause) {
      if (current.current === identity && generation.current === id)
        setError(shortcutErrorMessage(cause));
    } finally {
      if (current.current === identity && generation.current === id)
        setLoading(false);
    }
  };
  useEffect(() => {
    setEntries([]);
    void refresh();
    return () => {
      generation.current++;
    };
  }, [identity, service]);
  const edit = async (entry?: PromptShortcutIndexEntry) => {
    const id = ++generation.current;
    setLoading(true);
    setError('');
    try {
      const item = entry
        ? (await service({ workspaceId, action: 'read', entry })).item
        : undefined;
      if (entry && !item) throw new Error('shortcut_not_found');
      if (current.current !== identity || generation.current !== id) return;
      setLoading(false);
      const result = await present(
        PromptShortcutEditorScreen,
        {
          workspaceId,
          userId,
          options,
          service,
          entry,
          item,
          loadMentions,
          fixture,
        },
        {
          title: t(
            entry
              ? 'settings.promptShortcuts.edit'
              : 'settings.promptShortcuts.add',
          ),
        },
      );
      if (current.current === identity && result.status === 'completed')
        void refresh();
    } catch (cause) {
      if (current.current === identity && generation.current === id)
        setError(shortcutErrorMessage(cause));
    } finally {
      if (current.current === identity && generation.current === id)
        setLoading(false);
    }
  };
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'plus' },
        accessibilityLabel: t('settings.promptShortcuts.add'),
        tintColor: colors.accent,
        disabled: loading,
        onPress: () => void edit(),
      },
    ],
    [loading, colors.accent, options, identity, service],
  );
  const filtered = entries.filter((entry) =>
    `${entry.name} ${entry.slug} ${entry.description ?? ''}`
      .toLowerCase()
      .includes(query.trim().toLowerCase()),
  );
  const sections: NativeListSection[] = [];
  if (error)
    sections.push({
      id: 'shortcut-error',
      footer: error,
      rows: [{ id: 'shortcut-retry', title: t('common.retry'), action: true }],
    });
  sections.push({
    id: 'shortcuts',
    footer: t('settings.promptShortcuts.hint'),
    rows: filtered.map((entry) => ({
      id: entry.id,
      title: `${entry.emoji ?? '📝'} ${entry.name}`,
      subtitle: `/${entry.slug} · ${entry.description ?? t(entry.visibility === 'workspace' ? 'settings.promptShortcuts.shared' : 'settings.promptShortcuts.private')}`,
      action: true,
      disclosure: true,
      ...(entry.ownerUserId === userId
        ? {
            actions: [
              {
                id: 'delete',
                title: t('common.delete'),
                symbol: 'trash',
                destructive: true,
              },
            ],
          }
        : {}),
    })),
  });
  let placeholder = t('settings.promptShortcuts.empty');
  if (query) placeholder = t('settings.promptShortcuts.noMatches');
  if (loading) placeholder = t('common.reading');
  return (
    <>
      <NativeNavigationHeader items={actions} />
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        refreshing={loading}
        onRefresh={() => void refresh()}
        sections={sections}
        placeholder={placeholder}
        searchPlaceholder={t('settings.promptShortcuts.search')}
        onSearchChange={({ nativeEvent }) => setQuery(nativeEvent.text)}
        onRowPress={({ nativeEvent: { id } }) => {
          if (id === 'shortcut-retry') {
            void refresh();
            return;
          }
          const entry = entries.find((entry) => entry.id === id);
          if (entry && !loading) void edit(entry);
        }}
        onRowAction={({ nativeEvent: { id, actionId } }) => {
          const entry = entries.find((entry) => entry.id === id);
          if (
            actionId !== 'delete' ||
            !entry ||
            entry.ownerUserId !== userId ||
            loading
          )
            return;
          Alert.alert(
            t('settings.promptShortcuts.deleteTitle'),
            t('settings.promptShortcuts.deleteHint'),
            [
              { text: t('common.cancel'), style: 'cancel' },
              {
                text: t('common.delete'),
                style: 'destructive',
                onPress: () => {
                  const requestId = ++generation.current;
                  setLoading(true);
                  void service({ workspaceId, action: 'delete', entry })
                    .then((result) => {
                      if (
                        current.current === identity &&
                        generation.current === requestId
                      ) {
                        setEntries(result.entries);
                        setError('');
                      }
                    })
                    .catch((cause) => {
                      if (
                        current.current === identity &&
                        generation.current === requestId
                      )
                        setError(shortcutErrorMessage(cause, 'saveFailed'));
                    })
                    .finally(() => {
                      if (
                        current.current === identity &&
                        generation.current === requestId
                      )
                        setLoading(false);
                    });
                },
              },
            ],
          );
        }}
      />
    </>
  );
}
function View() {
  const { cancel } = usePageRuntime();
  const { account } = useAuth();
  const { selected, catalog } = useCatalog();
  const [agents, setAgents] = useState<CreationOptions['agents']>([]);
  useEffect(() => {
    if (!selected || !account) {
      cancel();
      return;
    }
    let active = true;
    setAgents([]);
    void sessionCreationOptions(JSON.stringify({ workspaceId: selected.id }))
      .then((json) => {
        const value = JSON.parse(json) as CreationOptions;
        if (active && Array.isArray(value.agents)) setAgents(value.agents);
      })
      .catch(() => {});
    return () => {
      active = false;
    };
  }, [selected?.id, account?.user.id, cancel]);
  const options = useMemo(
    () => promptShortcutScopeOptions(catalog, agents),
    [catalog, agents],
  );
  if (!account || !selected) return null;
  return (
    <PromptShortcutsView
      key={`${account.user.id}:${selected.id}`}
      workspaceId={selected.id}
      userId={account.user.id}
      options={options}
    />
  );
}
export const PromptShortcutsScreen = definePage({
  id: 'prompt-shortcuts',
  title: t('settings.promptShortcuts.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
