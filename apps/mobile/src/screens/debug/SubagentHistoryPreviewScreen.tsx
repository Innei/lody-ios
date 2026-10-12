import { useEffect, useMemo, useState, useSyncExternalStore } from 'react';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { NativeChat, NativeNavigationHeader } from '@lody-ios/kit';
import {
  definePage,
  present,
  presentationHeaderHeight,
} from '@/lib/presentation';
import { AppText } from '@/ui/AppText';
import type {
  SubagentHistoryService,
  SubagentHistorySignal,
} from '@/cloud/subagent-history';
import type {
  SubagentHistoryFragment,
  SubagentHistoryPage,
  SubagentIdentity,
  SubagentState,
} from '@lody/cloud-runtime/models/subagent-history';
import { SubagentTaskScreen, type SubagentTask } from '../SubagentTaskScreen';

const modes = [
  'loading',
  'running',
  'completed',
  'failed',
  'multiple',
  'pagination',
  'empty',
  'unsupported',
  'truncated',
  'load-failed',
] as const;
type Mode = (typeof modes)[number];
const baseIdentity: SubagentIdentity = {
  sessionId: 'offline-subagent-session',
  parentTurnId: 'offline-parent-turn',
  entryId: 'offline-parent-reply',
  itemId: 'task-one',
  taskId: 'run-one',
  runSessionId: 'offline-acp-root',
};
const support = {
  stream: ['text', 'thought', 'tool', 'plan'] as (
    'text' | 'thought' | 'tool' | 'plan'
  )[],
  progress: true,
  outputRead: 'none' as const,
  cancel: false,
};

function taskFor(
  mode: Mode,
  identity: SubagentIdentity,
  completed = false,
): SubagentTask {
  let state: SubagentState = 'completed';
  if (mode === 'running' && !completed) state = 'running';
  if (
    mode === 'failed' ||
    (mode === 'multiple' && identity.taskId === 'run-two')
  )
    state = 'failed';
  const legacy = mode === 'unsupported';
  const outputIncomplete = mode === 'truncated' ? true : undefined;
  const itemCount = mode === 'empty' ? 0 : 5;
  return {
    itemId: identity.itemId,
    rev: completed ? 2 : 1,
    type: 'subagent_task',
    taskId: identity.taskId,
    actor: 'Source inspector',
    description: 'Inspect the task execution records',
    status: state === 'running' ? 'in_progress' : state,
    lastToolName: 'Read',
    summary: 'The retained task result is available.',
    error: state === 'failed' ? 'The synthetic check failed.' : undefined,
    run: legacy
      ? undefined
      : {
          sessionId: 'offline-acp-root',
          snapshot: {
            state,
            support,
            outputIncomplete,
          },
          itemCount,
        },
  };
}

function fragmentsFor(
  mode: Mode,
  identity: SubagentIdentity,
  completed: boolean,
): SubagentHistoryFragment[] {
  if (mode === 'empty' || mode === 'unsupported') return [];
  if (mode === 'multiple')
    return [
      {
        index: 0,
        item: {
          itemId: 'run-prose',
          rev: 1,
          type: 'text',
          text:
            identity.taskId === 'run-one'
              ? 'First run result only.'
              : 'Second run result only.',
        },
      },
    ];
  const items: SubagentHistoryFragment[] = [
    {
      index: 0,
      item: {
        itemId: 'brief',
        rev: 1,
        type: 'text',
        text: '## Retained execution\n\nI inspected the **shared history**.',
      },
    },
    {
      index: 1,
      item: {
        itemId: 'thought',
        rev: 1,
        type: 'thought',
        text: 'Check that each run keeps its own tool results.',
      },
    },
    {
      index: 2,
      item: {
        itemId: 'plan',
        rev: 1,
        type: 'plan',
        entries: [
          { content: 'Inspect records', status: 'completed' },
          {
            content: 'Verify result',
            status: completed ? 'completed' : 'in_progress',
          },
        ],
      },
    },
    {
      index: 3,
      item: {
        itemId: 'tool',
        rev: 1,
        type: 'tool_call',
        kind: 'execute',
        title: 'Run the history check',
        status: 'completed',
        hasDetail: true,
      },
    },
    {
      index: 4,
      item: {
        itemId: 'result',
        rev: completed ? 2 : 1,
        type: 'text',
        text: completed
          ? 'Live record completed without restarting the task.'
          : 'Waiting for the retained result.',
      },
    },
  ];
  if (mode !== 'pagination') return items;
  return [
    ...Array.from({ length: 32 }, (_, index): SubagentHistoryFragment => ({
      index,
      item: {
        itemId: `older-${index}`,
        rev: 1,
        type: 'text',
        text: `Earlier retained step ${index + 1}.`,
      },
    })),
    ...items.map((fragment) => ({ ...fragment, index: fragment.index + 32 })),
  ];
}

function fixtureService(mode: Mode) {
  const signals = new Set<(event: SubagentHistorySignal) => void>();
  const statsListeners = new Set<() => void>();
  const watched = new Map<string, SubagentIdentity>();
  let completed = mode !== 'running';
  let failedRead = mode === 'load-failed';
  let value = 'Subtask subscriptions: 0';
  const updateStats = () => {
    value = `Subtask subscriptions: ${watched.size}`;
    statsListeners.forEach((listener) => listener());
  };
  const page = (
    identity: SubagentIdentity,
    cursor?: string,
  ): SubagentHistoryPage => {
    if (failedRead) {
      failedRead = false;
      throw new Error('synthetic_read_failed');
    }
    const all = fragmentsFor(mode, identity, completed);
    const end = cursor == null ? all.length : Number(cursor);
    const start = Math.max(0, end - 8);
    const task = taskFor(mode, identity, completed);
    const choices = [baseIdentity];
    if (mode === 'multiple')
      choices.push({ ...baseIdentity, taskId: 'run-two', itemId: 'task-two' });
    return {
      v: 1,
      identity,
      task,
      status: mode === 'unsupported' ? 'unsupported' : 'ready',
      revision: completed ? '2' : '1',
      fragments: all.slice(start, end),
      nextCursor: start > 0 ? String(start) : undefined,
      incomplete: mode === 'truncated',
      runs: choices.map((run) => ({
        identity: run,
        state: taskFor(mode, run, completed).run?.snapshot.state ?? 'completed',
      })),
    };
  };
  const service: SubagentHistoryService = {
    watch: async (id, identity) => {
      if (mode === 'loading')
        await new Promise((resolve) => setTimeout(resolve, 6000));
      const result = page(identity);
      watched.set(id, identity);
      updateStats();
      return result;
    },
    page: async (identity, cursor) => page(identity, cursor),
    detail: async () => {
      // Reading the retained tool outcome advances this offline service, so
      // AX latency cannot finish the run before its running state is observed.
      if (mode === 'running' && !completed) {
        completed = true;
        for (const [subscriptionId, runIdentity] of watched)
          for (const listener of signals)
            listener({
              subscriptionId,
              sessionId: runIdentity.sessionId,
              subagentHistory: 'changed',
              generation: 1,
            });
      }
      return {
        itemId: 'tool',
        rev: 1,
        blocks: [
          {
            type: 'terminal_output',
            output: 'History protocol: PASS',
            exitStatus: { exitCode: 0 },
          },
        ],
        rawInput: { command: 'synthetic-history-check' },
        rawOutput: { result: 'PASS' },
        truncated: false,
      };
    },
    unwatch: async (id) => {
      watched.delete(id);
      updateStats();
    },
    subscribe: (listener) => {
      signals.add(listener);
      return () => {
        signals.delete(listener);
      };
    },
  };
  return {
    service,
    getSnapshot: () => value,
    subscribe(listener: () => void) {
      statsListeners.add(listener);
      return () => {
        statsListeners.delete(listener);
      };
    },
    dispose() {
      watched.clear();
      signals.clear();
    },
  };
}

function Preview() {
  const insets = useSafeAreaInsets();
  const [mode, setMode] = useState<Mode>('running');
  const source = useMemo(() => fixtureService(mode), [mode]);
  const stats = useSyncExternalStore(source.subscribe, source.getSnapshot);
  const task = taskFor(mode, baseIdentity);
  useEffect(() => () => source.dispose(), [source]);
  return (
    <View style={{ flex: 1 }}>
      <NativeNavigationHeader
        items={[
          {
            type: 'menu',
            icon: { type: 'sfSymbol', name: 'ellipsis' },
            accessibilityLabel: 'Subtask fixtures',
            menu: {
              items: modes.map((value) => ({
                type: 'action',
                title: value,
                onPress: () => setMode(value),
              })),
            },
          },
        ]}
      />
      <View
        style={{
          paddingTop: insets.top + presentationHeaderHeight + 8,
          paddingHorizontal: 16,
        }}
      >
        <AppText testID="subagent-history-preview-ready" variant="meta">
          Subtask history fixture · {mode}
        </AppText>
        <AppText testID="subagent-history-subscriptions" variant="meta">
          {stats}
        </AppText>
      </View>
      <NativeChat
        style={{ flex: 1 }}
        readOnly
        entriesJSON={JSON.stringify([
          {
            id: baseIdentity.entryId,
            rev: 1,
            role: 'assistant',
            status: 'completed',
            finished: true,
            items: [task],
          },
        ])}
        composerJSON="{}"
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onReconnect={() => {}}
        onActivityPress={({ nativeEvent }) => {
          if (nativeEvent.itemId === task.itemId)
            void present(SubagentTaskScreen, {
              task,
              identity: baseIdentity,
              scope: {
                workspaceId: 'offline-subagent-workspace',
                userId: 'offline-subagent-user',
              },
              service: source.service,
            });
        }}
      />
    </View>
  );
}

export const SubagentHistoryPreviewScreen = definePage({
  id: 'subagent-history-preview',
  title: 'Subtask History Fixture',
  Component: Preview,
  presentation: { style: 'fullScreen', headerVariant: 'transparent' },
});
