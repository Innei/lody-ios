import { fastModeFor, withFastMode } from '@/cloud/send/capability';
import { useComposerMentions } from '@/hooks/screens/useComposerMentions';
import { setPushVisibleRoute } from '@lody-ios/kit';
import { useFocusEffect } from 'expo-router';
import { Stack } from 'expo-router';
import { usePendingSends } from '@/cloud/send/pendingSends';
import { useConnection } from '@/cloud/catalog/connection';
import { useSessionControl } from '@/features/sessions/useSessionControl';
import { useSessionSend } from '@/features/sessions/useSessionSend';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { View as RNView, Alert } from 'react-native';
import { usePalette } from '@/lib/theme/palette';
import {
  NativeChat,
  copyText,
  localProjectIdOf,
  sessionCreationOptions,
} from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { requestNewSession } from '@/features/sessions/sessionNav';
import { isChatSession } from '@/features/sessions/inbox';
import { sessionTitleDetails } from '@/features/sessions/sessionTitle';
import { setArchived, setPinned } from '@/features/sessions/sessionActions';
import { useSessionViewed } from '@/features/sessions/useSessionViewed';
import { sessionDebugText } from '@/features/sessions/sessionDebug';
import { useAuth } from '@/cloud/auth/AuthProvider';
import type { Session } from '@/models/catalog';
import type { Capability, CreationOptions } from '@/models/send';
import { effortsFor } from '@/cloud/send/capability';

import { useSessionRuntime } from '@/features/sessions/useSessionRuntime';
import { ItemDetailScreen } from '@/screens/ItemDetailScreen';
import { basename } from '@/features/sessions/path';
import { FileDiffScreen } from '@/screens/FileDiffScreen';
import { FilesScreen } from '@/screens/FilesScreen';
import { changedFiles } from '@/features/sessions/transcript/changes';
import { DiffWebViewWarmer } from '@/features/diff/DiffWebViewWarmer';
import { PermissionScreen } from '@/screens/PermissionScreen';
import {
  createPermissionGate,
  firstPermissionTarget,
  type PermissionTarget,
  type PermissionTargetSource,
  type PermissionTargetState,
} from '@/features/sessions/permissionTarget';
import { useOpenFile } from '@/hooks/screens/useOpenFile';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';
import type { ModelChoice } from './ModelScreen';
import { t } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useOpenPullRequest } from '@/hooks/screens/useOpenPullRequest';

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
  projectName?: string;
  machineName?: string;
  modelId?: string;
  effort?: string;
  modeId?: string;
};

function View() {
  const {
    params: {
      session,
      projectName: creationProjectName,
      machineName: creationMachineName,
      modelId,
      effort,
      modeId,
    },
  } = usePageRuntime<SessionParams>();
  const { account } = useAuth(),
    colors = usePalette();
  const { catalog, selected, serverSessions, refresh } = useCatalog();
  const currentSession =
    catalog.sessions.find((s) => s.id === session.id) ?? session;
  const [appendDraftJSON, setAppendDraftJSON] = useState('');
  const openPullRequest = useOpenPullRequest(
    selected?.id ?? '',
    account?.user.id ?? '',
    (text) => {
      if (currentSession.archived || send.sending) {
        Alert.alert(t('pr.investigate'), t('pr.draftUnavailable'));
        return false;
      }
      setAppendDraftJSON(
        JSON.stringify({ id: `${Date.now()}:${Math.random()}`, text }),
      );
      return true;
    },
  );
  const pullRequests = currentSession.pullRequests ?? [];
  const prAttention = pullRequests.some((pr) => pr.ci === 'f' || pr.ci === 'e');
  useSessionViewed(
    account?.user.id ?? '',
    selected?.id ?? '',
    session.id,
    currentSession.lastMessageAt,
  );
  useFocusEffect(
    useCallback(() => {
      void setPushVisibleRoute(
        selected?.slug ? `/${selected.slug}/sessions/${session.id}` : '',
      );
      return () => {
        void setPushVisibleRoute('');
      };
    }, [selected?.id, selected?.slug, session.id]),
  );
  const connection = useConnection();
  const outbox = usePendingSends(account?.user.id ?? '', selected?.id ?? '');
  const pending = outbox.records.find(
    (record) => record.session.id === session.id,
  );
  const { project, projectName, machineName } = sessionTitleDetails(
    catalog,
    currentSession,
    {
      projectName: creationProjectName,
      machineName: creationMachineName,
    },
  );
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
      configOptionValues: pending.send.choice.configOptionValues,
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
  const onTurnChangesPress = (entryId: string, path: string) => {
    const entry = snapshot.entries.find((e) => e.id === entryId);
    if (!entry) return;
    if (!changedFiles(entry).some((file) => file.path === path)) return;
    void present(
      FileDiffScreen,
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
  const gate = useRef(createPermissionGate()).current;
  const listeners = useRef(new Set<(state: PermissionTargetState) => void>());
  const targetState = useRef<PermissionTargetState>({ ready: false });
  const permissionSource = useCallback<PermissionTargetSource>((onState) => {
    listeners.current.add(onState);
    onState(targetState.current);
    return () => {
      listeners.current.delete(onState);
    };
  }, []);

  const askPermission = async (target?: PermissionTarget) => {
    gate.opened();
    try {
      gate.settled(
        await present(PermissionScreen, {
          sessionId: session.id,
          generation: cursor.current.generation,
          target,
          source: permissionSource,
        }),
      );
    } catch {
      gate.settled({ status: 'cancelled' });
    }
  };

  // Opening on entry beats waiting for the replica: the sheet resolves its own
  // target through `permissionSource` once the transcript arrives.
  useEffect(() => {
    if (session.awaitingUserSince != null) void askPermission();
  }, []);

  useEffect(() => {
    const ready = snapshot.status === 'live';
    const target = ready ? firstPermissionTarget(snapshot.entries) : undefined;
    targetState.current = { ready, target };
    for (const notify of listeners.current) notify(targetState.current);
    if (target && gate.shouldOpen(target)) void askPermission(target);
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
    const target = firstPermissionTarget([{ ...entry, items: [item] }]);
    if (target) {
      void askPermission(target);
      return;
    }
    void present(ItemDetailScreen, {
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
  const openFile = useOpenFile(session.id);
  const openProcess = useProcessSheet(entriesJSON, onActivityPress, session.id);
  let notice = '';
  if (overflow) notice = t('chat.notice.syncStopped');
  else if (disconnected && !send.sending)
    notice = t('chat.notice.connectionPaused');
  const control = useSessionControl(
    currentSession,
    snapshot,
    overflow,
    capability?.steer === true,
  );
  const mentions = useComposerMentions(
    selected && account
      ? {
          workspaceId: selected.id,
          sessionId: currentSession.id,
          cliType: currentSession.cliType,
          agentType: currentSession.agentType,
        }
      : undefined,
    present,
  );
  const composerJSON = JSON.stringify({
    editable: !currentSession.archived,
    canSend: send.canSend,
    sending: send.sending,
    running: control.running || send.awaitingReply,
    canStop: control.canStop,
    stopping: control.stopping,
    controlling: control.controlling,
    steerID: control.steerID,
    steerInterrupts: control.steerInterrupts,
    notice,
    reconnect: disconnected || overflow,
    placeholder: composerPlaceholder({
      archived: currentSession.archived,
      disconnected,
      overflow,
      live: snapshot.status === 'live',
    }),
  });
  const efforts = effortsFor(capability, activeChoice.modelId);
  const composerOptionsJSON = JSON.stringify({
    fast: fastModeFor(capability, activeChoice)?.enabled,
    modelId: activeChoice.modelId ?? '',
    effort: activeChoice.effort ?? '',
    models: (capability?.models ?? []).map((item) => ({
      id: item.id,
      title: item.name,
    })),
    efforts: efforts.map((id) => ({ id, title: id })),
  });
  const openProjectFiles = () => {
    if (!browsable || !account || !selected) return;
    void present(FilesScreen, {
      workspaceId: selected.id,
      sessionId: session.id,
      userId: account.user.id,
      path: '',
      title: project?.name ?? t('session.action.projectFiles'),
    });
  };
  const showDetails = () => {
    const body = sessionDebugText({
      session: currentSession,
      project,
      machineName,
      workspace: selected,
      userId: account?.user.id,
      connection,
      transcript: {
        status: snapshot.status,
        revision: snapshot.revision,
        overflow,
      },
      choice: activeChoice,
    });
    Alert.alert(t('session.debug.title'), body, [
      { text: t('common.copy'), onPress: () => copyText(body) },
      { text: t('common.ok'), style: 'cancel' },
    ]);
  };
  return (
    <RNView style={{ flex: 1, backgroundColor: colors.reading }}>
      <Stack.Screen
        options={{
          title: currentSession.title,
        }}
      />
      <Stack.Toolbar placement="right">
        {pullRequests.length === 1 && (
          <Stack.Toolbar.Button
            accessibilityLabel={`PR #${pullRequests[0].number}`}
            onPress={() => void openPullRequest(pullRequests[0])}
          >
            {`PR #${pullRequests[0].number}`}
            {prAttention ? <Stack.Toolbar.Badge>!</Stack.Toolbar.Badge> : null}
          </Stack.Toolbar.Button>
        )}
        {pullRequests.length > 1 && (
          <Stack.Toolbar.Menu accessibilityLabel={t('pr.pullRequests')}>
            <Stack.Toolbar.Label>{`PR · ${pullRequests.length}`}</Stack.Toolbar.Label>
            {pullRequests.map((pr) => (
              <Stack.Toolbar.MenuAction
                key={pr.url}
                onPress={() => void openPullRequest(pr)}
              >{`${pr.repository} #${pr.number} · ${t(`pr.state.${pr.status}`)}`}</Stack.Toolbar.MenuAction>
            ))}
          </Stack.Toolbar.Menu>
        )}
        <Stack.Toolbar.Menu
          icon="ellipsis"
          accessibilityLabel={t('common.more')}
        >
          <Stack.Toolbar.MenuAction
            icon="square.and.pencil"
            onPress={() => {
              if (selected)
                void requestNewSession(
                  selected.id,
                  catalog,
                  isChatSession(currentSession)
                    ? undefined
                    : currentSession.projectId,
                  isChatSession(currentSession) ? 'chat' : undefined,
                );
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
          {browsable && account ? (
            <Stack.Toolbar.Menu inline>
              <Stack.Toolbar.MenuAction
                icon="folder"
                onPress={openProjectFiles}
              >
                {t('session.action.projectFiles')}
              </Stack.Toolbar.MenuAction>
            </Stack.Toolbar.Menu>
          ) : null}
        </Stack.Toolbar.Menu>
      </Stack.Toolbar>
      <DiffWebViewWarmer />
      <NativeChat
        appendDraftJSON={appendDraftJSON}
        mentionItemsJSON={mentions.mentionItemsJSON}
        mentionResultJSON={mentions.mentionResultJSON}
        onMentionBrowse={mentions.onMentionBrowse}
        navigationTitle={currentSession.title}
        navigationSubtitle={projectName}
        navigationMachine={machineName}
        onTitlePress={showDetails}
        style={{ flex: 1 }}
        attachmentContextJSON={JSON.stringify({
          workspaceId: selected?.id,
          sessionId: session.id,
        })}
        entriesJSON={entriesJSON}
        mentionRepository={
          session.projectId?.startsWith('github:')
            ? session.projectId.slice(7)
            : ''
        }
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
        onStop={control.stop}
        onSteer={({ nativeEvent }) => control.steer(nativeEvent.id)}
        onSend={({ nativeEvent }) =>
          send.submit({
            id: nativeEvent.id,
            text: nativeEvent.text,
            startedAt: nativeEvent.startedAt,
            queue: nativeEvent.queue,
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
              configOptionValues: activeChoice.configOptionValues,
              reasoningEffortConfigId: capability?.reasoningEffortConfigId,
            },
          })
        }
        onActivityPress={({ nativeEvent }) =>
          nativeEvent.itemId
            ? onActivityPress(nativeEvent.entryId, nativeEvent.itemId)
            : openProcess(nativeEvent.entryId, nativeEvent.processStartId)
        }
        onFilePress={({ nativeEvent }) =>
          void openFile(nativeEvent.path, nativeEvent.line)
        }
        onTurnChangesPress={({ nativeEvent }) =>
          onTurnChangesPress(nativeEvent.entryId, nativeEvent.path)
        }
        onRetrySend={send.retry}
        onReconnect={pending?.send.creation ? refresh : reconnect}
        onComposerOptionChange={({ nativeEvent }) => {
          choiceHydrated.current = true;
          if (typeof nativeEvent.fast === 'boolean') {
            setChoice(withFastMode(capability, activeChoice, nativeEvent.fast));
            return;
          }
          setChoice((current) => ({
            ...current,
            modelId: nativeEvent.modelId || undefined,
            effort: nativeEvent.effort || undefined,
          }));
        }}
      />
    </RNView>
  );
}
export const SessionScreen = definePage<SessionParams>({
  id: 'session',
  title: t('session.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from the session list');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
