import { useState } from 'react';
import { Stack } from 'expo-router';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { useMessageDetailsSheet } from '@/hooks/screens/useMessageDetailsSheet';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';

const choices = [
  'usage',
  'no-usage',
  'warning',
  'files',
  'team',
  'solo',
  'goal-active',
  'goal-paused',
  'goal-cleared',
  'schedules',
  'expired-schedule',
];
const usage = {
  inputTokens: 1234,
  outputTokens: 500,
  cacheReadInputTokens: 4096,
  cacheCreationInputTokens: 100,
  reasoningOutputTokens: 30,
};
const reply = (id: string, text: string) => ({
  id,
  role: 'assistant',
  status: 'completed',
  finished: true,
  items: [{ itemId: 'answer', type: 'text', text }],
});
const goal = {
  threadId: 'goal-thread',
  objective: 'Finish the release notes and review the changelog.',
  status: 'active',
};

function fixture(name: string) {
  let entries: object[] = [];
  let context: object = {};
  if (name === 'usage' || name === 'no-usage') {
    entries = [
      {
        ...reply(
          'usage-report',
          'This reply has provider-reported token usage.',
        ),
        tokenUsage: name === 'usage' ? usage : undefined,
      },
      reply('absent-report', 'This reply has no reported token usage.'),
    ];
    if (name === 'usage')
      context = {
        contextWindowUsage: { size: 200000, used: 64000 },
        quotas: [
          {
            id: 'codex',
            provider: 'Codex',
            windows: [{ usedPercent: 25, duration: 18000, resetsAt: null }],
          },
        ],
      };
  }
  if (name === 'warning')
    entries = [
      {
        ...reply(
          'warning-reply',
          'The reply remains readable while the warning stays visible.',
        ),
        items: [
          { itemId: 'thought', type: 'thought', text: 'PRIVATE-PROCESS' },
          {
            itemId: 'warning',
            type: 'system_notice',
            name: 'agent_warning',
            meta: {
              message: 'The provider retried after a temporary interruption.',
              source: 'codex',
            },
          },
          {
            itemId: 'tool',
            type: 'tool_call',
            title: 'Read changelog',
            kind: 'read',
            status: 'completed',
          },
          {
            itemId: 'answer',
            type: 'text',
            text: 'The reply remains readable while the warning stays visible.',
          },
        ],
      },
    ];
  if (name === 'files')
    entries = [
      {
        ...reply('artifact-reply', 'Files produced by the agent.'),
        items: [
          {
            itemId: 'pdf',
            type: 'file',
            file: {
              id: 'pdf',
              fileName: 'report.pdf',
              sizeBytes: 2048,
              transport: 'r2',
              uploadedAt: Date.now(),
              storageSessionId: 'ui-verify-attachments',
            },
          },
          {
            itemId: 'pending',
            type: 'file',
            file: {
              id: 'pending',
              fileName: 'pending.pdf',
              transport: 'local',
              storageSessionId: 'ui-verify-attachments',
            },
          },
          {
            itemId: 'expired',
            type: 'file',
            file: {
              id: 'expired',
              fileName: 'expired.pdf',
              transport: 'r2',
              uploadedAt: Date.now() - 91 * 86400000,
              storageSessionId: 'ui-verify-attachments',
            },
          },
        ],
      },
    ];
  if (name === 'team' || name === 'solo') {
    entries = [
      {
        id: 'maya-message',
        role: 'user',
        status: 'handled',
        finished: true,
        userId: 'maya',
        items: [
          { itemId: 'text', type: 'text', text: 'Please review the release.' },
        ],
      },
      {
        id: 'ethan-message',
        role: 'user',
        status: 'handled',
        finished: true,
        author: { kind: 'human', userId: 'ethan' },
        items: [
          { itemId: 'text', type: 'text', text: 'I will check the notes.' },
        ],
      },
      {
        id: 'reviewer-message',
        role: 'user',
        status: 'handled',
        finished: true,
        author: {
          kind: 'agent',
          name: 'Codex',
          role: { name: 'Reviewer', emoji: '🔎' },
        },
        items: [
          {
            itemId: 'text',
            type: 'text',
            text: 'The agent wrote this update.',
          },
        ],
      },
    ];
    context = {
      senders: { maya: 'Maya Chen', ethan: 'Ethan' },
      showSenderIdentity: name === 'team',
    };
  }
  if (name.startsWith('goal-')) {
    const status = name.slice(5);
    entries = [
      {
        ...reply(
          'goal-reply',
          'The goal banner reflects the latest authoritative status.',
        ),
        items: [
          { itemId: 'old', type: 'goal', goal },
          { itemId: 'latest', type: 'goal', goal: { ...goal, status } },
          {
            itemId: 'answer',
            type: 'text',
            text: 'The goal banner reflects the latest authoritative status.',
          },
        ],
      },
    ];
    context = { goal: { ...goal, objective: 'Stale catalog fallback' } };
  }
  if (name === 'schedules' || name === 'expired-schedule') {
    entries = [
      reply(
        'scheduled-reply',
        'Pending tasks come from the existing agent scheduling tool history.',
      ),
    ];
    const future = Date.now() + 600000;
    context = {
      scheduledTasks: [
        {
          id: 'wakeup',
          kind: 'wakeup',
          createdAtMs: Date.now(),
          scheduledForMs: name === 'schedules' ? future : Date.now() - 10000,
          summary: 'Check the deployment again.',
        },
        {
          id: 'cron',
          kind: 'cron',
          createdAtMs: Date.now(),
          humanSchedule: '0 9 * * 1-5',
          recurring: true,
          timeZone: 'Asia/Tokyo',
          summary: 'Review the daily changelog.',
        },
      ],
    };
  }
  return {
    entriesJSON: JSON.stringify(entries),
    contextJSON: JSON.stringify(context),
  };
}

function View() {
  const [name, setName] = useState('usage');
  const data = fixture(name);
  const details = useMessageDetailsSheet(data.entriesJSON);
  const process = useProcessSheet(
    data.entriesJSON,
    () => {},
    'ui-verify-transcript-context',
  );
  return (
    <>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Menu
          icon="slider.horizontal.3"
          accessibilityLabel="Transcript fixtures"
        >
          {choices.map((choice) => (
            <Stack.Toolbar.MenuAction
              key={choice}
              onPress={() => setName(choice)}
            >
              {choice}
            </Stack.Toolbar.MenuAction>
          ))}
        </Stack.Toolbar.Menu>
      </Stack.Toolbar>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON={data.entriesJSON}
        sessionContextJSON={data.contextJSON}
        turnInfoEnabled
        onTurnInfoPress={({ nativeEvent }) => details(nativeEvent.entryId)}
        composerJSON={'{"editable":false,"canSend":false}'}
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onReconnect={() => {}}
        onActivityPress={({ nativeEvent }) =>
          process(nativeEvent.entryId, nativeEvent.processStartId)
        }
      />
    </>
  );
}

export const TranscriptContextPreviewScreen = definePage({
  id: 'transcript-context-preview',
  title: 'Transcript context',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
