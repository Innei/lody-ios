import { useEffect, useState, type ReactNode } from 'react';
import { ActivityIndicator, View } from 'react-native';
import {
  NativeDiff,
  NativeDiffToolbar,
  fileDiff,
  previewContent,
  readFile,
  readLocalValue,
  turnDiff,
  writeLocalValue,
  type DiffContent,
} from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { usePalette } from '@/theme/palette';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { t, type TranslationKey } from '../../../i18n/index.ts';

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

function FileDiffScreen() {
  const { params } = usePageRuntime<FileDiffParams>();
  const colors = usePalette();
  const [diff, setDiff] = useState<DiffContent>();
  const [error, setError] = useState('');
  const [style, setStyle] = useState<DiffStyle>('unified');
  const [revision, setRevision] = useState(0);

  useEffect(() => {
    void readLocalValue(STYLE_KEY)
      .then((value) => value === 'split' && setStyle('split'))
      .catch(() => {});
  }, []);

  useEffect(() => {
    let active = true;
    setDiff(undefined);
    setError('');
    const request = params.entryId
      ? turnDiff({
          sessionId: params.sessionId,
          entryId: params.entryId,
          path: params.path,
        })
      : fileDiff({ sessionId: params.sessionId, path: params.path });
    request
      .then((value) => active && setDiff(value))
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
    body = (
      <NativeDiff
        style={{ flex: 1 }}
        path={params.path}
        handle={diff.handle}
        diffStyle={style}
        onFail={() => setError(t('diff.error.render'))}
      />
    );

  return (
    <View style={{ flex: 1, backgroundColor: colors.reading }}>
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
    </View>
  );
}

function Notice({ text, children }: { text: string; children?: ReactNode }) {
  return (
    <View
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
    </View>
  );
}

export const fileDiffPage = definePage<FileDiffParams>({
  id: 'file-diff',
  title: t('diff.title'),
  Component: FileDiffScreen,
  parseRouteParams: () => {
    throw new Error('请从本轮改动打开');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
