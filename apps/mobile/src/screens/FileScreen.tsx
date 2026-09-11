import { Stack } from 'expo-router';
import { useOpenFile } from '@/hooks/screens/useOpenFile';
import { use, useEffect, useMemo, useState } from 'react';
import { SheetHeaderContext } from '@/lib/presentation/SheetStack';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { ActivityIndicator, PlatformColor, View as RNView } from 'react-native';
import {
  NativeCodeView,
  previewContent,
  readFile,
  type FileContent,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { t, type TranslationKey } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';

export type FileParams = {
  path: string;
  sessionId: string;
  line?: number;
};

const errors: Record<string, TranslationKey> = {
  too_large: 'files.error.tooLarge',
  file_not_found: 'files.error.notFound',
  permission_denied: 'files.error.permissionDenied',
  path_not_allowed: 'files.error.pathNotAllowed',
  decode_error: 'files.error.decode',
};

function View() {
  const colors = usePalette();
  const { params } = usePageRuntime<FileParams>();
  const [file, setFile] = useState<Extract<FileContent, { status: 'ok' }>>();
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const path = file?.path ?? params.path;
  const quickLook = file?.kind === 'image' || file?.kind === 'binary';
  const markdown =
    Boolean(file) && !quickLook && /\.(md|markdown|mdx)$/i.test(path);
  const [source, setSource] = useState(Boolean(params.line));
  const openFile = useOpenFile(params.sessionId);
  const inSheet = use(SheetHeaderContext) !== null;

  useEffect(() => {
    let active = true;
    setFile(undefined);
    setError('');
    readFile({ sessionId: params.sessionId, path: params.path })
      .then(async (value) => {
        if (!active) return;
        if (value.status !== 'ok') {
          const key = errors[value.code];
          setError(key ? t(key) : (value.message ?? t('files.error.read')));
          return;
        }
        setFile(value);
        if (value.kind === 'image' || value.kind === 'binary') {
          await previewContent(value.handle);
        }
      })
      .catch(() => {
        if (active) setError(t('files.error.offline'));
      });
    return () => {
      active = false;
    };
  }, [params.sessionId, params.path, revision]);

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
  let body;
  if (error) {
    body = (
      <RNView style={{ flex: 1, justifyContent: 'center', padding: 24 }}>
        <AppText variant="meta" style={{ textAlign: 'center' }}>
          {error}
        </AppText>
        <Button
          label={t('common.retry')}
          onPress={() => setRevision((n) => n + 1)}
        />
      </RNView>
    );
  } else if (!file) {
    body = (
      <ActivityIndicator
        testID="file-loading"
        accessibilityLabel={t('common.reading')}
        color={PlatformColor('secondaryLabel')}
        style={{ flex: 1 }}
      />
    );
  } else if (quickLook) {
    body = (
      <RNView style={{ flex: 1, justifyContent: 'center', padding: 24 }}>
        <Button
          label={t('file.preview')}
          onPress={() => {
            void previewContent(file.handle).catch(() =>
              setError(t('file.error.stale')),
            );
          }}
        />
      </RNView>
    );
  } else {
    body = (
      <NativeCodeView
        style={{ flex: 1 }}
        path={path}
        handle={file.handle}
        renderMarkdown={markdown && !source}
        line={params.line ?? 0}
        onFilePress={({ nativeEvent }) => {
          const target = nativeEvent.path;
          const absolute =
            target.startsWith('/') || /^[A-Za-z]:[\\/]/.test(target);
          const parent = path.replace(/[^/]*$/, '');
          void openFile(absolute ? target : parent + target, nativeEvent.line);
        }}
        onFail={({ nativeEvent }) =>
          setError(
            nativeEvent.message === 'content_expired'
              ? t('file.error.stale')
              : t('file.error.render'),
          )
        }
      />
    );
  }
  return (
    <RNView style={{ flex: 1, backgroundColor: colors.reading }}>
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
      {body}
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
