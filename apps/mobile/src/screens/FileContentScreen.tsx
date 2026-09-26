import { useEffect, useState } from 'react';
import { ActivityIndicator, useColorScheme, View } from 'react-native';
import {
  NativeMarkdownDocumentView,
  NativeNavigationHeader,
  readContentText,
  readFile,
  type FileContent,
} from '@lody-ios/kit';
import { DiffView } from '@/features/diff/DiffView';
import { basename } from '@/features/sessions/path';
import { useOpenFile } from '@/hooks/screens/useOpenFile';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import { t, type TranslationKey } from '@/lib/i18n';
import { usePalette } from '@/lib/theme/palette';
import { uiVerify } from '@/lib/uiVerify';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';

type Params = { sessionId: string; path: string; line?: number };
const errors: Record<string, TranslationKey> = {
  too_large: 'native.file.error.tooLarge',
  file_not_found: 'native.file.error.notFound',
  permission_denied: 'native.file.error.permissionDenied',
  path_not_allowed: 'native.file.error.pathNotAllowed',
  decode_error: 'native.file.error.decode',
};

function Content() {
  const { params, cancel } = usePageRuntime<Params>();
  const colors = usePalette();
  const theme = useColorScheme() === 'dark' ? 'dark' : 'light';
  const openFile = useOpenFile(params.sessionId);
  const [file, setFile] = useState<Extract<FileContent, { status: 'ok' }>>();
  const [text, setText] = useState<string>();
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const [source, setSource] = useState((params.line ?? 0) > 0);
  const [ready, setReady] = useState(false);
  const markdown = /\.(md|markdown|mdx)$/i.test(params.path);

  useEffect(() => {
    let active = true;
    setFile(undefined);
    setText(undefined);
    setError('');
    setReady(false);
    void readFile(params)
      .then(async (value) => {
        if (!active) return;
        if (value.status !== 'ok') {
          setError(t(errors[value.code] ?? 'native.file.error.read'));
          return;
        }
        const contents = await readContentText(value.handle);
        if (!active) return;
        if (contents == null) {
          setError(t('native.file.error.stale'));
          return;
        }
        setFile(value);
        setText(contents);
      })
      .catch(() => {
        if (active) setError(t('native.file.error.read'));
      });
    return () => {
      active = false;
    };
  }, [params.sessionId, params.path, revision]);

  let body;
  if (error) {
    body = (
      <View
        style={{
          flex: 1,
          alignItems: 'center',
          justifyContent: 'center',
          padding: 24,
          gap: 12,
        }}
      >
        <AppText>{error}</AppText>
        <Button
          label={t('common.retry')}
          onPress={() => setRevision((value) => value + 1)}
        />
      </View>
    );
  } else if (!file || text === undefined) {
    body = (
      <ActivityIndicator
        testID="file-loading"
        style={{ flex: 1 }}
        color={colors.secondaryLabel}
      />
    );
  } else if (markdown && !source) {
    body = (
      <NativeMarkdownDocumentView
        handle={file.handle}
        style={{ flex: 1 }}
        onFail={() => setError(t('native.file.error.stale'))}
        onFilePress={({ nativeEvent }) => {
          const href = nativeEvent.path;
          const parent = params.path.replace(/[^/\\]+$/, '');
          const path = /^(\/|[A-Za-z]:[\\/])/.test(href) ? href : parent + href;
          void openFile(path, nativeEvent.line);
        }}
      />
    );
  } else {
    body = (
      <DiffView
        mode="file"
        path={params.path}
        oldText=""
        newText={text}
        diffStyle="unified"
        theme={theme}
        line={params.line}
        handle={file.handle}
        verify={uiVerify}
        dom={{
          shared: true,
          matchContents: false,
          scrollEnabled: true,
          directionalLockEnabled: false,
          contentInsetAdjustmentBehavior: 'automatic',
          style: { flex: 1 },
          testID: ready ? 'file-source' : 'file-source-loading',
          onContentProcessDidTerminate: () =>
            setError(t('native.file.error.stale')),
          onMessage: (event) => {
            try {
              const message = JSON.parse(event.nativeEvent.data);
              if (
                message.type === 'lody:file-rendered' &&
                message.handle === file.handle
              )
                setReady(true);
              if (message.type === 'lody:diff-error')
                setError(t('native.file.error.stale'));
            } catch {
              /* Other Expo DOM bridge messages. */
            }
          },
        }}
      />
    );
  }
  return (
    <View style={{ flex: 1, backgroundColor: colors.reading }}>
      <NativeNavigationHeader
        title={basename(params.path)}
        leftItems={[
          {
            type: 'button',
            systemItem: 'close',
            identifier: 'file-back',
            accessibilityLabel: t('native.close'),
            onPress: cancel,
          },
        ]}
        items={
          file && markdown
            ? [
                {
                  type: 'button',
                  title: t(source ? 'file.preview' : 'file.source'),
                  onPress: () => {
                    setReady(false);
                    setSource((value) => !value);
                  },
                },
              ]
            : []
        }
      />
      {body}
    </View>
  );
}

export const FileContentScreen = definePage<Params>({
  id: 'file-content',
  title: '',
  Component: Content,
  parseRouteParams: () => {
    throw new Error('Open files through useOpenFile');
  },
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [1],
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
