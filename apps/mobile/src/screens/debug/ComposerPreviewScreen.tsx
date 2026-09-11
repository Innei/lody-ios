import type { MentionItem } from '@/models/mentions';
import { expandMentionText } from '../../../modules/lody-kit/data-runtime/mention-expansion';
import { MentionPickerPreviewScreen } from './MentionPickerPreviewScreen';
import { PickerScreen } from '../PickerScreen';
import { ComposerSheet } from '@/ui/ComposerSheet';
import { Button } from '@/ui/Button';
import { useRef, useState } from 'react';
import { type NativeSyntheticEvent, Text, View as RNView } from 'react-native';
import { NativeChat, NativeComposer } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

type Params = {
  host: 'chat' | 'sheet';
  outcome: 'success' | 'failure';
  mentions?: boolean;
};

const mentionItems: MentionItem[] = [
  { path: 'src', name: 'src', kind: 'directory', subtitle: '项目源代码' },
  {
    path: 'src/auth',
    name: 'auth',
    kind: 'directory',
    subtitle: 'src · 登录与权限',
  },
  {
    path: 'src/auth/session.ts',
    name: 'session.ts',
    kind: 'file',
    subtitle: 'src/auth',
  },

  { path: 'src/app.tsx', name: 'app.tsx', kind: 'file', subtitle: 'src' },
  {
    path: 'README.md',
    name: 'README.md',
    kind: 'file',
    subtitle: '项目根目录',
  },
  {
    path: 'skills/auth-review/SKILL.md',
    name: 'auth-review',
    insertText: '$auth-review',
    kind: 'skill',
    subtitle: '检查登录、会话与权限边界',
  },
  {
    path: 'skills/swiftui-pro/SKILL.md',
    name: 'swiftui-pro',
    insertText: '$swiftui-pro',
    kind: 'skill',
    subtitle: '构建符合 Apple 平台习惯的界面',
  },
  {
    path: 'skills/code-review/SKILL.md',
    name: 'code-review',
    insertText: '$code-review',
    kind: 'skill',
    subtitle: '审查代码并指出可执行的改进',
  },
  {
    path: 'session-review',
    name: 'Review authentication',
    kind: 'session',
    subtitle: 'Lody iOS',
    insertText: '@session:session-review',
  },
  {
    path: 'session-followup',
    name: 'Follow up',
    kind: 'session',
    subtitle: 'Lody iOS',
    insertText: '@session:session-followup',
  },
  {
    path: 'role-reviewer',
    name: 'Reviewer',
    kind: 'role',
    subtitle: 'Review changes',
    insertText: '@role:role-reviewer',
  },
  {
    path: 'issue:11',
    name: 'Mentions alignment',
    kind: 'issue',
    subtitle: 'LodyAI/Lody #11',
    insertText: '#11',
  },
  {
    path: 'pr:12',
    name: 'Review implementation',
    kind: 'pr',
    subtitle: 'LodyAI/Lody #12',
    insertText: '#12',
  },
  {
    path: 'compact',
    name: 'compact',
    kind: 'cmd',
    subtitle: 'Compact this conversation',
    insertText: '/compact',
  },
];

// Keep the request pending until the driver completes it: no race against CI speed.
function View() {
  const { params, push, present } = usePageRuntime<Params>();
  const colors = usePalette();
  const [restoreDraftToken, setRestoreDraftToken] = useState(0);
  const [clearDraftToken, setClearDraftToken] = useState(0);
  const [sending, setSending] = useState(false);
  const [fast, setFast] = useState(false);
  const [count, setCount] = useState(0);
  const [sent, setSent] = useState<{ id: string; text: string }>();
  const busy = useRef(false);
  const [mentionResultJSON, setMentionResultJSON] = useState('');
  const mentionResultID = useRef(0);
  const props = {
    mentionResultJSON,
    onMentionBrowse: async ({
      nativeEvent,
    }: NativeSyntheticEvent<{ category: string; query: string }>) => {
      const result = await present(
        MentionPickerPreviewScreen,
        { ...nativeEvent, items: mentionItems },
        {
          title:
            (
              {
                file: '文件或目录',
                skill: '技能',
                session: '会话',
                role: 'Agent Role',
                issue: 'Issue',
                pr: 'Pull Request',
                cmd: '命令',
              } as Record<string, string>
            )[nativeEvent.category] ?? '引用',
        },
      );
      setMentionResultJSON(
        JSON.stringify({
          id: String(++mentionResultID.current),
          path: result.status === 'completed' ? result.value.path : undefined,
        }),
      );
    },
    composerJSON: JSON.stringify({
      editable: !sending,
      canSend: !sending,
      sending,
      notice: '',
      reconnect: false,
      placeholder: params.mentions ? '输入 @ 引用文件或技能' : '离线草稿验收',
      mentionItems: params.mentions ? mentionItems : undefined,
    }),
    onComposerOptionChange: ({
      nativeEvent,
    }: NativeSyntheticEvent<{ fast?: boolean }>) => {
      if (typeof nativeEvent.fast === 'boolean') setFast(nativeEvent.fast);
    },
    composerOptionsJSON: JSON.stringify({
      fast,
      modelId: 'gpt-5.6-sol',
      models: [{ id: 'gpt-5.6-sol', title: 'GPT-5.6 Sol' }],
      effort: 'high',
      efforts: [{ id: 'high', title: 'High' }],
    }),
    restoreDraftToken,
    onSend: ({
      nativeEvent,
    }: NativeSyntheticEvent<{ id: string; text: string }>) => {
      if (params.mentions) {
        setSent({
          id: nativeEvent.id,
          text: expandMentionText(nativeEvent.text, mentionItems),
        });
        setClearDraftToken((value) => value + 1);
        return;
      }
      busy.current = true;
      setSending(true);
      setCount((value) => value + 1);
    },
  };
  return (
    <RNView
      style={{
        flex: 1,
        backgroundColor:
          params.host === 'chat' ? colors.background : 'transparent',
      }}
    >
      {!params.mentions && (
        <RNView
          style={{
            marginTop: params.host === 'chat' ? 104 : 56,
            paddingHorizontal: 16,
          }}
        >
          <Button
            testID="complete-request"
            onPress={() => {
              if (!busy.current) return;
              if (params.outcome === 'failure')
                setRestoreDraftToken((value) => value + 1);
              else setClearDraftToken((value) => value + 1);
              setSending(false);
              busy.current = false;
            }}
          >
            Complete Request
          </Button>
        </RNView>
      )}
      {!params.mentions && (
        <Text
          testID="composer-result"
          style={{ color: colors.label, padding: 16 }}
        >{`Requests: ${count}`}</Text>
      )}
      {params.host === 'chat' || sent ? (
        <NativeChat
          {...props}
          mentionRepository="LodyAI/Lody"
          style={{ flex: 1 }}
          entriesJSON={JSON.stringify(
            sent
              ? [
                  {
                    id: sent.id,
                    role: 'user',
                    status: 'completed',
                    finished: true,
                    items: [{ itemId: 'text', type: 'text', text: sent.text }],
                  },
                ]
              : [],
          )}
          clearDraftToken={clearDraftToken}
          initialAttachmentsJSON={JSON.stringify(
            params.mentions
              ? []
              : [
                  {
                    id: 'fixture-file',
                    name: 'fixture.txt',
                    uri: 'file:///tmp/lody-ui-fixture.txt',
                    kind: 'file',
                  },
                ],
          )}
          emptyText={params.mentions ? '' : '离线输入框验收'}
          onActivityPress={() => {}}
          onReconnect={() => {}}
        />
      ) : (
        <ComposerSheet
          sections={Array.from(
            { length: params.mentions ? 2 : 8 },
            (_, index) => ({
              id: `group-${index}`,
              rows: [
                {
                  id: `option-${index}`,
                  title: params.mentions
                    ? ['Lody iOS', 'GPT-5.6 Sol'][index]!
                    : `Option ${index + 1}`,
                  subtitle: params.mentions
                    ? ['项目', '模型'][index]!
                    : 'Session configuration',
                  image: 'folder',
                  action: true,
                  navigates: true,
                },
              ],
            }),
          )}
          onRowPress={() => {
            if (busy.current) return;
            void push(PickerScreen, {
              title: 'Sheet options',
              options: [
                { id: 'sheet-choice-1', title: 'First option' },
                { id: 'sheet-choice-2', title: 'Second option' },
              ],
            });
          }}
        >
          <NativeComposer {...props} scrollEdge />
        </ComposerSheet>
      )}
    </RNView>
  );
}
export const ComposerPreviewScreen = definePage<Params>({
  id: 'composer-preview',
  title: '输入框验收',
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from Debug');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.62, 1],
    sheetGrabberVisible: true,
  },
});
