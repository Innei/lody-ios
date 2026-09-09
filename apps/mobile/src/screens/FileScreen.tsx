import { Stack } from 'expo-router';
import { useOpenFile } from '@/hooks/screens/useOpenFile';
import { use, useMemo, useState } from 'react';
import { SheetHeaderContext } from '@/lib/presentation/SheetStack';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { PlatformColor, View as RNView } from 'react-native';
import { NativeCodeView } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { AppText } from '@/ui/AppText';
import { t } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

export type FileParams = {
  path: string;
  handle: string;
  bytes: number;
  sessionId?: string;
  line?: number;
};

function View() {
  const { params } = usePageRuntime<FileParams>();
  const [error, setError] = useState('');
  const markdown = /\.(md|markdown|mdx)$/i.test(params.path);
  const [source, setSource] = useState(Boolean(params.line));
  const openFile = useOpenFile(params.sessionId ?? '');
  const inSheet = use(SheetHeaderContext) !== null;
  useSheetHeader(
    useMemo(
      () =>
        markdown
          ? [
              {
                type: 'button' as const,
                title: t(source ? 'file.preview' : 'file.source'),
                accessibilityLabel: t(source ? 'file.preview' : 'file.source'),
                onPress: () => setSource(!source),
              },
            ]
          : [],
      [markdown, source],
    ),
  );
  return (
    <RNView
      style={{ flex: 1, backgroundColor: PlatformColor('systemBackground') }}
    >
      {markdown && !inSheet && (
        <Stack.Toolbar placement="right">
          <Stack.Toolbar.Button
            icon={
              source
                ? 'doc.richtext'
                : 'chevron.left.forwardslash.chevron.right'
            }
            accessibilityLabel={t(source ? 'file.preview' : 'file.source')}
            onPress={() => setSource(!source)}
          />
        </Stack.Toolbar>
      )}
      {error ? (
        <AppText variant="meta" style={{ padding: 24, textAlign: 'center' }}>
          {error}
        </AppText>
      ) : (
        <NativeCodeView
          style={{ flex: 1 }}
          path={params.path}
          handle={params.handle}
          renderMarkdown={markdown && !source}
          line={params.line ?? 0}
          onFilePress={({ nativeEvent }) => {
            const target = nativeEvent.path;
            const absolute =
              target.startsWith('/') || /^[A-Za-z]:[\\/]/.test(target);
            const parent = params.path.replace(/[^/]*$/, '');
            void openFile(
              absolute ? target : parent + target,
              nativeEvent.line,
            );
          }}
          onFail={({ nativeEvent }) =>
            setError(
              nativeEvent.message === 'content_expired'
                ? t('file.error.stale')
                : t('file.error.render'),
            )
          }
        />
      )}
    </RNView>
  );
}

export const FileScreen = definePage<FileParams>({
  id: 'file',
  title: t('file.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from the project files');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
