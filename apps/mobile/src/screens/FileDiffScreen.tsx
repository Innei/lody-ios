import { useEffect, useRef, useState, type ReactNode } from 'react';
import {
  ActivityIndicator,
  Text,
  useColorScheme,
  View as RNView,
} from 'react-native';
import {
  NativeDiffToolbar,
  fileDiff,
  previewContent,
  readContentText,
  readFile,
  readLocalValue,
  turnDiff,
  writeLocalValue,
  type DiffContent,
} from '@lody-ios/kit';
import { DiffView } from '@/features/diff/DiffView';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { t, type TranslationKey } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

export type FileDiffParams = {
  sessionId: string;
  entryId?: string;
  path: string;
};

type DiffStyle = 'unified' | 'split';
const STYLE_KEY = 'diffStyle';

const REASONS: Record<string, TranslationKey> = {
  not_changed: 'diff.reason.notChanged',
  base_unavailable: 'diff.reason.baseUnavailable',
  transient_io: 'diff.reason.transientIo',
  unsupported_binary: 'diff.reason.unsupportedBinary',
};

function reasonText(reason: string, message?: string) {
  const key = REASONS[reason];
  return key ? t(key) : (message ?? t('diff.error.fetch'));
}

function View() {
  const { params } = usePageRuntime<FileDiffParams>();
  const colors = usePalette();
  const [diff, setDiff] = useState<DiffContent>();
  const [sides, setSides] = useState<{ old: string; new: string }>();
  const [error, setError] = useState('');
  const [style, setStyle] = useState<DiffStyle>('unified');
  const [revision, setRevision] = useState(0);
  const [renderMs, setRenderMs] = useState<number>();
  const readyAt = useRef(0);
  const theme = useColorScheme() === 'dark' ? 'dark' : 'light';

  useEffect(() => {
    void readLocalValue(STYLE_KEY)
      .then((value) => value === 'split' && setStyle('split'))
      .catch(() => {});
  }, []);

  useEffect(() => {
    let active = true;
    setDiff(undefined);
    setSides(undefined);
    setRenderMs(undefined);
    setError('');
    const request = params.entryId
      ? turnDiff({
          sessionId: params.sessionId,
          entryId: params.entryId,
          path: params.path,
        })
      : fileDiff({ sessionId: params.sessionId, path: params.path });
    request
      .then(async (value) => {
        if (!active) return;
        setDiff(value);
        if (value.status !== 'ok') return;
        const raw = await readContentText(value.handle);
        if (!active) return;
        if (!raw) {
          setError(t('diff.error.render'));
          return;
        }
        const parsed = JSON.parse(raw) as { old?: string; new?: string };
        readyAt.current = Date.now();
        setSides({ old: parsed.old ?? '', new: parsed.new ?? '' });
      })
      .catch((cause: Error) => {
        if (!active) return;
        setError(
          /permission_denied/.test(String(cause))
            ? t('files.error.archived')
            : t('diff.error.offline'),
        );
      });
    return () => {
      active = false;
    };
  }, [params.sessionId, params.entryId, params.path, revision]);

  const changeStyle = (next: DiffStyle) => {
    setStyle(next);
    void writeLocalValue(STYLE_KEY, next).catch(() => {});
  };

  const preview = async () => {
    const file = await readFile({
      sessionId: params.sessionId,
      path: params.path,
    });
    if (file.status === 'ok') await previewContent(file.handle);
  };

  let body;
  if (error)
    body = (
      <Notice text={error}>
        <Button
          label={t('common.retry')}
          onPress={() => setRevision((n) => n + 1)}
        />
      </Notice>
    );
  else if (!diff)
    body = (
      <ActivityIndicator style={{ flex: 1 }} color={colors.secondaryLabel} />
    );
  else if (diff.status === 'unavailable')
    body = (
      <Notice text={reasonText(diff.reason, diff.message)}>
        {diff.reason === 'unsupported_binary' ? (
          <Button
            label={t('diff.action.previewFile')}
            onPress={() => void preview()}
          />
        ) : null}
      </Notice>
    );
  else if (diff.newKind === 'binary' || diff.oldKind === 'binary')
    body = (
      <Notice text={t('diff.reason.unsupportedBinary')}>
        <Button
          label={t('diff.action.previewFile')}
          onPress={() => void preview()}
        />
      </Notice>
    );
  else if (diff.newKind === 'too_large' || diff.oldKind === 'too_large')
    body = <Notice text={t('diff.error.tooLarge')} />;
  else
    body =
      sides == null ? (
        <ActivityIndicator style={{ flex: 1 }} color={colors.secondaryLabel} />
      ) : (
        <>
          <DiffView
            path={params.path}
            oldText={sides.old}
            newText={sides.new}
            diffStyle={style}
            theme={theme}
            dom={{
              shared: true,
              matchContents: false,
              scrollEnabled: true,
              style: { flex: 1 },
              onMessage: (event) => {
                try {
                  const payload = JSON.parse(event.nativeEvent.data) as {
                    type?: string;
                  };
                  if (payload.type === 'lody:diff-rendered') {
                    const started = readyAt.current || Date.now();
                    setRenderMs(Math.max(1, Date.now() - started));
                  }
                } catch {
                  /* ignore */
                }
              },
            }}
          />
          {renderMs != null ? (
            <RNView
              collapsable={false}
              accessible
              accessibilityLabel={`${renderMs}`}
              nativeID="diff-render-ms"
              testID="diff-render-ms"
              pointerEvents="none"
              style={{ position: 'absolute', width: 44, height: 44 }}
            />
          ) : null}
        </>
      );

  return (
    <RNView style={{ flex: 1, backgroundColor: colors.reading }}>
      {body}
      {diff?.status === 'ok' ? (
        <NativeDiffToolbar
          style={{
            position: 'absolute',
            left: 0,
            right: 0,
            bottom: 16,
            height: 56,
          }}
          add={diff.add ?? 0}
          del={diff.del ?? 0}
          base={t(
            diff.base === 'turn' ? 'diff.base.turn' : 'diff.base.current',
          )}
          diffStyle={style}
          onStyleChange={({ nativeEvent }) => changeStyle(nativeEvent.style)}
        />
      ) : null}
    </RNView>
  );
}

function Notice({ text, children }: { text: string; children?: ReactNode }) {
  return (
    <RNView
      style={{
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        gap: 12,
        padding: 24,
      }}
    >
      <AppText variant="meta" style={{ textAlign: 'center' }}>
        {text}
      </AppText>
      {children}
    </RNView>
  );
}

export const FileDiffScreen = definePage<FileDiffParams>({
  id: 'file-diff',
  title: t('diff.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('请从本轮改动打开');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
