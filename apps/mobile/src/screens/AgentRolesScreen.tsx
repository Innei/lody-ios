import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { NativeGroupedList } from '@lody-ios/kit';
import type {
  AgentRoleSnapshot,
  AgentRoleItem,
} from '@lody/cloud-runtime/models/agent-roles';
import { requestAgentRoles, type AgentRoleService } from '@/cloud/agent-roles';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { listState } from '@/features/settings/list-state';
import { roleSections } from '@/features/settings/agent-roles';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { AgentRoleEditorScreen } from './AgentRoleEditorScreen';

export function AgentRolesView({
  workspaceId,
  userId,
  service = requestAgentRoles,
}: {
  workspaceId: string;
  userId: string;
  service?: AgentRoleService;
}) {
  const [snapshot, setSnapshot] = useState<AgentRoleSnapshot>();
  const [loading, setLoading] = useState(true),
    [failed, setFailed] = useState(false),
    [pulled, setPulled] = useState(false);
  const [syncedAt, setSyncedAt] = useState<number>();
  const generation = useRef(0);
  const { present } = usePageRuntime();
  const { account } = useAuth();
  const { selected } = useCatalog();
  const actorScope = `${account?.user.id ?? ''}:${selected?.id ?? ''}`;
  const colors = usePalette();
  const refresh = useCallback(async () => {
    const id = ++generation.current;
    setLoading(true);
    setFailed(false);
    try {
      const next = await service({ workspaceId, action: 'list' });
      if (generation.current === id) {
        setSnapshot(next);
        setSyncedAt(Date.now());
      }
    } catch {
      if (generation.current === id) setFailed(true);
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
    async (item: AgentRoleItem | null) => {
      if (!snapshot || loading || failed) return;
      const id = generation.current;
      const result = await present(AgentRoleEditorScreen, {
        workspaceId,
        userId,
        item,
        agents: snapshot.agents,
        service,
        actorScope,
      });
      if (generation.current === id && result.status === 'completed')
        void refresh();
    },
    [
      snapshot,
      loading,
      failed,
      present,
      workspaceId,
      userId,
      service,
      refresh,
      actorScope,
    ],
  );
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'plus' },
        accessibilityLabel: t('settings.roles.add'),
        disabled: !snapshot || !snapshot.agents.length || loading || failed,
        onPress: () => void edit(null),
      },
    ],
    [snapshot, loading, failed, edit],
  );
  useSheetHeader(actions);
  const state = listState({
    title: t('settings.roles.unavailable'),
    hasData: !!snapshot,
    loading,
    failed,
    syncedAt,
  });
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      loading={state.loading}
      notice={state.notice}
      unavailable={state.unavailable}
      onNoticeAction={() => void refresh()}
      onUnavailableAction={() => void refresh()}
      refreshing={pulled && loading}
      onRefresh={() => {
        setPulled(true);
        void refresh();
      }}
      placeholder={
        snapshot && !snapshot.roles.length ? t('settings.roles.empty') : ''
      }
      sections={snapshot ? roleSections(snapshot.roles, userId) : []}
      onRowPress={({ nativeEvent: { id } }) => {
        const role = snapshot?.roles.find((role) => `role:${role.id}` === id);
        if (role) void edit(role);
      }}
    />
  );
}
function View() {
  const { account } = useAuth();
  const { selected } = useCatalog();
  if (!account || !selected) return null;
  return (
    <AgentRolesView
      key={`${account.user.id}:${selected.id}`}
      workspaceId={selected.id}
      userId={account.user.id}
    />
  );
}
export const AgentRolesScreen = definePage({
  id: 'agent-roles',
  title: t('settings.roles.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
