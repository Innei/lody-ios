import { useEffect, useMemo, useState } from 'react';
import { NativeChat, NativeGroupedList } from '@lody-ios/kit';
import type { Session } from '@lody/cloud-runtime/models/catalog';
import type { SessionToolsSource } from '@/cloud/session-tools';
import { definePage, present } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { ForkSessionScreen } from '../ForkSessionScreen';
import { AutoArchiveSettingsView } from '../AutoArchiveSettingsScreen';
import type { AutoArchivePreferences } from '@/features/sessions/autoArchive';
import { inboxSections } from '@/features/sessions/inbox';
import {
  requestOpenSessionFromPage,
  subscribeSessionNav,
} from '@/features/sessions/sessionNav';
import { t } from '@/lib/i18n';
import { showToast } from '@/ui/toast';

const targetSessionId = 'aa62488a-b09c-49a6-8994-303b802b8191';
const session: Session = {
  id: 'session-tools-fixture',
  title: 'Session tools',
  machineId: 'fixture-machine',
  projectId: 'fixture-project',
  status: 'completed',
  archived: false,
  pinned: true,
  createdAt: '2026-10-12T00:00:00Z',
  lastMessageAt: 100,
  lastReadAt: 100,
};
function entries(count: number) {
  return Array.from({ length: count }, (_, index) => ({
    id: `tools-${index}`,
    role: index % 2 === 0 ? 'user' : 'assistant',
    status: 'completed',
    finished: true,
    rev: 1,
    acpTurnId: index % 2 === 1 ? `acp-${index}` : undefined,
    items: [
      {
        itemId: 'text',
        rev: 1,
        type: 'text',
        text: `Message ${index}: Keep the source and this fork independent.`,
      },
    ],
  }));
}
const composerJSON = JSON.stringify({
  editable: false,
  canSend: false,
  sending: false,
  notice: '',
  reconnect: false,
  placeholder: '',
});

function Target() {
  return (
    <NativeChat
      style={{ flex: 1 }}
      readOnly
      entriesJSON={JSON.stringify(entries(2))}
      navigationTitle="Forked conversation"
      composerJSON={composerJSON}
      clearDraftToken={0}
      emptyText=""
      onSend={() => {}}
      onActivityPress={() => {}}
      onReconnect={() => {}}
    />
  );
}
const ForkTargetPreviewScreen = definePage({
  id: 'session-tools-fork-target',
  title: 'Forked conversation',
  Component: Target,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

function forkFixture(
  mode: 'success' | 'dirty' | 'unknown' | 'failed',
  onDispatch = () => {},
): SessionToolsSource {
  let dispatches = 0;
  let checks = 0;
  return async (request) => {
    if (request.action === 'fork-options')
      return {
        action: request.action,
        shared: true,
        newWorktree: true,
        targetSessionId,
      };
    if (request.action === 'fork-status') {
      checks++;
      const state = mode === 'unknown' ? 'unknown' : 'completed';
      return { action: request.action, fork: { targetSessionId, state } };
    }
    if (request.action === 'fork') {
      dispatches++;
      onDispatch();
      if (
        mode === 'dirty' &&
        !request.spec.targetContext.acknowledgeDirtySource
      )
        return {
          action: request.action,
          fork: { targetSessionId, state: 'confirmation-required' },
        };
      if (mode === 'failed' && dispatches === 1)
        return {
          action: request.action,
          fork: {
            targetSessionId,
            state: 'failed',
            code: 'FORK_UNAVAILABLE',
            message: 'Fixture rejection; retry is safe.',
          },
        };
      if (mode === 'unknown')
        return {
          action: request.action,
          fork: {
            targetSessionId,
            state: 'unknown',
            message: `Dispatches ${dispatches}, checks ${checks}`,
          },
        };
      return {
        action: request.action,
        fork: { targetSessionId, state: 'preparing' },
      };
    }
    return { action: request.action, saved: true };
  };
}

function pinFixture(rejectFirst: boolean) {
  return async (historyId: string) => {
    if (rejectFirst) {
      rejectFirst = false;
      throw new Error('pin_fixture_rejected');
    }
    return historyId;
  };
}

type PinnedHistoryParams = { older: boolean; rejectPin?: boolean };
function Chat() {
  const { params } = usePageRuntime<PinnedHistoryParams>();
  const [pin, setPin] = useState(
    params.older || params.rejectPin ? 'tools-0' : '',
  );
  const savePin = useMemo(
    () => pinFixture(params.rejectPin === true),
    [params.rejectPin],
  );
  let count = 2;
  if (params.older) count = 66;
  else if (params.rejectPin) count = 4;
  return (
    <NativeChat
      style={{ flex: 1 }}
      entriesJSON={JSON.stringify(entries(count))}
      navigationTitle="Pinned history"
      pinEnabled
      pinnedHistoryId={pin}
      onPin={async ({ nativeEvent: { entryId } }) => {
        try {
          setPin(await savePin(entryId));
        } catch {
          showToast(t('session.toast.contentPinFailed'));
        }
      }}
      forkEnabled
      onFork={async ({ nativeEvent: { entryId } }) => {
        const result = await present(ForkSessionScreen, {
          workspaceId: 'fixture',
          userId: 'fixture',
          session,
          sourceTurnId: entryId,
          source: forkFixture('success'),
        });
        if (result.status === 'completed')
          void requestOpenSessionFromPage('fixture', 'fixture', {
            ...session,
            id: result.value.targetSessionId,
            title: 'Forked conversation',
          });
      }}
      composerJSON={composerJSON}
      clearDraftToken={0}
      emptyText=""
      onSend={() => {}}
      onActivityPress={() => {}}
      onReconnect={() => {}}
    />
  );
}
const PinnedHistoryPreviewScreen = definePage<PinnedHistoryParams>({
  id: 'session-tools-pin',
  title: 'Pinned history',
  Component: Chat,
  parseRouteParams: () => {
    throw new Error('Open the fixture');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});

function Preferences() {
  const [preferences, setPreferences] = useState<AutoArchivePreferences>({
    onPrMerged: false,
    onPrClosed: false,
  });
  return (
    <AutoArchiveSettingsView
      preferences={preferences}
      update={async (next) => setPreferences(next)}
    />
  );
}
const AutoArchivePreviewScreen = definePage({
  id: 'session-tools-auto-archive',
  title: t('settings.autoArchive.title'),
  Component: Preferences,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

function Receipt() {
  const [readAt, setReadAt] = useState(100);
  const catalog = {
    projects: [],
    machineIds: ['fixture-machine'],
    sessions: [{ ...session, id: 'tools-receipt', lastReadAt: readAt }],
  };
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      sections={inboxSections(catalog, { accent: 'blue', now: 100 })}
      onRowPress={() => {}}
      onRowAction={({ nativeEvent: { actionId } }) => {
        if (actionId === 'unread') setReadAt(99);
        if (actionId === 'read') setReadAt(100);
      }}
    />
  );
}
const ReceiptPreviewScreen = definePage({
  id: 'session-tools-receipt',
  title: 'Read state',
  Component: Receipt,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

function View() {
  const { push } = usePageRuntime();
  const [dispatches, setDispatches] = useState(0);
  useEffect(
    () =>
      subscribeSessionNav(async (intent) => {
        if (intent.kind === 'open-from-page')
          await present(ForkTargetPreviewScreen);
      }),
    [],
  );
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      sections={[
        {
          id: 'session-tools-preview',
          rows: [
            {
              id: 'tools-pin',
              title: 'Pin a message',
              action: true,
              navigates: true,
              disclosure: true,
            },
            {
              id: 'tools-pin-failure',
              title: 'Pin rejected once',
              action: true,
              navigates: true,
              disclosure: true,
            },
            {
              id: 'tools-old-pin',
              title: 'Older pinned message',
              action: true,
              navigates: true,
              disclosure: true,
            },
            { id: 'tools-fork', title: 'Fork conversation', action: true },
            {
              id: 'tools-dirty-fork',
              title: 'Fork dirty worktree',
              action: true,
            },
            {
              id: 'tools-unknown-fork',
              title: 'Fork with lost response',
              action: true,
            },
            {
              id: 'tools-failed-fork',
              title: 'Fork rejected once',
              action: true,
            },
            {
              id: 'tools-unread',
              title: 'Read state',
              action: true,
              navigates: true,
              disclosure: true,
            },
            {
              id: 'tools-auto-archive',
              title: t('settings.autoArchive.title'),
              action: true,
              navigates: true,
              disclosure: true,
            },
            {
              id: 'tools-fork-count',
              title: 'Fork requests',
              value: String(dispatches),
            },
          ],
        },
      ]}
      onRowPress={async ({ nativeEvent: { id } }) => {
        if (['tools-pin', 'tools-pin-failure', 'tools-old-pin'].includes(id)) {
          void push(PinnedHistoryPreviewScreen, {
            older: id === 'tools-old-pin',
            rejectPin: id === 'tools-pin-failure',
          });
          return;
        }
        if (id === 'tools-unread') {
          void push(ReceiptPreviewScreen);
          return;
        }
        if (id === 'tools-auto-archive') {
          void push(AutoArchivePreviewScreen);
          return;
        }
        let mode: Parameters<typeof forkFixture>[0] = 'success';
        if (id === 'tools-dirty-fork') mode = 'dirty';
        if (id === 'tools-unknown-fork') mode = 'unknown';
        if (id === 'tools-failed-fork') mode = 'failed';
        setDispatches(0);
        const result = await present(ForkSessionScreen, {
          workspaceId: 'fixture',
          userId: 'fixture',
          session,
          sourceTurnId: 'tools-1',
          source: forkFixture(mode, () => setDispatches((count) => count + 1)),
        });
        if (result.status === 'completed')
          void requestOpenSessionFromPage('fixture', 'fixture', {
            ...session,
            id: result.value.targetSessionId,
            title: 'Forked conversation',
          });
      }}
    />
  );
}
export const SessionToolsPreviewScreen = definePage({
  id: 'session-tools-preview',
  title: 'Session tools',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
