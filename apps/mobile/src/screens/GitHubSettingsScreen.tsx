import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState, Linking } from 'react-native';
import { NativeGroupedList } from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { requestGitHubSettings } from '@/cloud/workspace-settings';
import {
  githubSettingsSections,
  type GitHubSettings,
  type GitHubSettingsRequest,
  type GitHubSettingsService,
} from '@/features/settings/github-settings';
import { listState } from '@/features/settings/list-state';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
export function GitHubSettingsView({
  workspaceId,
  service = requestGitHubSettings,
  onChanged,
  openURL = Linking.openURL,
}: {
  workspaceId: string;
  service?: GitHubSettingsService;
  onChanged?: () => void;
  openURL?: (url: string) => Promise<unknown>;
}) {
  const [value, setValue] = useState<GitHubSettings>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState(false);
  const [unconfirmed, setUnconfirmed] = useState(false);
  const [pulled, setPulled] = useState(false);
  const [loadedAt, setLoadedAt] = useState<number>();
  const version = useRef(0),
    writing = useRef(false),
    opening = useRef(false);
  const colors = usePalette();
  const read = useCallback(async () => {
    if (writing.current) return;
    const id = ++version.current;
    setBusy(true);
    setError(false);
    try {
      const next = await service({
        page: 'github',
        workspaceId,
        action: 'list',
      });
      if ('url' in next) throw new Error('invalid');
      if (version.current === id) {
        setValue(next);
        setUnconfirmed(false);
        setLoadedAt(Date.now());
      }
    } catch {
      if (version.current === id) setError(true);
    } finally {
      if (version.current === id) {
        setBusy(false);
        setPulled(false);
      }
    }
  }, [workspaceId, service]);
  useEffect(() => {
    void read();
    return () => {
      version.current++;
    };
  }, [read]);
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active' && opening.current) {
        opening.current = false;
        void read();
        onChanged?.();
      }
    });
    return () => subscription.remove();
  }, [read, onChanged]);
  const perform = async (request: GitHubSettingsRequest) => {
    if (writing.current || busy) return;
    writing.current = true;
    setBusy(true);
    setError(false);
    const id = ++version.current;
    try {
      const next = await service(request);
      if (version.current !== id) return;
      if ('url' in next) {
        opening.current = true;
        await openURL(next.url);
      } else {
        setValue(next);
        onChanged?.();
      }
    } catch {
      if (version.current === id) setUnconfirmed(true);
    } finally {
      writing.current = false;
      if (version.current === id) setBusy(false);
    }
  };
  const partial = !!value?.errors.length;
  const failed = error || partial || unconfirmed;
  const state = listState({
    title: t('settings.unavailable.github'),
    hasData: !!value,
    loading: busy,
    failed: error,
    unconfirmed,
    partial: partial ? t('settings.github.partial') : undefined,
    syncedAt: loadedAt,
  });
  const reload = () => void read();
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      refreshing={pulled && busy}
      onRefresh={() => {
        setPulled(true);
        reload();
      }}
      loading={state.loading}
      notice={state.notice}
      unavailable={state.unavailable}
      onNoticeAction={reload}
      onUnavailableAction={reload}
      sections={value ? githubSettingsSections(value, !busy && !failed) : []}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'install' && value?.canManage)
          void perform({ page: 'github', workspaceId, action: 'install' });
      }}
      onRowAction={({ nativeEvent: { id, actionId } }) => {
        if (!['enabled', 'disabled'].includes(actionId) || failed) return;
        const enabled = actionId === 'enabled';
        if (id === 'preference' && value?.personal?.enabled !== enabled)
          void perform({
            page: 'github',
            workspaceId,
            action: 'preference',
            enabled,
          });
        else if (
          id.startsWith('repo:') &&
          value?.canManage &&
          value.repositories?.some(
            (repo) =>
              repo.repoFullName === id.slice(5) && repo.enabled !== enabled,
          )
        )
          void perform({
            page: 'github',
            workspaceId,
            action: 'repository',
            repoFullName: id.slice(5),
            enabled,
          });
      }}
    />
  );
}
function View() {
  const { account } = useAuth();
  const { selected, refresh } = useCatalog();
  if (!account || !selected) return null;
  return (
    <GitHubSettingsView
      key={`${account.user.id}:${selected.id}`}
      workspaceId={selected.id}
      onChanged={refresh}
    />
  );
}
export const GitHubSettingsScreen = definePage({
  id: 'github-settings',
  title: 'GitHub',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
