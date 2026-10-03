import { useState, useSyncExternalStore } from 'react';
import { StyleSheet, View as RNView } from 'react-native';
import { copyText, NativeChat } from '@lody-ios/kit';
import { definePage, presentationHeaderHeight } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';
import { t } from '@/lib/i18n/index.ts';
import { usePalette } from '@/lib/theme/palette';
import {
  liveTask,
  runEntries,
  runMeta,
  type SubagentTask,
} from '@/features/sessions/subagentRun';
import { Screen } from '@/ui/Screen';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { FormGroup } from '@/ui/FormGroup';
import type { createProcessSource } from './ProcessScreen';

export type { SubagentTask };
export type SubagentTaskParams = SubagentTask & {
  entryId?: string;
  source?: ReturnType<typeof createProcessSource>;
  onStop?: (task: SubagentTask) => void;
};
const noSource = { subscribe: () => () => {}, getSnapshot: () => '[]' };

const statusKeys = {
  pending: 'native.chat.subagent.pending',
  in_progress: 'native.chat.subagent.running',
  completed: 'native.chat.subagent.completed',
  failed: 'native.chat.subagent.failed',
  cancelled: 'native.chat.subagent.cancelled',
  unknown: 'native.chat.subagent.unknown',
} as const;
const runStatus: Record<string, keyof typeof statusKeys> = {
  running: 'in_progress',
  pending: 'pending',
  completed: 'completed',
  failed: 'failed',
  cancelled: 'cancelled',
  unknown: 'unknown',
};

function View() {
  const { params } = usePageRuntime<SubagentTaskParams>();
  const source = params.source ?? noSource;
  const json = useSyncExternalStore(source.subscribe, source.getSnapshot);
  const task = params.entryId ? liveTask(params, params.entryId, json) : params;
  if (task.run) return <RunView task={task} onStop={params.onStop} />;
  return <SummaryView task={task} />;
}

function RunView({
  task,
  onStop,
}: {
  task: SubagentTask;
  onStop?: (task: SubagentTask) => void;
}) {
  const colors = usePalette();
  const run = task.run!;
  const entriesJSON = JSON.stringify(runEntries(task));
  const openProcess = useProcessSheet(entriesJSON, () => {});
  const running = run.state === 'running' || run.state === 'pending';
  const statusKey = statusKeys[runStatus[run.state] ?? 'unknown'];
  const actor = task.actor?.trim() || t('native.chat.transcript.subtask');
  return (
    <RNView style={{ flex: 1 }}>
      <RNView style={styles.runHeader}>
        <RNView style={styles.runTitle}>
          <AppText
            variant="meta"
            style={{ flex: 1 }}
            testID="subagent-run-status"
          >
            {[actor, t(statusKey)].join(' · ')}
          </AppText>
          {running && run.cancel && onStop ? (
            <Button
              testID="subagent-run-stop"
              label={t('subagent.run.stop')}
              destructive
              onPress={() => onStop(task)}
            />
          ) : null}
        </RNView>
        {task.description ? (
          <AppText selectable>{task.description}</AppText>
        ) : null}
        {runMeta(task) ? (
          <AppText variant="secondary">{runMeta(task)}</AppText>
        ) : null}
        {run.outputIncomplete ? (
          <AppText variant="secondary" testID="subagent-run-incomplete">
            {t('subagent.run.incomplete')}
          </AppText>
        ) : null}
      </RNView>
      <NativeChat
        style={{ flex: 1, backgroundColor: colors.reading }}
        entriesJSON={entriesJSON}
        composerJSON="{}"
        composerHidden
        clearDraftToken={0}
        emptyText={running ? t('subagent.run.silent') : ''}
        onSend={() => {}}
        onActivityPress={({ nativeEvent }) =>
          openProcess(nativeEvent.entryId, nativeEvent.processStartId)
        }
        onReconnect={() => {}}
      />
    </RNView>
  );
}

function SummaryView({ task }: { task: SubagentTask }) {
  const colors = usePalette();
  const [copied, setCopied] = useState(false);
  const failed = task.status === 'failed';
  const actor = task.actor?.trim() || t('native.chat.transcript.subtask');
  const result = (failed ? task.error : task.summary)?.trim() ?? '';
  const statusKey = statusKeys[task.status as keyof typeof statusKeys];
  const status = [
    statusKey ? t(statusKey) : '',
    task.isBackgrounded ? t('native.chat.subagent.background') : '',
  ]
    .filter(Boolean)
    .join(' · ');
  return (
    <Screen>
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
      {result ? (
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
      ) : null}
      {result ? (
        <Button
          testID="subagent-detail-copy"
          label={t(copied ? 'subagent.detail.copied' : 'subagent.detail.copy')}
          onPress={() => {
            copyText(result);
            setCopied(true);
          }}
        />
      ) : null}
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

const styles = StyleSheet.create({
  runHeader: {
    paddingHorizontal: 20,
    paddingTop: presentationHeaderHeight + 12,
    paddingBottom: 8,
    gap: 6,
  },
  runTitle: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  header: { padding: 16, gap: 6 },
  body: { padding: 16 },
  row: {
    minHeight: 44,
    paddingHorizontal: 16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
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
    sheetAllowedDetents: [0.6, 1],
    sheetInitialDetentIndex: 0,
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
