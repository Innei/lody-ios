import { Stack } from 'expo-router';
import { usePendingSends } from '@/cloud/pendingSends';
import { useConnection } from '@/cloud/connection';
import { useSessionSend } from './useSessionSend';
import { useCatalog } from '@/cloud/CatalogProvider';
import { useEffect, useMemo, useRef, useState } from 'react';
import { View, Alert } from 'react-native';
import { usePalette } from '@/theme/palette';
import { NativeChat, sessionCreationOptions } from '@lody-ios/kit';
import { definePage, present, usePageRuntime } from '@/presentation';
import { localProjectIdOf } from '@lody-ios/kit';
import { newSession, setArchived, setPinned } from './navigation';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Capability, CreationOptions, Session } from '@/cloud/model';
import type { EntrySummary, ItemSummary } from './transcript/types';
import { pendingPermission, useSessionRuntime } from './useSessionRuntime';
import { itemDetailPage } from './detail/itemDetailPage';
import { basename } from './changes/turnChangesPage';
import { fileDiffPage } from './changes/fileDiffPage';
import { filesPage } from './files/FilesScreen';
import { changedFiles } from './transcript/changes';
import { permissionPage } from './detail/permissionPage';
import { useProcessSheet } from './detail/processPage';
import type { ModelChoice } from './ModelScreen';
import { t } from '../../i18n/index.ts';

function composerPlaceholder({
  archived,
  disconnected,
  overflow,
  live,
}: {
  archived: boolean;
  disconnected: boolean;
  overflow: boolean;
  live: boolean;
}) {
  if (archived) return t('chat.composer.archived');
  if (!disconnected && !overflow && !live) return t('chat.composer.connecting');
  return t('chat.composer.placeholder');
}

type SessionParams = {
  session: Session;
  modelId?: string;
  effort?: string;
  modeId?: string;
};

function SessionScreen() {
  const {
    params: { session, modelId, effort, modeId },
  } = usePageRuntime<SessionParams>();
  const { account } = useAuth(),
    colors = usePalette();
  const { catalog, selected, serverSessions, refresh } = useCatalog();
  const connection = useConnection();
  const outbox = usePendingSends(account?.user.id ?? '', selected?.id ?? '');
  const pending = outbox.records.find(
    (record) => record.session.id === session.id,
  );
  const project = catalog.projects.find((p) => p.id === session.projectId);
  const currentSession =
    catalog.sessions.find((s) => s.id === session.id) ?? session;
  const [capability, setCapability] = useState<Capability>();
  const [choice, setChoice] = useState<ModelChoice>({
    modelId,
    effort,
    modeId,
  });
  const choiceHydrated = useRef(
    modelId !== undefined || effort !== undefined || modeId !== undefined,
  );

  const restoredChoice = useRef('');
  useEffect(() => {
    if (!outbox.ready || !pending || restoredChoice.current === pending.send.id)
      return;
    restoredChoice.current = pending.send.id;
    choiceHydrated.current = true;
    setChoice({
      modelId: pending.send.choice.modelId ?? undefined,
      effort: pending.send.choice.effort ?? undefined,
      modeId: pending.send.choice.modeId,
    });
  }, [outbox.ready, pending]);

  useEffect(() => {
    if (
      !selected?.id ||
      !project?.id ||
      !currentSession.cliType ||
      !currentSession.agentType
    ) {
      setCapability(undefined);
      return;
    }
    let active = true;
    void sessionCreationOptions(
      JSON.stringify({ workspaceId: selected.id, projectId: project.id }),
    )
      .then((raw) => {
        if (!active) return;
        const options: CreationOptions = JSON.parse(raw);
        setCapability(
          options.capabilities.find(
            (item) =>
              item.machineId === currentSession.machineId &&
              item.cliType === currentSession.cliType &&
              item.agentType === currentSession.agentType,
          ),
        );
      })
      .catch(() => {
        if (active) setCapability(undefined);
      });
    return () => {
      active = false;
    };
  }, [
    selected?.id,
    project?.id,
    currentSession.machineId,
    currentSession.cliType,
    currentSession.agentType,
  ]);
  const browsable =
    !!selected &&
    !pending?.send.creation &&
    !currentSession.archived &&
    !!localProjectIdOf(session.projectId);
  const showDetails = () =>
    Alert.alert(
      currentSession.title,
      [
        project?.name,
        project?.rootPath,
        t('session.detail.machine', { name: currentSession.machineId }),
      ]
        .filter(Boolean)
        .join('\n'),
      browsable && account
        ? [
            {
              text: t('session.action.projectFiles'),
              onPress: () =>
                void present(filesPage, {
                  workspaceId: selected.id,
                  sessionId: session.id,
                  userId: account.user.id,
                  path: '',
                  title: project?.name ?? t('session.action.projectFiles'),
                }),
            },
            { text: t('common.ok'), style: 'cancel' },
          ]
        : undefined,
    );
  const onTurnChangesPress = (entryId: string, path: string) => {
    const entry = snapshot.entries.find((e) => e.id === entryId);
    if (!entry) return;
    if (!changedFiles(entry).some((file) => file.path === path)) return;
    void present(
      fileDiffPage,
      { sessionId: session.id, entryId, path },
      { title: basename(path) },
    );
  };
  const { snapshot, overflow, cursor, reconnect } = useSessionRuntime(
    session.id,
    account?.user.id ?? '',
    selected?.id ?? '',
    outbox.ready && !pending?.send.creation,
  );
  useEffect(() => {
    if (
      !outbox.ready ||
      pending ||
      choiceHydrated.current ||
      !snapshot.composer
    )
      return;
    choiceHydrated.current = true;
    setChoice(snapshot.composer);
  }, [snapshot.composer, outbox.ready, pending]);
  const activeChoice = choiceHydrated.current
    ? choice
    : (snapshot.composer ?? choice);
  const send = useSessionSend({
    outbox,
    session: currentSession,
    record: pending,
    snapshot,
    connected: connection.state === 'live',
    serverCreated: serverSessions.some((entry) => entry.id === session.id),
    userId: account?.user.id ?? '',
    overflow,
  });
  const answered = useRef(new Set<string>());

  const askPermission = (
    entry: EntrySummary,
    item: Extract<ItemSummary, { type: 'tool_call' }>,
  ) =>
    void present(permissionPage, {
      sessionId: session.id,
      entryId: entry.id,
      itemId: item.itemId,
      requestId: item.permission!.requestId,
      generation: cursor.current.generation,
      kind: item.kind,
      title: item.title,
      path: item.path,
    });

  useEffect(() => {
    if (snapshot.status !== 'live' || !snapshot.awaitingUserSince) return;
    for (const entry of snapshot.entries) {
      const item = pendingPermission(entry);
      const requestId = item?.permission?.requestId;
      if (!item || !requestId || answered.current.has(requestId)) continue;
      answered.current.add(requestId);
      askPermission(entry, item);
      return;
    }
  }, [snapshot]);

  const onActivityPress = (entryId: string, itemId: string) => {
    if (snapshot.status !== 'live') {
      Alert.alert(
        t('session.alert.syncing.title'),
        t('session.alert.syncing.message'),
      );
      return;
    }
    const entry = snapshot.entries.find((e) => e.id === entryId);
    const item = entry?.items.find((i) => i.itemId === itemId);
    if (!entry || !item) return;
    if (
      entry &&
      item?.type === 'tool_call' &&
      'permission' in item &&
      item.permission?.pending
    ) {
      askPermission(entry, item as Extract<ItemSummary, { type: 'tool_call' }>);
      return;
    }
    void present(itemDetailPage, {
      sessionId: session.id,
      entryId,
      itemIds: [itemId],
      generation: cursor.current.generation,
    });
  };

  const disconnected = ['offline', 'failed', 'stopped'].includes(
    snapshot.status,
  );
  const entriesJSON = useMemo(
    () =>
      JSON.stringify(
        snapshot.entries.map((entry) => ({
          ...entry,
          fileDiffs: changedFiles(entry),
        })),
      ),
    [snapshot.entries],
  );
  const openProcess = useProcessSheet(entriesJSON, onActivityPress);
  let notice = '';
  if (overflow) notice = t('chat.notice.syncStopped');
  else if (disconnected && !send.sending)
    notice = t('chat.notice.connectionPaused');
  const composerJSON = JSON.stringify({
    editable: !currentSession.archived,
    canSend: send.canSend,
    sending: send.sending,
    notice,
    reconnect: disconnected || overflow,
    placeholder: composerPlaceholder({
      archived: currentSession.archived,
      disconnected,
      overflow,
      live: snapshot.status === 'live',
    }),
  });
  const efforts = activeChoice.modelId
    ? (capability?.reasoningEfforts[activeChoice.modelId] ?? [])
    : [];
  const composerOptionsJSON = JSON.stringify({
    modelId: activeChoice.modelId ?? '',
    effort: activeChoice.effort ?? '',
    models: (capability?.models ?? []).map((item) => ({
      id: item.id,
      title: item.name,
    })),
    efforts: efforts.map((id) => ({ id, title: id })),
  });
  return (
    <View style={{ flex: 1, backgroundColor: colors.reading }}>
      <Stack.Screen
        options={{
          title: currentSession.title,
        }}
      />
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Menu
          icon="ellipsis.circle"
          accessibilityLabel={t('common.more')}
        >
          <Stack.Toolbar.MenuAction
            icon="square.and.pencil"
            onPress={() => {
              if (selected)
                void newSession(selected.id, catalog, currentSession.projectId);
            }}
          >
            {t('session.action.newSession')}
          </Stack.Toolbar.MenuAction>
          <Stack.Toolbar.MenuAction
            icon={currentSession.pinned ? 'pin.slash' : 'pin'}
            disabled={!!pending?.send.creation}
            onPress={() => {
              if (selected)
                void setPinned(
                  selected.id,
                  currentSession,
                  !currentSession.pinned,
                );
            }}
          >
            {t(
              currentSession.pinned
                ? 'session.action.unpin'
                : 'session.action.pin',
            )}
          </Stack.Toolbar.MenuAction>
          <Stack.Toolbar.MenuAction
            icon={currentSession.archived ? 'tray.and.arrow.up' : 'archivebox'}
            disabled={!!pending?.send.creation}
            onPress={() => {
              if (selected)
                void setArchived(
                  selected.id,
                  currentSession,
                  !currentSession.archived,
                );
            }}
          >
            {t(
              currentSession.archived
                ? 'session.action.unarchive'
                : 'session.action.archive',
            )}
          </Stack.Toolbar.MenuAction>
        </Stack.Toolbar.Menu>
      </Stack.Toolbar>
      <NativeChat
        navigationTitle={currentSession.title}
        navigationSubtitle={project?.name ?? ''}
        onTitlePress={showDetails}
        style={{ flex: 1 }}
        attachmentContextJSON={JSON.stringify({
          workspaceId: selected?.id,
          sessionId: session.id,
        })}
        entriesJSON={entriesJSON}
        composerJSON={composerJSON}
        composerOptionsJSON={composerOptionsJSON}
        draftKey={
          account && selected
            ? `draft:${account.user.id}:${selected.id}:${session.id}`
            : ''
        }
        pendingSendJSON={send.pendingSendJSON}
        clearDraftToken={send.clearDraftToken}
        restoreDraftToken={send.restoreDraftToken}
        emptyText={
          snapshot.status === 'live'
            ? t('chat.empty.prompt')
            : t('chat.empty.loading')
        }
        onSend={({ nativeEvent }) =>
          send.submit({
            id: nativeEvent.id,
            text: nativeEvent.text,
            attachments: nativeEvent.attachments,
            phase: 'waiting',
            choice: {
              modelId: capability
                ? (activeChoice.modelId ?? null)
                : activeChoice.modelId,
              effort: capability
                ? (activeChoice.effort ?? null)
                : activeChoice.effort,
              modeId: activeChoice.modeId,
              reasoningEffortConfigId: capability?.reasoningEffortConfigId,
            },
          })
        }
        onActivityPress={({ nativeEvent }) =>
          nativeEvent.itemId
            ? onActivityPress(nativeEvent.entryId, nativeEvent.itemId)
            : openProcess(nativeEvent.entryId, nativeEvent.processStartId)
        }
        onTurnChangesPress={({ nativeEvent }) =>
          onTurnChangesPress(nativeEvent.entryId, nativeEvent.path)
        }
        onReconnect={pending?.send.creation ? refresh : reconnect}
        onComposerOptionChange={({ nativeEvent }) => {
          choiceHydrated.current = true;
          setChoice((current) => ({
            ...current,
            modelId: nativeEvent.modelId || undefined,
            effort: nativeEvent.effort || undefined,
          }));
        }}
      />
    </View>
  );
}
export const sessionPage = definePage<SessionParams>({
  id: 'session',
  title: t('session.title'),
  Component: SessionScreen,
  parseRouteParams: () => {
    throw new Error('请从会话列表打开');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
