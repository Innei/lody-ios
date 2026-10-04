import { useState } from 'react';
import { StyleSheet, View as RNView } from 'react-native';
import { copyText } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t } from '@/lib/i18n/index.ts';
import { usePalette } from '@/lib/theme/palette';
import type { ItemSummary } from '@/models/session';
import { Screen } from '@/ui/Screen';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { FormGroup } from '@/ui/FormGroup';

export type SubagentTask = Extract<ItemSummary, { type: 'subagent_task' }>;

const statusKeys = {
  pending: 'native.chat.subagent.pending',
  in_progress: 'native.chat.subagent.running',
  completed: 'native.chat.subagent.completed',
  failed: 'native.chat.subagent.failed',
} as const;

function View() {
  const { params: task } = usePageRuntime<SubagentTask>();
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

export const SubagentTaskScreen = definePage<SubagentTask>({
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
