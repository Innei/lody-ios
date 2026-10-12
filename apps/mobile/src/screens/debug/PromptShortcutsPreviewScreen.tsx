import { useEffect, useMemo, useRef, useState } from 'react';
import { View as RNView } from 'react-native';
import { NativeChat, NativeCreateSession, uuid } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useComposerMentions } from '@/hooks/screens/useComposerMentions';
import { usePalette } from '@/lib/theme/palette';
import { usePendingSends } from '@/cloud/send/pendingSends';
import { useSessionSend } from '@/features/sessions/useSessionSend';
import { pendingSessionFromDraft } from '@/features/sessions/createDraft';
import {
  makePromptShortcutFixture,
  shortcutFixtureOptions,
} from '@/features/prompt-shortcuts/fixture';
import { PromptShortcutsView } from '../PromptShortcutsScreen';
import { Button } from '@/ui/Button';
import { AppText } from '@/ui/AppText';
import type { Session } from '@lody/cloud-runtime/models/catalog';
import type { Snapshot } from '@lody/cloud-runtime/models/session';
import type { MentionSource } from '@lody/cloud-runtime/models/mentions';

function View() {
  const { present } = usePageRuntime();
  const [fixture] = useState(makePromptShortcutFixture);
  const [offline, setOffline] = useState(false);
  const [revision, setRevision] = useState(0);
  const colors = usePalette();
  return (
    <RNView style={{ flex: 1, backgroundColor: colors.background }}>
      <RNView
        style={{
          paddingTop: 105,
          paddingHorizontal: 16,
          flexDirection: 'row',
          gap: 16,
        }}
      >
        <Button
          testID="shortcut-fixture-chat"
          onPress={() =>
            void present(
              PromptShortcutComposerPreviewScreen,
              { host: 'chat' },
              { title: 'Prompt Shortcuts · Chat' },
            )
          }
        >
          Chat
        </Button>
        <Button
          testID="shortcut-fixture-create"
          onPress={() =>
            void present(
              PromptShortcutComposerPreviewScreen,
              { host: 'create' },
              {
                style: 'formSheet',
                headerShown: false,
                sheetAllowedDetents: [1],
              },
            )
          }
        >
          Create
        </Button>
        <Button
          testID="shortcut-fixture-offline"
          onPress={() => {
            fixture.setOffline(!offline);
            setOffline(!offline);
            setRevision((value) => value + 1);
          }}
        >
          {offline ? 'Reconnect' : 'Offline'}
        </Button>
        <Button
          testID="shortcut-fixture-reset"
          onPress={() => {
            fixture.reset();
            setOffline(false);
            setRevision((value) => value + 1);
          }}
        >
          Reset
        </Button>
      </RNView>
      <AppText
        testID="shortcut-fixture-ready"
        variant="meta"
        style={{ padding: 16 }}
      >
        {offline ? 'Offline fixture' : 'Workspace Shortcuts fixture ready'}
      </AppText>
      <PromptShortcutsView
        key={revision}
        workspaceId={fixture.workspaceId}
        userId={fixture.userId}
        options={shortcutFixtureOptions}
        service={fixture.service}
        loadMentions={fixture.mentions}
        fixture
      />
    </RNView>
  );
}
type ComposerParams = { host: 'chat' | 'create' };
function Composer() {
  const { params, present, cancel } = usePageRuntime<ComposerParams>();
  const [fixture] = useState(makePromptShortcutFixture);
  const colors = usePalette();
  const [source, setSource] = useState<MentionSource>(fixture.source);
  const mentions = useComposerMentions(source, present, fixture.mentions);
  const session = useMemo<Session>(
    () => ({
      id: uuid.v4(),
      projectId: 'ui:local:alpha',
      machineId: 'ui',
      title: 'Prompt Shortcut',
      cliType: 'builtin',
      agentType: 'codex',
      agentConfigId: 'fixture-agent',
      status: 'idle',
      archived: false,
      pinned: false,
      createdAt: new Date().toISOString(),
    }),
    [params.host],
  );
  const snapshot: Snapshot = { status: 'live', revision: 1, entries: [] };
  const outbox = usePendingSends(fixture.userId, fixture.workspaceId);
  const record = outbox.records.find(
    (record) => record.session.id === session.id,
  );
  const [expanded, setExpanded] = useState('');
  const [responses, setResponses] = useState<object[]>([]);
  const [revision, setRevision] = useState(0);
  const [offline, setOffline] = useState(false);
  const [restoreToken, setRestoreToken] = useState(0);
  useEffect(() => {
    if (record?.send.phase === 'failed') setRestoreToken((value) => value + 1);
  }, [record?.send.id, record?.send.phase]);
  const sourceRef = useRef(source);
  sourceRef.current = source;
  const services = useRef({
    ensureSession: async () => {},
    createSession: async () => JSON.stringify({ state: 'created', session }),
    sendSessionTurn: async (payload: string) => {
      const args = JSON.parse(payload);
      try {
        const text = await fixture.expand(args.text, sourceRef.current);
        setExpanded(text);
        return JSON.stringify({ state: 'accepted' });
      } catch (cause) {
        return JSON.stringify({
          state: 'not_sent',
          reason: String(cause).replace(/^Error: /, ''),
        });
      }
    },
  }).current;
  const send = useSessionSend({
    outbox,
    session,
    record,
    snapshot,
    connected: true,
    serverCreated: true,
    userId: fixture.userId,
    overflow: false,
    services,
  });
  useEffect(
    () => () => {
      void outbox.remove(session.id).catch(() => {});
    },
    [outbox.remove, session.id],
  );
  const header = (
    <RNView
      style={{
        paddingTop: params.host === 'chat' ? 105 : 60,
        paddingHorizontal: 16,
        gap: 8,
      }}
    >
      <RNView style={{ flexDirection: 'row', gap: 16 }}>
        <Button
          testID="shortcut-composer-close"
          disabled={send.sending}
          onPress={cancel}
        >
          Close
        </Button>
        <Button
          testID="shortcut-composer-delete"
          onPress={() => fixture.deleteSelected()}
        >
          Delete Selected Shortcut
        </Button>
        <Button
          testID="shortcut-composer-offline"
          onPress={() => {
            fixture.setOffline(!offline);
            setOffline(!offline);
          }}
        >
          {offline ? 'Reconnect' : 'Offline'}
        </Button>
        <Button
          testID="shortcut-composer-reset"
          onPress={async () => {
            await outbox.remove(session.id);
            fixture.reset();
            setOffline(false);
            setExpanded('');
            setRevision((value) => value + 1);
          }}
        >
          Reset
        </Button>
      </RNView>
      <AppText
        testID="shortcut-composer-ready"
        variant="meta"
      >{`Shortcut ${params.host} ready · ${record?.send.phase ?? 'idle'}`}</AppText>
      {!!expanded && (
        <AppText testID="shortcut-expanded-text" variant="meta">
          {expanded}
        </AppText>
      )}
    </RNView>
  );
  if (params.host === 'create')
    return (
      <RNView style={{ flex: 1, backgroundColor: colors.background }}>
        {header}
        <NativeCreateSession
          key={revision}
          style={{ flex: 1 }}
          configJSON={JSON.stringify({
            userId: fixture.userId,
            workspaceId: fixture.workspaceId,
            projects: [
              {
                id: session.projectId,
                name: 'Alpha',
                machineId: 'ui',
                rootPath: '/fixture',
              },
            ],
            projectId: session.projectId,
            context: 'project',
            prefs: {},
            persistShare: false,
          })}
          responseJSON={JSON.stringify(responses)}
          mentionItemsJSON={mentions.mentionItemsJSON}
          mentionResultJSON={mentions.mentionResultJSON}
          onMentionBrowse={mentions.onMentionBrowse}
          onRequest={({ nativeEvent }) => {
            const value = {
              sessionId: session.id,
              project: {
                id: session.projectId,
                name: 'Alpha',
                machineId: 'ui',
                rootPath: '/fixture',
              },
              agents: [
                {
                  id: 'fixture-agent',
                  name: 'Codex',
                  machineId: 'ui',
                  machineName: 'Fixture Mac',
                  cliType: 'builtin',
                  agentType: 'codex',
                },
              ],
              capabilities: [],
            };
            setResponses((old) => [
              ...old.slice(-15),
              { id: nativeEvent.id, value: JSON.stringify(value) },
            ]);
          }}
          onPrefs={() => {}}
          onSelection={({ nativeEvent }) =>
            setSource({ ...nativeEvent, sessionId: undefined })
          }
          onSubmit={({ nativeEvent }) => {
            const { record } = pendingSessionFromDraft(
              JSON.parse(nativeEvent.draft),
              nativeEvent.payload,
            );
            void outbox.put(record);
          }}
          restoreDraftToken={send.restoreDraftToken + restoreToken}
          onCancel={cancel}
        />
      </RNView>
    );
  return (
    <RNView style={{ flex: 1, backgroundColor: colors.background }}>
      {header}
      <NativeChat
        key={revision}
        style={{ flex: 1 }}
        entriesJSON="[]"
        composerJSON={JSON.stringify({
          editable: true,
          canSend: send.canSend,
          sending: send.sending,
          running: false,
          notice: '',
          reconnect: false,
          placeholder: 'Message',
        })}
        mentionItemsJSON={mentions.mentionItemsJSON}
        mentionResultJSON={mentions.mentionResultJSON}
        onMentionBrowse={mentions.onMentionBrowse}
        pendingSendJSON={send.pendingSendJSON}
        clearDraftToken={send.clearDraftToken}
        restoreDraftToken={send.restoreDraftToken}
        emptyText="Try @ or /"
        onSend={({ nativeEvent }) =>
          send.submit({ ...nativeEvent, choice: {}, phase: 'waiting' })
        }
        onRetrySend={send.retry}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </RNView>
  );
}
export const PromptShortcutsPreviewScreen = definePage({
  id: 'prompt-shortcuts-preview',
  title: 'Prompt Shortcuts',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
export const PromptShortcutComposerPreviewScreen = definePage<ComposerParams>({
  id: 'prompt-shortcut-composer-preview',
  title: 'Prompt Shortcuts',
  Component: Composer,
  parseRouteParams: () => {
    throw new Error('Open the Shortcut fixture');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
