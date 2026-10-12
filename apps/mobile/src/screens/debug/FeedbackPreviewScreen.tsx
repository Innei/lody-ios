import { useEffect, useMemo, useRef, useState } from 'react';
import { View } from 'react-native';
import { copyText, feedbackScreenshot, shareFeedback } from '@lody-ios/kit';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { definePage } from '@/lib/presentation';
import {
  createFeedbackDraftStore,
  feedbackDiagnostics,
} from '@/features/feedback/report';
import type { FeedbackService } from '@/features/feedback/service';
import { BugFeedbackScreen } from '@/screens/BugFeedbackScreen';
import { SettingsScreen } from '@/screens/SettingsScreen';
import { Button } from '@/ui/Button';
import { AppText } from '@/ui/AppText';

function Content() {
  const { present } = usePageRuntime();
  const [revision, setRevision] = useState(0);
  const [outcome, setOutcome] = useState('No reports submitted');
  const screenshots = useRef<string[]>([]);
  const service = useMemo<FeedbackService>(() => {
    let opens = 0;
    const store = createFeedbackDraftStore(
      async () => null,
      async () => {},
    );
    return {
      ...store,
      environment: async () => ({
        version: '0.2.0',
        build: '48',
        systemVersion: '27.0',
        deviceModel: 'iPhone18,1',
      }),
      diagnostics: async () =>
        feedbackDiagnostics({
          connection: { state: 'offline', machines: 1 },
          runtime: {
            state: 'failed',
            generation: 3,
            acknowledgements: 0,
            ...{
              reason:
                'token=synthetic-secret email=private@example.com /Users/private/project',
            },
          },
        }),
      pickScreenshot: async () => {
        const picked = await feedbackScreenshot('fixture', '');
        if (picked) screenshots.current.push(picked.uri);
        return picked;
      },
      previewScreenshot: (uri) => feedbackScreenshot('preview', uri),
      removeScreenshot: (uri) => feedbackScreenshot('remove', uri),
      copy: copyText,
      share: shareFeedback,
      openGithub: async (url) => {
        opens += 1;
        setOutcome(`GitHub attempts: ${opens} · ${url}`);
        if (opens === 1) throw new Error('Offline open failure');
      },
    };
  }, [revision]);
  useEffect(
    () => () => {
      for (const uri of screenshots.current)
        void feedbackScreenshot('remove', uri).catch(() => {});
      screenshots.current = [];
    },
    [revision],
  );

  return (
    <View style={{ flex: 1, paddingTop: 110, paddingHorizontal: 20, gap: 16 }}>
      <AppText testID="feedback-fixture-ready">Offline Feedback</AppText>
      <Button
        testID="feedback-settings"
        label="Open Settings"
        onPress={() => void present(SettingsScreen)}
      />
      <Button
        testID="feedback-open"
        label="Open Feedback"
        onPress={() => void present(BugFeedbackScreen, { service })}
      />
      <Button
        testID="feedback-reset"
        label="Reset Fixture"
        onPress={() => {
          setOutcome('No reports submitted');
          setRevision((value) => value + 1);
        }}
      />
      <AppText testID="feedback-fixture-outcome" numberOfLines={4} selectable>
        {outcome}
      </AppText>
    </View>
  );
}

export const FeedbackPreviewScreen = definePage({
  id: 'feedback-preview',
  title: 'Feedback',
  Component: Content,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
