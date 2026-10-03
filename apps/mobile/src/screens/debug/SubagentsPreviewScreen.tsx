import { useEffect, useLayoutEffect, useMemo, useState } from 'react';
import { View as RNView } from 'react-native';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';
import { openSubagentTask } from '@/hooks/screens/openSubagentTask';
import { createProcessSource } from '@/screens/ProcessScreen';
import type { ItemSummary } from '@/models/session';

const steps = [
  { type: 'thought', text: 'Find every caller of verifyToken first.' },
  {
    type: 'tool_call',
    kind: 'search',
    status: 'completed',
    title: 'Grep verifyToken src/',
  },
  {
    type: 'tool_call',
    kind: 'read',
    status: 'completed',
    title: 'Read src/middleware/session.ts',
  },
  {
    type: 'text',
    text: 'Six callers run inside the middleware. Two of them, `guardRedirect` and `refreshSession`, touch the cookie in the wrong order.',
  },
  {
    type: 'tool_call',
    kind: 'read',
    status: 'in_progress',
    title: 'Read src/auth/guard.ts',
  },
];

const runItems = (count: number) =>
  steps.slice(0, count).map((step, index) => ({
    itemId: `explore-${index}`,
    rev: 1,
    ...step,
    status:
      step.type === 'tool_call' && index < count - 1
        ? 'completed'
        : step.status,
  }));

function task(itemId: string, extra: Record<string, unknown>) {
  return { itemId, rev: 1, type: 'subagent_task', taskId: itemId, ...extra };
}

function entries(progress: number, stopped: boolean) {
  const exploreState = stopped ? 'cancelled' : 'running';
  return [
    {
      id: 'agents-user',
      role: 'user',
      status: 'completed',
      finished: true,
      items: [
        {
          itemId: 'text',
          type: 'text',
          text: 'Audit every token refresh path before we ship.',
        },
      ],
    },
    {
      id: 'agents-reply',
      role: 'assistant',
      status: 'running',
      finished: false,
      items: [
        {
          itemId: 'intro',
          type: 'text',
          text: "I'll split this into parallel investigations.",
        },
        task('explore', {
          status: stopped ? 'failed' : 'in_progress',
          actor: 'Explore',
          description: 'Map every caller of verifyToken',
          run: {
            state: exploreState,
            modelId: 'gpt-5-codex',
            outputIncomplete: true,
            cancel: true,
            totalTokens: 900 + progress * 450,
            toolCallCount: Math.max(0, progress - 1),
            contextUsagePercent: 6 + progress * 3,
            items: runItems(progress),
          },
        }),
        task('reviewer', {
          status: 'completed',
          actor: 'code-reviewer',
          description: 'Review session middleware for refresh races',
          isBackgrounded: true,
          summary:
            'Found two races: the refresh clears the cookie before guardRedirect reads it, and parallel refreshes write a stale expiry.',
          run: {
            state: 'completed',
            modelId: 'claude-sonnet-5-5',
            totalTokens: 6200,
            toolCallCount: 9,
            items: [
              {
                itemId: 'r0',
                rev: 1,
                type: 'thought',
                text: 'Check write order.',
              },
              {
                itemId: 'r1',
                rev: 1,
                type: 'tool_call',
                kind: 'read',
                status: 'completed',
                title: 'Read middleware/session.ts',
              },
              {
                itemId: 'r2',
                rev: 1,
                type: 'text',
                text: 'Found two races in `middleware/session.ts`.',
              },
            ],
          },
        }),
        task('tests', {
          status: 'failed',
          actor: 'test-runner',
          description: 'Run the auth specs',
          error: 'jest exited with code 1',
        }),
        task('docs', {
          status: 'failed',
          actor: 'doc-writer',
          description: 'Draft the migration note',
          run: { state: 'cancelled', items: [] },
        }),
        task('migrator', {
          status: 'in_progress',
          actor: 'migrator',
          description: 'Backfill session expiry',
          run: { state: 'unknown', items: [] },
        }),
        task('house', {
          status: 'in_progress',
          actor: 'Housekeeping',
          skipTranscript: true,
        }),
      ],
    },
  ];
}

function View() {
  const colors = usePalette();
  const [progress, setProgress] = useState(1);
  const [stopped, setStopped] = useState(false);
  useEffect(() => {
    if (stopped || progress >= steps.length) return;
    const timer = setTimeout(() => setProgress((n) => n + 1), 1500);
    return () => clearTimeout(timer);
  }, [progress, stopped]);
  const list = entries(progress, stopped);
  const entriesJSON = JSON.stringify(list);
  const source = useMemo(() => createProcessSource(entriesJSON), []);
  useLayoutEffect(() => source.update(entriesJSON), [entriesJSON, source]);
  const openItem = (entryId: string, itemId: string) => {
    const item = list
      .find((entry) => entry.id === entryId)
      ?.items.find((candidate) => candidate.itemId === itemId);
    return openSubagentTask(item as ItemSummary | undefined, {
      entryId,
      source,
      onStop: () => setStopped(true),
    });
  };
  const openProcess = useProcessSheet(entriesJSON, (entryId, itemId) => {
    openItem(entryId, itemId);
  });
  return (
    <RNView style={{ flex: 1, backgroundColor: colors.reading }}>
      <NativeChat
        style={{ flex: 1 }}
        navigationTitle="Audit token refresh"
        navigationSubtitle="Sub agents"
        entriesJSON={entriesJSON}
        composerJSON={JSON.stringify({
          editable: true,
          canSend: false,
          sending: false,
          running: true,
          notice: '',
          reconnect: false,
          connection: '',
          placeholder: 'Message',
        })}
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onActivityPress={({ nativeEvent }) => {
          if (
            nativeEvent.itemId &&
            openItem(nativeEvent.entryId, nativeEvent.itemId)
          )
            return;
          openProcess(nativeEvent.entryId, nativeEvent.processStartId);
        }}
        onReconnect={() => {}}
      />
      <RNView
        accessible
        testID="subagent-probe"
        accessibilityLabel="Subagent state"
        accessibilityValue={{ text: JSON.stringify({ progress, stopped }) }}
        pointerEvents="none"
        style={{ position: 'absolute', bottom: 0, width: 1, height: 1 }}
      />
    </RNView>
  );
}

export const SubagentsPreviewScreen = definePage({
  id: 'subagents-preview',
  title: 'Sub agents',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
