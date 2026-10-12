import { useMemo, useRef, useState } from 'react';
import { Image, View } from 'react-native';
import type { FeedbackEnvironment } from '@lody-ios/kit';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import {
  feedbackIssueURL,
  feedbackReport,
  type FeedbackDraft,
} from '@/features/feedback/report';
import type { FeedbackService } from '@/features/feedback/service';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';
import { FormGroup } from '@/ui/FormGroup';
import { Screen } from '@/ui/Screen';

type Params = {
  draft: FeedbackDraft;
  environment: FeedbackEnvironment;
  service: FeedbackService;
  update: (draft: FeedbackDraft) => Promise<void>;
};

function Content() {
  const { params, cancel } = usePageRuntime<Params>();
  const colors = usePalette();
  const [draft, setDraft] = useState(params.draft);
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);
  const pending = useRef(false);
  const report = feedbackReport(draft, params.environment);
  const link = feedbackIssueURL(draft.description, report);

  async function perform(action: () => Promise<void>, failure: string) {
    if (pending.current) return;
    pending.current = true;
    setBusy(true);
    setStatus('');
    try {
      await action();
    } catch {
      setStatus(failure);
    } finally {
      pending.current = false;
      setBusy(false);
    }
  }

  async function openGithub() {
    await perform(async () => {
      params.service.copy(report);
      await params.service.openGithub(link.url);
      setStatus(
        t(link.prefilled ? 'feedback.githubOpened' : 'feedback.githubPaste'),
      );
    }, t('feedback.githubFailed'));
  }

  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('feedback.github'),
        accessibilityLabel: t('feedback.github'),
        disabled: busy,
        tintColor: colors.accent,
        onPress: () => void openGithub(),
      },
    ],
    // The report and link change when a selected screenshot is removed or edited.
    [busy, colors.accent, report, link.url, params.service],
  );
  useSheetHeader(actions);

  return (
    <Screen>
      <AppText testID="feedback-public-warning" variant="secondary">
        {t('feedback.publicWarning')}
      </AppText>
      <View style={{ flexDirection: 'row', gap: 24 }}>
        <Button
          testID="feedback-copy"
          label={t('feedback.copy')}
          disabled={busy}
          onPress={() =>
            void perform(async () => {
              params.service.copy(report);
              setStatus(t('feedback.copied'));
            }, t('feedback.copyFailed'))
          }
        />
        <Button
          testID="feedback-share"
          label={t('feedback.share')}
          disabled={busy}
          onPress={() =>
            void perform(async () => {
              const completed = await params.service.share(
                report,
                draft.screenshots.map((item) => item.uri),
              );
              setStatus(
                t(completed ? 'feedback.shared' : 'feedback.shareCancelled'),
              );
            }, t('feedback.shareFailed'))
          }
        />
      </View>
      {status ? (
        <AppText testID="feedback-status" accessibilityLiveRegion="polite">
          {status}
        </AppText>
      ) : null}
      <Button
        testID="feedback-edit-report"
        label={t('feedback.edit')}
        disabled={busy}
        onPress={cancel}
      />
      <AppText testID="feedback-report" variant="mono" selectable>
        {report}
      </AppText>
      {draft.screenshots.map((item, index) => (
        <FormGroup
          key={item.uri}
          header={t('feedback.screenshot', { index: index + 1 })}
          footer={t('feedback.screenshotHint')}
        >
          <Image
            source={{ uri: item.uri }}
            resizeMode="contain"
            accessibilityLabel={t('feedback.screenshot', { index: index + 1 })}
            style={{ height: 240, margin: 16 }}
          />
          <Button
            testID={`feedback-preview-image-${index}`}
            label={t('feedback.previewScreenshot')}
            disabled={busy}
            onPress={() =>
              void perform(async () => {
                const updated = await params.service.previewScreenshot(
                  item.uri,
                );
                if (!updated) return;
                const next = {
                  ...draft,
                  screenshots: draft.screenshots.map((old) =>
                    old.uri === item.uri ? updated : old,
                  ),
                };
                setDraft(next);
                await params.update(next);
              }, t('feedback.imageFailed'))
            }
          />
          <Button
            testID={`feedback-remove-image-${index}`}
            label={t('feedback.removeScreenshot')}
            destructive
            disabled={busy}
            onPress={() =>
              void perform(async () => {
                const next = {
                  ...draft,
                  screenshots: draft.screenshots.filter(
                    (old) => old.uri !== item.uri,
                  ),
                };
                setDraft(next);
                await params.update(next);
                await params.service.removeScreenshot(item.uri);
              }, t('feedback.imageFailed'))
            }
          />
        </FormGroup>
      ))}
    </Screen>
  );
}

export const BugFeedbackPreviewScreen = definePage<Params>({
  id: 'bug-feedback-preview',
  title: t('feedback.preview'),
  Component: Content,
  parseRouteParams: () => {
    throw new Error('Open preview from a feedback draft');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
