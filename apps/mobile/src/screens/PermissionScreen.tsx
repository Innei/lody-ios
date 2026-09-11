import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, View as RNView } from 'react-native';
import { Screen } from '@/ui/Screen';
import { respondSessionPermission } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { CommandBlock } from '@/ui/DetailBlocks';
import { fetchDetail } from '@/features/sessions/itemDetail';
import type {
  PermissionDetail,
  PermissionOption,
  PermissionResult,
  PermissionTarget,
} from '../models/session.ts';
import type { PermissionTargetSource } from '@/features/sessions/permissionTarget';
import { t, type TranslationKey } from '../lib/i18n/index.ts';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { QuestionCard } from '@/features/sessions/QuestionCard';
import type { QuestionAnswers } from '../models/session.ts';

export type { PermissionDetail, PermissionOption } from '../models/session.ts';

export type PermissionService = {
  detail: (
    sessionId: string,
    target: PermissionTarget,
  ) => Promise<PermissionDetail>;
  respond: (
    sessionId: string,
    target: PermissionTarget,
    optionId: string,
    answers?: QuestionAnswers,
  ) => Promise<'accepted' | 'stale' | 'conflict'>;
};

export type PermissionParams = {
  sessionId: string;
  generation: number;
  target?: PermissionTarget;
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
  async respond(sessionId, target, optionId, answers) {
    const result = JSON.parse(
      await respondSessionPermission(
        JSON.stringify({
          sessionId,
          entryId: target.entryId,
          itemId: target.itemId,
          requestId: target.requestId,
          optionId,
          answers,
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
    if (!params.source) return;
    // The source tracks the synced replica: an answer given on the desktop
    // clears the pending request, so the sheet moves on or closes by itself.
    return params.source((state) => {
      if (!state.ready) return;
      if (state.target) {
        setTarget(state.target);
      } else {
        giveUp();
      }
    });
  }, [params.source]);
  return target;
}

function View() {
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
  const currentTarget = useRef(target);
  currentTarget.current = target;

  useEffect(() => {
    if (!target) return;
    let active = true;
    setDetail(undefined);
    setError('');
    setSubmitting('');
    if (target.questionMeta) return;
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
  }, [
    params.sessionId,
    target?.entryId,
    target?.itemId,
    target?.requestId,
    service,
  ]);

  const answer = async (optionId: string, answers?: QuestionAnswers) => {
    if (!target) return;
    setSubmitting(optionId);
    setError('');
    try {
      const state = await service.respond(
        params.sessionId,
        target,
        optionId,
        answers,
      );
      if (currentTarget.current?.requestId !== target.requestId) return;
      if (state === 'accepted') finish({ requestId: target.requestId });
      else
        setError(
          state === 'stale'
            ? t('permission.error.stale')
            : t('permission.error.answered'),
        );
    } catch (caught) {
      if (currentTarget.current?.requestId !== target.requestId) return;
      setError(
        String(caught).includes('invalid_option')
          ? t('permission.error.invalidOption')
          : t('permission.error.send'),
      );
    } finally {
      if (currentTarget.current?.requestId === target.requestId)
        setSubmitting('');
    }
  };

  // Actions belong to the synced request; optional command details must not gate them.
  const options = target?.options ?? detail?.options ?? [];
  const submitOption = options.find((o) => o.kind?.startsWith('allow'));
  if (target?.kind === 'ask_user_question' && !target.questionMeta)
    return (
      <Screen>
        <AppText>{t('permission.error.options')}</AppText>
      </Screen>
    );
  if (target?.questionMeta)
    return (
      <Screen automaticallyAdjustKeyboardInsets>
        <QuestionCard
          key={`${target.entryId}/${target.itemId}/${target.requestId}`}
          meta={target.questionMeta}
          disabled={!!submitting}
          onSubmit={(answers) => {
            if (submitOption) void answer(submitOption.optionId, answers);
            else setError(t('permission.error.options'));
          }}
        />
        {error ? (
          <AppText variant="meta" style={{ color: colors.danger }}>
            {error}
          </AppText>
        ) : null}
      </Screen>
    );
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
      <RNView style={{ gap: 8 }}>
        {options.map((option, index) => {
          const allow = option.kind?.startsWith('allow');
          const filled =
            allow &&
            options.findIndex((o) => o.kind?.startsWith('allow')) === index;
          return submitting === option.optionId ? (
            <RNView
              key={option.optionId}
              style={{ minHeight: 44, justifyContent: 'center' }}
            >
              <ActivityIndicator />
            </RNView>
          ) : (
            <Button
              key={option.optionId}
              label={option.name}
              variant={filled ? 'glass' : 'plain'}
              disabled={!!submitting}
              destructive={option.kind?.startsWith('reject')}
              onPress={() => void answer(option.optionId)}
            />
          );
        })}
      </RNView>
    </Screen>
  );
}

export const PermissionScreen = definePage<PermissionParams, PermissionResult>({
  id: 'session-permission',
  title: t('permission.title'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open this page from the session screen');
  },
  presentation: {
    style: 'formSheet',
    // `fitToContents` cannot measure through SheetStack's absolutely filled
    // inner stack, which leaves the sheet blank and full height.
    sheetAllowedDetents: [0.5, 1],
    // A late-resolving target may be a multi-question form. Start with enough
    // room for its navigation and allow the user to collapse the sheet.
    sheetInitialDetentIndex: 'last',
    sheetGrabberVisible: false,
    // Answering is the way out; the header close button is the escape hatch.
    dismissible: false,
    headerVariant: 'transparent',
  },
});
