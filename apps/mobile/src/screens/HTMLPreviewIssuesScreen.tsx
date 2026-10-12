import { useState } from 'react';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import {
  NativeGroupedList,
  NativeNavigationHeader,
  type HTMLPreviewIssue,
} from '@lody-ios/kit';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import { htmlFeedbackReport, htmlIssueKey } from '@/features/files/htmlPreview';
import type { PreviewFeedbackResult } from '@/features/files/previewFeedback';
import { t } from '@/lib/i18n';
import { usePalette } from '@/lib/theme/palette';
import { AppText } from '@/ui/AppText';
import { Button } from '@/ui/Button';

type Params = {
  path: string;
  issues: HTMLPreviewIssue[];
  send: (report: string) => Promise<PreviewFeedbackResult>;
};

function Content() {
  const { params, cancel, finish } = usePageRuntime<Params, 'open-session'>();
  const colors = usePalette();
  const insets = useSafeAreaInsets();
  const [sending, setSending] = useState(false);
  const [result, setResult] = useState<PreviewFeedbackResult>();
  const [error, setError] = useState('');
  const [attempted, setAttempted] = useState(false);
  const feedback = async () => {
    if (sending || attempted) return;
    setSending(true);
    setAttempted(true);
    setError('');
    try {
      setResult(
        await params.send(htmlFeedbackReport(params.path, params.issues)),
      );
    } catch (cause) {
      const code = cause instanceof Error ? cause.message : '';
      setError(
        t(
          code === 'pending_send'
            ? 'html.feedback.pending'
            : 'html.feedback.failed',
        ),
      );
    } finally {
      setSending(false);
    }
  };
  const status = {
    sent: 'html.feedback.sent',
    queued: 'html.feedback.queued',
    unknown: 'html.feedback.unknown',
  } as const;
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <NativeNavigationHeader
        title={t('html.issues.title')}
        items={[]}
        leftItems={[
          {
            type: 'button',
            systemItem: 'close',
            identifier: 'html-issues-close',
            accessibilityLabel: t('native.close'),
            onPress: cancel,
          },
        ]}
      />
      <NativeGroupedList
        style={{ flex: 1 }}
        sections={params.issues.map((issue, index) => ({
          id: `issue-${index}`,
          header: issue.reference,
          rows: [
            {
              id: `html-issue-${index}`,
              title: t(htmlIssueKey(issue)),
              subtitle: issue.path,
              subtitleMono: true,
              wrapSubtitle: true,
              image: 'exclamationmark.triangle',
              imageTint: 'warning',
              action: false,
            },
          ],
        }))}
        onRowPress={() => {}}
      />
      <View
        style={{
          padding: 16,
          paddingBottom: Math.max(16, insets.bottom),
          gap: 12,
        }}
      >
        {error ? <AppText testID="html-feedback-error">{error}</AppText> : null}
        {result ? (
          <AppText testID="html-feedback-status">{t(status[result])}</AppText>
        ) : null}
        {attempted && !sending ? (
          <Button
            testID="html-feedback-conversation"
            label={t('html.feedback.conversation')}
            onPress={() => finish('open-session')}
          />
        ) : (
          <Button
            testID="html-feedback-send"
            variant="filled"
            radius={999}
            disabled={sending}
            label={t(sending ? 'html.feedback.sending' : 'html.feedback.send')}
            onPress={() => void feedback()}
          />
        )}
      </View>
    </View>
  );
}

export const HTMLPreviewIssuesScreen = definePage<Params, 'open-session'>({
  id: 'html-preview-issues',
  title: '',
  Component: Content,
  parseRouteParams: () => {
    throw new Error('Open issues through the HTML preview');
  },
  presentation: {
    style: 'formSheet',
    sheetAllowedDetents: [1],
    sheetGrabberVisible: true,
    headerVariant: 'transparent',
  },
});
