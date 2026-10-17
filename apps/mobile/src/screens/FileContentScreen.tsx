import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, useColorScheme, View } from 'react-native';
import {
  NativeMarkdownDocumentView,
  NativeNavigationHeader,
  NativeHTMLPreviewView,
  NativePressable,
  NativeSymbol,
  readContentText,
  readFile,
  type FileContent,
  type HTMLPreviewIssue,
} from '@lody-ios/kit';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { DiffView } from '@/features/diff/DiffView';
import { basename } from '@/features/sessions/path';
import { useOpenFile } from '@/hooks/screens/useOpenFile';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePreviewFeedback } from '@/hooks/screens/usePreviewFeedback';
import { htmlReadError, isHTML } from '@/features/files/htmlPreview';
import type { PreviewFeedbackResult } from '@/features/files/previewFeedback';
import { HTMLPreviewIssuesScreen } from './HTMLPreviewIssuesScreen';
import { definePage, present } from '@/lib/presentation';
import { t, tp, type TranslationKey } from '@/lib/i18n';
import { usePalette } from '@/lib/theme/palette';
import { uiVerify } from '@/lib/uiVerify';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';

type Params = {
  sessionId: string;
  path: string;
  line?: number;
  preview?: boolean;
  feedback?: (report: string) => Promise<PreviewFeedbackResult>;
};
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
  const feedback = usePreviewFeedback(params.sessionId);
  const insets = useSafeAreaInsets();
  const html = isHTML(params.path);
  const [file, setFile] = useState<Extract<FileContent, { status: 'ok' }>>();
  const [text, setText] = useState<string>();
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const [source, setSource] = useState(
    (params.line ?? 0) > 0 || (html && !params.preview),
  );
  const [ready, setReady] = useState(false);
  const [issues, setIssues] = useState<HTMLPreviewIssue[]>([]);
  const [responses, setResponses] = useState<
    { id: string; handle?: string; code?: string }[]
  >([]);
  const activeHandle = useRef<string | undefined>(undefined);
  activeHandle.current = source ? undefined : file?.handle;
  const markdown = /\.(md|markdown|mdx)$/i.test(params.path);

  const showIssues = async () => {
    const result = await present(HTMLPreviewIssuesScreen, {
      path: params.path,
      issues,
      send: uiVerify && params.feedback ? params.feedback : feedback.send,
    });
    if (result.status === 'completed' && result.value === 'open-session') {
      cancel();
      feedback.openSession();
    }
  };

  useEffect(() => {
    let active = true;
    setFile(undefined);
    setText(undefined);
    setError('');
    setReady(false);
    setIssues([]);
    setResponses([]);
    void readFile(params)
      .then(async (value) => {
        if (!active) return;
        if (value.status !== 'ok') {
          if (html)
            setIssues([
              {
                reference: params.path,
                path: params.path,
                kind: 'document',
                code: value.code,
              },
            ]);
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
      .catch((cause) => {
        if (active) {
          setError(t('native.file.error.read'));
          if (html)
            setIssues([
              {
                reference: params.path,
                path: params.path,
                kind: 'document',
                code: htmlReadError(cause),
              },
            ]);
        }
      });
    return () => {
      active = false;
      activeHandle.current = undefined;
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
        {html && issues.length > 0 ? (
          <Button
            label={t('html.issues.title')}
            onPress={() => void showIssues()}
          />
        ) : null}
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
  } else if (html && !source) {
    body = (
      <NativeHTMLPreviewView
        handle={file.handle}
        responsesJSON={JSON.stringify(responses)}
        style={{ flex: 1 }}
        onLoad={() => setReady(true)}
        onFail={({ nativeEvent }) => {
          setIssues((old) =>
            old.length > 0
              ? old
              : [
                  {
                    reference: params.path,
                    path: params.path,
                    kind: 'document',
                    code: nativeEvent.code,
                  },
                ],
          );
          setError(t('html.error.resource'));
        }}
        onIssues={({ nativeEvent }) => setIssues(nativeEvent.issues)}
        onResourceRequest={({ nativeEvent }) => {
          const handle = file.handle;
          const { id, path } = nativeEvent;
          void readFile({ sessionId: params.sessionId, path })
            .then((value) => {
              if (activeHandle.current !== handle) return;
              const response =
                value.status === 'ok'
                  ? { id, handle: value.handle }
                  : { id, code: value.code };
              setResponses((old) => [...old, response]);
            })
            .catch((cause) => {
              if (activeHandle.current === handle)
                setResponses((old) => [
                  ...old,
                  { id, code: htmlReadError(cause) },
                ]);
            });
        }}
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
          file && (markdown || html)
            ? [
                {
                  type: 'button',
                  title: html
                    ? undefined
                    : t(source ? 'file.preview' : 'file.source'),
                  icon: html
                    ? { type: 'sfSymbol', name: source ? 'eye' : 'doc.text' }
                    : undefined,
                  identifier: 'file-preview-toggle',
                  accessibilityLabel: t(
                    source ? 'file.preview' : 'file.source',
                  ),
                  onPress: () => {
                    setReady(false);
                    if (html && source) setRevision((value) => value + 1);
                    setSource((value) => !value);
                  },
                },
              ]
            : []
        }
      />
      {body}
      {html && !source && !error && issues.length > 0 ? (
        <NativePressable
          testID="html-issues-summary"
          accessibilityLabel={tp('html.issues.count', issues.length, {
            count: issues.length,
          })}
          onPress={() => void showIssues()}
          style={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: 12,
            minHeight: 56,
            padding: 16,
            paddingBottom: Math.max(16, insets.bottom),
            backgroundColor: colors.card,
          }}
        >
          <NativeSymbol
            symbol="exclamationmark.triangle"
            tint="warning"
            style={{ width: 24, height: 24 }}
          />
          <View style={{ flex: 1, gap: 4 }}>
            <AppText>
              {tp('html.issues.count', issues.length, { count: issues.length })}
            </AppText>
            <AppText variant="meta">{t('html.issues.incomplete')}</AppText>
          </View>
          <NativeSymbol
            symbol="chevron.right"
            tint="secondary"
            style={{ width: 16, height: 20 }}
          />
        </NativePressable>
      ) : null}
    </View>
  );
}

export const FileContentScreen = definePage<Params>({
  id: 'file-content',
  panel: true,
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
