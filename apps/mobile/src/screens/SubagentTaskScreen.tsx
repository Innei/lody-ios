import { useMemo, useState, useSyncExternalStore } from 'react';
import { StyleSheet, View as RNView } from 'react-native';
import { copyText, NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t } from '@/lib/i18n/index.ts';
import { usePalette } from '@/lib/theme/palette';
import {
  findSessionItem,
  subagentEntries,
  type SubagentTask,
} from '@/features/sessions/subagentHistory';
import type { createProcessSource } from './ProcessScreen';
import { useOpenFile } from '@/hooks/screens/useOpenFile';
import { Screen } from '@/ui/Screen';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { FormGroup } from '@/ui/FormGroup';

export type { SubagentTask };
export type SubagentTaskParams = {
  task: SubagentTask;
  entryId: string;
  sessionId?: string;
  source: ReturnType<typeof createProcessSource>;
  onActivityPress: (entryId: string, itemId: string) => void;
};

const statusKeys = {
  pending: 'native.chat.subagent.pending',
  in_progress: 'native.chat.subagent.running',
  completed: 'native.chat.subagent.completed',
  failed: 'native.chat.subagent.failed',
} as const;

function View() {
  const { params } = usePageRuntime<SubagentTaskParams>();
  const entriesJSON = useSyncExternalStore(
    params.source.subscribe,
    params.source.getSnapshot,
  );
  const item = useMemo(
    () =>
      findSessionItem(
        JSON.parse(entriesJSON),
        params.entryId,
        params.task.itemId,
      ),
    [entriesJSON, params],
  );
  const task =
    item?.type === 'subagent_task' ? (item as SubagentTask) : params.task;
  const openFile = useOpenFile(params.sessionId ?? '');
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
  if (task.run) {
    const history = subagentEntries(params.entryId, task);
    history[0]!.items.unshift({
      itemId: `${task.itemId}:header`,
      rev: task.rev,
      type: 'text',
      text: `${[actor, status].filter(Boolean).join(' · ')}\n\n${task.description?.trim() || actor}`,
    });
    return (
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON={JSON.stringify(history)}
        processEntryId={params.entryId}
        processStartId="__subagent__"
        composerJSON="{}"
        clearDraftToken={0}
        emptyText={t('process.empty')}
        onSend={() => {}}
        onReconnect={() => {}}
        onActivityPress={({ nativeEvent }) =>
          params.onActivityPress(nativeEvent.entryId, nativeEvent.itemId)
        }
        onFilePress={({ nativeEvent }) =>
          void openFile(nativeEvent.path, nativeEvent.line)
        }
      />
    );
  }
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
  panel: true,
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
