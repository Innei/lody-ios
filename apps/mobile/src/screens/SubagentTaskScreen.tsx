import { useMemo, useState } from 'react';
import { ActivityIndicator, StyleSheet, View as RNView } from 'react-native';
import { copyText, NativeChat, NativeNavigationHeader } from '@lody-ios/kit';
import { definePage, presentationHeaderHeight } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t } from '@/lib/i18n/index.ts';
import { usePalette } from '@/lib/theme/palette';
import type { ItemSummary } from '@lody/cloud-runtime/models/session';
import { Screen } from '@/ui/Screen';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { FormGroup } from '@/ui/FormGroup';
import type {
  SubagentIdentity,
  SubagentState,
} from '@lody/cloud-runtime/models/subagent-history';
import { subagentIdentityKey } from '@lody/cloud-runtime/models/subagent-history';
import { useSubagentHistory } from '@/features/subagent-history/useSubagentHistory';
import { subagentTranscript } from '@/features/subagent-history/transcript';
import {
  createSubagentHistoryService,
  type SubagentHistoryService,
  type SubagentHistoryScope,
} from '@/cloud/subagent-history';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';
import { useOpenFile } from '@/hooks/screens/useOpenFile';
import { SubagentHistoryToolScreen } from './SubagentHistoryToolScreen';

export type SubagentTask = Extract<ItemSummary, { type: 'subagent_task' }>;
export type SubagentTaskParams = {
  task: SubagentTask;
  identity?: SubagentIdentity;
  scope?: SubagentHistoryScope;
  service?: SubagentHistoryService;
};

const statusKeys = {
  pending: 'native.chat.subagent.pending',
  in_progress: 'native.chat.subagent.running',
  running: 'native.chat.subagent.running',
  completed: 'native.chat.subagent.completed',
  failed: 'native.chat.subagent.failed',
  cancelled: 'subagent.history.cancelled',
  unknown: 'subagent.history.unknown',
} as const;

export function subagentStateLabel(state: string) {
  const key = statusKeys[state as keyof typeof statusKeys];
  return t(key ?? 'subagent.history.unknown');
}

function Summary({ task, note }: { task: SubagentTask; note?: string }) {
  const colors = usePalette();
  const [copied, setCopied] = useState(false);
  const failed = task.status === 'failed';
  const actor = task.actor?.trim() || t('native.chat.transcript.subtask');
  const result = (failed ? task.error : task.summary)?.trim() ?? '';
  const status = [
    subagentStateLabel(task.run?.snapshot.state ?? task.status),
    task.isBackgrounded ? t('native.chat.subagent.background') : '',
  ]
    .filter(Boolean)
    .join(' · ');
  return (
    <Screen>
      {note ? (
        <AppText testID="subagent-history-state" variant="secondary">
          {note}
        </AppText>
      ) : null}
      <FormGroup>
        <RNView style={styles.header}>
          <AppText
            variant="meta"
            style={failed ? { color: colors.danger } : undefined}
          >
            {[actor, status].filter(Boolean).join(' · ')}
          </AppText>
          <AppText variant="title" selectable>
            {task.description?.trim() || actor}
          </AppText>
        </RNView>
      </FormGroup>
      {!!result && (
        <FormGroup
          header={t(
            failed ? 'subagent.detail.error' : 'subagent.detail.result',
          )}
        >
          <AppText
            testID="subagent-detail-result"
            selectable
            style={[styles.body, failed ? { color: colors.danger } : undefined]}
          >
            {result}
          </AppText>
        </FormGroup>
      )}
      {!!result && (
        <Button
          testID="subagent-detail-copy"
          label={t(copied ? 'subagent.detail.copied' : 'subagent.detail.copy')}
          onPress={() => {
            copyText(result);
            setCopied(true);
          }}
        />
      )}
      {task.lastToolName ? (
        <FormGroup>
          <RNView style={styles.row}>
            <AppText>{t('subagent.detail.lastTool')}</AppText>
            <AppText variant="secondary">{task.lastToolName}</AppText>
          </RNView>
        </FormGroup>
      ) : null}
    </Screen>
  );
}

function SummaryView() {
  const { params } = usePageRuntime<SubagentTask>();
  return <Summary task={params} />;
}

function History({
  task: initial,
  identity,
  scope,
  service,
}: SubagentTaskParams & {
  identity: SubagentIdentity;
  service: SubagentHistoryService;
}) {
  const history = useSubagentHistory(identity, service);
  const page = history.page;
  const task = page?.task ?? initial;
  const state = (task.run?.snapshot.state ?? 'unknown') as SubagentState;
  const runtime = usePageRuntime<SubagentTaskParams>();
  const colors = usePalette();
  const openFile = useOpenFile(identity.sessionId);
  const entries = useMemo(
    () => subagentTranscript(task.taskId, history.fragments, state),
    [task.taskId, history.fragments, state],
  );
  const entriesJSON = useMemo(() => JSON.stringify(entries), [entries]);
  const openItem = (_entryId: string, itemId: string) => {
    const fragment = history.fragments.find(
      (value) => value.item.itemId === itemId,
    );
    if (!fragment || fragment.item.type !== 'tool_call' || !history.identity)
      return;
    void runtime.push(SubagentHistoryToolScreen, {
      identity: history.identity,
      index: fragment.index,
      service: history.service,
    });
  };
  const openProcess = useProcessSheet(
    entriesJSON,
    openItem,
    identity.sessionId,
  );
  const actor = task.actor?.trim() || t('native.chat.transcript.subtask');
  const description = task.description?.trim() || actor;
  let note = '';
  if (history.paused) note = t('subagent.history.paused');
  else if (history.status === 'loading') note = t('subagent.history.loading');
  else if (history.status === 'failed') note = t('subagent.history.failed');
  else if (!history.fragments.length) {
    if (!task.run?.snapshot.support.stream.length)
      note = t('subagent.history.unsupported');
    else if (state === 'running' || state === 'pending')
      note = t('subagent.history.waiting');
    else note = t('subagent.history.empty');
  }
  const runs = page?.runs ?? [];
  const selectedKey = history.identity
    ? subagentIdentityKey(history.identity)
    : '';
  const actions = [
    {
      type: 'button' as const,
      icon: { type: 'sfSymbol' as const, name: 'info.circle' },
      accessibilityLabel: t('subagent.history.details'),
      onPress: () => void runtime.push(SubagentTaskSummaryScreen, task),
    },
  ];
  const runItems = runs.map((run, index) => ({
    type: 'action' as const,
    title: t('subagent.history.run', {
      number: index + 1,
      state: subagentStateLabel(run.state),
    }),
    state:
      subagentIdentityKey(run.identity) === selectedKey
        ? ('on' as const)
        : ('off' as const),
    onPress: () => void history.controller.select(run.identity),
  }));
  const headerItems =
    runs.length > 1
      ? [
          {
            type: 'menu' as const,
            title: t('subagent.history.runs'),
            accessibilityLabel: t('subagent.history.runs'),
            menu: {
              items: runItems,
            },
          },
          ...actions,
        ]
      : actions;
  const closeItems = [
    {
      type: 'button' as const,
      systemItem: 'close' as const,
      accessibilityLabel: t('accessibility.closeSheet', {
        title: t('native.chat.transcript.subtask'),
      }),
      onPress: runtime.cancel,
    },
  ];

  if (history.status === 'unsupported') {
    return (
      <>
        <NativeNavigationHeader items={headerItems} leftItems={closeItems} />
        <Summary task={task} note={t('subagent.history.unsupported')} />
      </>
    );
  }
  return (
    <RNView style={{ flex: 1 }}>
      <NativeNavigationHeader items={headerItems} leftItems={closeItems} />
      <RNView style={styles.historyHeader}>
        <AppText testID="subagent-history-description" numberOfLines={2}>
          {description}
        </AppText>
        <AppText testID="subagent-history-status" variant="meta">
          {subagentStateLabel(state)}
        </AppText>
        {!!note && (
          <AppText
            testID="subagent-history-state"
            variant="secondary"
            style={
              history.status === 'failed' ? { color: colors.danger } : undefined
            }
          >
            {note}
          </AppText>
        )}
        {page?.incomplete ? (
          <AppText testID="subagent-history-incomplete" variant="meta">
            {t('subagent.history.incomplete')}
          </AppText>
        ) : null}
        {history.status === 'loading' ? <ActivityIndicator /> : null}
        {history.error ? (
          <Button
            testID="subagent-history-retry"
            label={t('common.retry')}
            onPress={() => void history.controller.retry()}
          />
        ) : null}
        {!!page?.nextCursor && (
          <Button
            testID="subagent-history-more"
            label={t(
              history.loadingMore
                ? 'subagent.history.loading'
                : 'subagent.history.earlier',
            )}
            disabled={history.loadingMore}
            onPress={() => void history.controller.loadMore()}
          />
        )}
      </RNView>
      <NativeChat
        key={selectedKey}
        testID="subagent-history-transcript"
        style={{ flex: 1 }}
        readOnly
        attachmentContextJSON={JSON.stringify({
          workspaceId: scope?.workspaceId,
          sessionId: identity.sessionId,
        })}
        entriesJSON={entriesJSON}
        composerJSON="{}"
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onActivityPress={({ nativeEvent }) =>
          nativeEvent.itemId
            ? openItem(nativeEvent.entryId, nativeEvent.itemId)
            : openProcess(nativeEvent.entryId, nativeEvent.processStartId)
        }
        onFilePress={({ nativeEvent }) =>
          void openFile(nativeEvent.path, nativeEvent.line)
        }
        onReconnect={() => void history.controller.retry()}
      />
    </RNView>
  );
}

function View() {
  const { params } = usePageRuntime<SubagentTaskParams>();
  const service = useMemo(
    () =>
      params.service ??
      createSubagentHistoryService(
        params.scope ?? { workspaceId: '', userId: '' },
      ),
    [params.service, params.scope],
  );
  if (!params.identity)
    return (
      <Summary task={params.task} note={t('subagent.history.unsupported')} />
    );
  return <History {...params} identity={params.identity} service={service} />;
}

const styles = StyleSheet.create({
  header: { padding: 16, gap: 6 },
  body: { padding: 16 },
  row: {
    minHeight: 44,
    paddingHorizontal: 16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  historyHeader: {
    paddingTop: presentationHeaderHeight + 8,
    paddingHorizontal: 16,
    paddingBottom: 8,
    gap: 5,
  },
});

export const SubagentTaskScreen = definePage<SubagentTaskParams>({
  id: 'subagent-task',
  title: t('native.chat.transcript.subtask'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from a subtask card');
  },
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [0.75, 1],
    sheetInitialDetentIndex: 1,
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});

const SubagentTaskSummaryScreen = definePage<SubagentTask>({
  id: 'subagent-task-summary',
  title: t('subagent.history.details'),
  Component: SummaryView,
  parseRouteParams: () => {
    throw new Error('Open from a subtask record');
  },
});
