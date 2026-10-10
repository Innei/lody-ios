import { useState } from 'react';
import { NativeChat, NativeNavigationHeader } from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { PermissionScreen } from '@/screens/PermissionScreen';
import { useProposedPlan } from '@/features/sessions/useProposedPlan';
import { planExecutionChoice } from '@/features/sessions/proposedPlan';
import type { EntrySummary } from '@/models/session';
import type { PermissionTarget } from '@/models/session';

const body = `# A clearer session list

Keep recent work easy to find while preserving native navigation.

## 1. Group recent sessions

- Show the project name above each group.
- Keep pinned sessions at the top.
- Preserve the selected row during navigation.

## 2. Handle empty results

Explain why no sessions match and offer a clear way to reset the filter.

## 3. Verify the experience

Check light and dark appearance, back navigation, and search.

**Acceptance marker: lighthouse.**`;
const target: PermissionTarget = {
  entryId: 'plan-preview',
  itemId: 'approval',
  requestId: 'plan-request',
  kind: 'switch_mode',
  title: 'Implement the proposed plan',
  options: [{ optionId: 'allow', name: 'Allow once', kind: 'allow_once' }],
};

function View() {
  const [mode, setMode] = useState('long');
  const [revision, setRevision] = useState(0);
  const [find, setFind] = useState('');
  const [responses, setResponses] = useState(0);
  const [published, setPublished] = useState<EntrySummary[]>([]);
  const [sends, setSends] = useState<string[]>([]);
  const markdown =
    mode === 'short' ? '# Small change\n\nUpdate the session title.' : body;
  const items: object[] = [
    {
      itemId: 'document',
      type: 'proposed_plan',
      rev: revision,
      turnId: 'turn',
      markdown:
        markdown +
        '\n'.repeat(revision) +
        (revision ? '\nAdditional review notes.' : ''),
      status: mode === 'cleared' ? 'cleared' : 'completed',
      isLatest: mode !== 'history',
    },
  ];
  if (mode === 'delta') Object.assign(items[0], { status: 'delta' });
  if (mode === 'approval')
    items.push({
      itemId: 'approval',
      type: 'tool_call',
      kind: 'switch_mode',
      title: target.title,
      status: 'pending',
      permission: { requestId: target.requestId, pending: true },
    });
  const entries = [
    {
      id: 'plan-user',
      role: 'user',
      status: 'completed',
      finished: true,
      items: [
        {
          itemId: 'question',
          type: 'text',
          text: 'Plan a clearer session list.',
        },
      ],
    },
    {
      id: 'plan-preview',
      role: 'assistant',
      status: 'completed',
      finished: mode !== 'delta',
      items,
    },
    ...published,
  ] as EntrySummary[];
  const executionChoice = planExecutionChoice({
    modelId: 'fixture-model',
    effort: 'high',
    configOptionValues: {
      collaboration_mode: 'plan',
      permission_mode: 'read-only',
    },
  });
  const decision = useProposedPlan({
    sessionId: `plan-fixture-${mode}`,
    entries,
    enabled: mode.startsWith('business-') && mode !== 'business-busy',
    payload: {
      ...executionChoice,
      reasoningEffort: executionChoice.effort,
      machineId: 'fixture-machine',
      userId: 'fixture-user',
      agentType: 'codex',
    },
    request: async (payload) => {
      const value = JSON.parse(payload);
      const valid =
        value.text === 'Implement the plan' &&
        value.queue === false &&
        value.guide === false &&
        value.attachments.length === 0 &&
        value.configOptionValues.collaboration_mode === 'default' &&
        value.configOptionValues.permission_mode === 'read-only' &&
        value.modelId === 'fixture-model' &&
        value.reasoningEffort === 'high';
      setSends((old) => [...old, valid ? 'valid' : 'INVALID']);
      if (mode !== 'business-failed')
        setPublished([
          {
            id: value.id,
            rev: 0,
            role: 'user',
            status: 'completed',
            finished: true,
            items: [
              {
                itemId: 'execution-input',
                rev: 0,
                type: 'text',
                text: value.text,
              },
            ],
          },
        ]);
      await new Promise((resolve) => setTimeout(resolve, 600));
      if (mode === 'business-unknown') throw new Error('Lost receipt');
      return JSON.stringify({
        state: mode === 'business-failed' ? 'not_sent' : 'accepted',
      });
    },
  });
  return (
    <>
      <NativeNavigationHeader
        items={[
          {
            type: 'menu',
            icon: { type: 'sfSymbol', name: 'ellipsis' },
            accessibilityLabel: 'Plan fixtures',
            menu: {
              items: [
                ...[
                  'long',
                  'short',
                  'delta',
                  'history',
                  'cleared',
                  'approval',
                  'business-ready',
                  'business-failed',
                  'business-unknown',
                  'business-busy',
                ].map((value) => ({
                  type: 'action' as const,
                  title: value,
                  onPress: () => {
                    setMode(value);
                    setRevision(0);
                    setSends([]);
                    setPublished([]);
                  },
                })),
                {
                  type: 'action',
                  title: 'Append',
                  onPress: () => setRevision((value) => value + 1),
                },
                {
                  type: 'action',
                  title: 'Find tail',
                  onPress: () =>
                    setFind(
                      JSON.stringify({
                        id: String(Date.now()),
                        query: 'lighthouse',
                        open: true,
                      }),
                    ),
                },
                {
                  type: 'action',
                  title: `Plan sends: ${sends.length} (${sends.every((value) => value === 'valid') ? 'valid' : 'INVALID'})`,
                  disabled: true,
                  onPress: () => {},
                },
                {
                  type: 'action',
                  title: `Permission responses: ${responses}`,
                  disabled: true,
                  onPress: () => {},
                },
              ],
            },
          },
        ]}
      />
      <NativeChat
        style={{ flex: 1 }}
        navigationTitle="Proposed plan"
        entriesJSON={JSON.stringify(entries)}
        planDecisionJSON={decision.stateJSON}
        onPlanDecision={({ nativeEvent: event }) =>
          void decision.decide(
            event.entryId,
            event.itemId,
            event.action,
            event.id,
          )
        }
        initialDraft="Keep this draft"
        composerJSON={JSON.stringify({ editable: true, canSend: false })}
        clearDraftToken={0}
        emptyText=""
        findRequestJSON={find}
        onSend={() => {}}
        onReconnect={() => {}}
        onActivityPress={({ nativeEvent }) => {
          if (
            nativeEvent.entryId !== target.entryId ||
            nativeEvent.itemId !== target.itemId
          )
            return;
          void present(PermissionScreen, {
            sessionId: 'plan-fixture',
            generation: 0,
            target,
            service: {
              detail: async () => ({ options: target.options ?? [] }),
              respond: async () => {
                setResponses((count) => count + 1);
                return 'accepted';
              },
            },
          });
        }}
      />
    </>
  );
}

export const ProposedPlanPreviewScreen = definePage({
  id: 'proposed-plan-preview',
  title: 'Proposed plan',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
