import { useEffect, useState } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { Screen } from '@/ui/Screen';
import { respondSessionPermission } from '@lody-ios/kit';
import { definePage, usePageRuntime } from '@/presentation';
import { usePalette } from '@/theme/palette';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { CommandBlock } from '@/ui/DetailBlocks';
import { fetchDetail } from '../itemDetail';
import type {
  PermissionDetail,
  PermissionOption,
  PermissionResult,
  PermissionTarget,
} from '../../../models/session.ts';
import type { PermissionTargetSource } from './permissionTarget';
import { t, type TranslationKey } from '../../../i18n/index.ts';

export type {
  PermissionDetail,
  PermissionOption,
} from '../../../models/session.ts';

export type PermissionService = {
  detail: (
    sessionId: string,
    target: PermissionTarget,
  ) => Promise<PermissionDetail>;
  respond: (
    sessionId: string,
    target: PermissionTarget,
    optionId: string,
  ) => Promise<'accepted' | 'stale' | 'conflict'>;
};

export type PermissionParams = {
  sessionId: string;
  generation: number;
  /** Known up front when the user taps the transcript row. */
  target?: PermissionTarget;
  /** Feeds the target in later, so the sheet can open before the replica loads. */
  source?: PermissionTargetSource;
  service?: PermissionService;
};

const liveService: PermissionService = {
  async detail(sessionId, target) {
    const response = await fetchDetail({
      sessionId,
      entryId: target.entryId,
      itemId: target.itemId,
    });
    return {
      options: response.options ?? [],
      command: response.blocks.find((b) => b.type === 'terminal_command'),
    };
  },
  async respond(sessionId, target, optionId) {
    const result = JSON.parse(
      await respondSessionPermission(
        JSON.stringify({
          sessionId,
          entryId: target.entryId,
          itemId: target.itemId,
          requestId: target.requestId,
          optionId,
        }),
      ),
    );
    return result.state;
  },
};

const HEADINGS: Record<string, TranslationKey> = {
  execute: 'permission.heading.execute',
  bash: 'permission.heading.execute',
  edit: 'permission.heading.edit',
  write: 'permission.heading.edit',
  delete: 'permission.heading.edit',
  move: 'permission.heading.edit',
};

function useTarget(params: PermissionParams, giveUp: () => void) {
  const [target, setTarget] = useState(params.target);
  useEffect(() => {
    if (params.target || !params.source) return;
    return params.source((state) => {
      if (state.target) setTarget(state.target);
      else if (state.ready) giveUp();
    });
  }, [params.target, params.source]);
  return target;
}

function PermissionScreen() {
  const { params, finish } = usePageRuntime<
    PermissionParams,
    PermissionResult
  >();
  const colors = usePalette();
  const service = params.service ?? liveService;
  const target = useTarget(params, () => finish(undefined));
  const [detail, setDetail] = useState<PermissionDetail>();
  const [submitting, setSubmitting] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    if (!target) return;
    let active = true;
    void service
      .detail(params.sessionId, target)
      .then((next) => {
        if (active) setDetail(next);
      })
      .catch(() => {
        if (active) setError(t('permission.error.options'));
      });
    return () => {
      active = false;
    };
  }, [target?.requestId]);

  const answer = async (optionId: string) => {
    if (!target) return;
    setSubmitting(optionId);
    setError('');
    try {
      const state = await service.respond(params.sessionId, target, optionId);
      if (state === 'accepted') finish({ requestId: target.requestId });
      else
        setError(
          state === 'stale'
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

  const options = detail?.options ?? [];
  return (
    <Screen>
      <AppText variant="title">
        {t(HEADINGS[target?.kind ?? ''] ?? 'permission.heading.tool')}
      </AppText>
      {target?.title ? (
        <AppText variant="secondary">{target.title}</AppText>
      ) : (
        <AppText variant="secondary">{t('permission.waiting')}</AppText>
      )}
      {detail?.command ? (
        <CommandBlock block={detail.command} />
      ) : target?.path ? (
        <AppText variant="mono" selectable>
          {target.path}
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
              variant={filled ? 'glass' : 'plain'}
              disabled={!!submitting}
              destructive={option.kind.startsWith('reject')}
              onPress={() => void answer(option.optionId)}
            />
          );
        })}
      </View>
    </Screen>
  );
}

export const permissionPage = definePage<PermissionParams, PermissionResult>({
  id: 'session-permission',
  title: t('permission.title'),
  Component: PermissionScreen,
  parseRouteParams: () => {
    throw new Error('请从会话页打开');
  },
  presentation: {
    style: 'formSheet',
    // `fitToContents` cannot measure through SheetStack's absolutely filled
    // inner stack, which leaves the sheet blank and full height.
    sheetAllowedDetents: [0.5, 1],
    sheetGrabberVisible: false,
    // Answering is the way out; the header close button is the escape hatch.
    dismissible: false,
    headerVariant: 'transparent',
  },
});
