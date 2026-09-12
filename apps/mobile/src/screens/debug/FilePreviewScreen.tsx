import { Stack } from 'expo-router';
import { useState } from 'react';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { FilesScreen } from '@/screens/FilesScreen';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { useOpenFile } from '@/hooks/screens/useOpenFile';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';

const files =
  '[完整报告](docs/report.md)\n\n[代码](docs/sample.swift#L2)\n\n[图片](photo.png)\n\n[PDF 文档](document.pdf)\n\n[不存在的文件](missing.txt)';
const entriesJSON = JSON.stringify([
  {
    id: 'file-links',
    role: 'assistant',
    finished: true,
    status: 'completed',
    items: [
      { itemId: 'thought', type: 'thought', text: files },
      {
        itemId: 'read',
        type: 'tool_call',
        kind: 'read',
        title: 'Read files',
        status: 'completed',
      },
      { itemId: 'answer', type: 'text', text: files },
    ],
  },
]);
const userMentionsJSON = JSON.stringify([
  {
    id: 'user-mentions',
    role: 'user',
    finished: true,
    status: 'completed',
    items: [
      {
        itemId: 'text',
        type: 'text',
        text: '#30\n@docs/report.md\nuse /review [Skill Path](skills/review/SKILL.md)\n@docs/sample.swift',
      },
    ],
  },
]);
const attachmentsJSON = JSON.stringify([
  {
    id: 'mcp-files',
    role: 'assistant',
    finished: true,
    status: 'completed',
    items: [
      'text',
      'pdf',
      'video',
      'retry',
      'missing',
      'pending',
      'cancel',
    ].map((id) => ({
      itemId: id,
      type: 'file',
      file: {
        id,
        fileName: { pdf: 'report.pdf', video: 'video.mp4' }[id] ?? `${id}.txt`,
        storageSessionId: 'ui-verify-attachments',
        transport: id === 'pending' ? 'local' : 'r2',
      },
    })),
  },
  {
    id: 'user-file',
    role: 'user',
    finished: true,
    status: 'completed',
    items: [
      {
        itemId: 'file',
        type: 'file',
        file: {
          id: 'text',
          fileName: 'report.txt',
          storageSessionId: 'ui-verify-attachments',
          transport: 'r2',
        },
      },
    ],
  },
]);
function View() {
  const [userMentions, setUserMentions] = useState(false);
  const [showAttachments, setShowAttachments] = useState(false);
  const { push } = usePageRuntime();
  const openFile = useOpenFile('ui-verify-files');
  const openProcess = useProcessSheet(entriesJSON, () => {}, 'ui-verify-files');
  let displayed = entriesJSON;
  if (userMentions) displayed = userMentionsJSON;
  if (showAttachments) displayed = attachmentsJSON;
  return (
    <>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Button
          icon="paperclip"
          accessibilityLabel="MCP Attachments"
          onPress={() => setShowAttachments((value) => !value)}
        />
        <Stack.Toolbar.Button
          icon="at"
          accessibilityLabel="User Mentions"
          onPress={() => setUserMentions((value) => !value)}
        />
        <Stack.Toolbar.Button
          icon="folder"
          accessibilityLabel="File Browser"
          onPress={() =>
            void push(FilesScreen, {
              workspaceId: 'fixture',
              sessionId: 'ui-verify-files',
              userId: 'fixture',
              path: 'docs',
              title: 'docs',
            })
          }
        />
      </Stack.Toolbar>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON={displayed}
        mentionRepository="Innei/lody-ios"
        composerJSON="{}"
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onReconnect={() => {}}
        onActivityPress={({ nativeEvent }) =>
          openProcess(nativeEvent.entryId, nativeEvent.processStartId)
        }
        onFilePress={({ nativeEvent }) =>
          void openFile(nativeEvent.path, nativeEvent.line)
        }
      />
    </>
  );
}
export const FilePreviewScreen = definePage({
  id: 'file-preview',
  title: '文件预览验收',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
