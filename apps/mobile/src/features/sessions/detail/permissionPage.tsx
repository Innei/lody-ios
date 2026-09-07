import { useEffect, useState } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { respondSessionPermission } from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { usePalette } from '@/theme/palette';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { CommandBlock, type DetailResponse } from './DetailBlocks';
import { fetchDetail } from './itemDetailPage';
import { t, type TranslationKey } from '../../../i18n/index.ts';

export type PermissionParams = {
  sessionId: string;
  entryId: string;
  itemId: string;
  requestId: string;
  generation: number;
  kind: string;
  title: string;
  path?: string;
};

const HEADINGS: Record<string, TranslationKey> = {
  execute: 'permission.heading.execute',
  bash: 'permission.heading.execute',
  edit: 'permission.heading.edit',
  write: 'permission.heading.edit',
  delete: 'permission.heading.edit',
  move: 'permission.heading.edit',
};

function PermissionScreen() {
  const { params, finish } = usePageRuntime<PermissionParams, void>();
  const colors = usePalette();
  const [detail, setDetail] = useState<DetailResponse>();
  const [submitting, setSubmitting] = useState('');
  const [error, setError] = useState('');
  useEffect(() => {
    void fetchDetail(params)
      .then(setDetail)
      .catch(() => setError(t('permission.error.options')));
  }, [params.sessionId, params.entryId, params.itemId]);

  const answer = async (optionId: string) => {
    setSubmitting(optionId);
    setError('');
    try {
      const result = JSON.parse(
        await respondSessionPermission(
          JSON.stringify({
            sessionId: params.sessionId,
            entryId: params.entryId,
            itemId: params.itemId,
            requestId: params.requestId,
            optionId,
          }),
        ),
      );
      if (result.state === 'accepted') finish();
      else
        setError(
          result.state === 'stale'
            ? t('permission.error.stale')
            : t('permission.error.answered'),
        );
    } catch (caught) {
      setError(
        String(caught).includes('invalid_option')
          ? t('permission.error.invalidOption')
          : t('permission.error.send'),
      );
    } finally {
      setSubmitting('');
    }
  };
  const command = detail?.blocks.find((b) => b.type === 'terminal_command');
  const options = detail?.options ?? [];
  return (
    <View style={{ padding: 16, gap: 16 }}>
      <AppText variant="title">
        {t(HEADINGS[params.kind] ?? 'permission.heading.tool')}
      </AppText>
      {params.title ? (
        <AppText variant="secondary">{params.title}</AppText>
      ) : null}
      {command ? (
        <CommandBlock block={command} />
      ) : params.path ? (
        <AppText variant="mono" selectable>
          {params.path}
        </AppText>
      ) : null}
      {!detail && !error ? <ActivityIndicator /> : null}
      {error ? (
        <AppText variant="meta" style={{ color: colors.danger }}>
          {error}
        </AppText>
      ) : null}
      <View style={{ gap: 8 }}>
        {options.map((option, index) => {
          const allow = option.kind.startsWith('allow');
          const filled =
            allow &&
            options.findIndex((o) => o.kind.startsWith('allow')) === index;
          return submitting === option.optionId ? (
            <View
              key={option.optionId}
              style={{ minHeight: 44, justifyContent: 'center' }}
            >
              <ActivityIndicator />
            </View>
          ) : (
            <Button
              key={option.optionId}
              label={option.name}
              variant={filled ? 'filled' : 'plain'}
              disabled={!!submitting}
              destructive={option.kind.startsWith('reject')}
              onPress={() => void answer(option.optionId)}
            />
          );
        })}
      </View>
    </View>
  );
}

export const permissionPage = definePage<PermissionParams, void>({
  id: 'session-permission',
  title: t('permission.title'),
  Component: PermissionScreen,
  parseRouteParams: () => {
    throw new Error('请从会话页打开');
  },
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: 'fitToContents',
    sheetGrabberVisible: true,
    dismissible: true,
    headerVariant: 'transparent',
  },
});
