import { useMemo, useRef, useState } from 'react';
import { Alert, PlatformColor, TextInput } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { Screen } from '@/ui/Screen';
import { AppText } from '@/ui/AppText';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { pullRequestError } from '@/features/pull-request/errors';

type Params = {
  repository: string;
  number: number;
  onSubmit: (body: string) => Promise<boolean>;
};
function View() {
  const { params, cancel, finish } = usePageRuntime<Params>();
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);
  const busy = useRef(false);
  const [unknown, setUnknown] = useState(false);
  const colors = usePalette();
  const right = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('pr.send'),
        accessibilityLabel: t('pr.send'),
        tintColor: PlatformColor('systemBlue'),
        disabled: !body.trim() || sending || unknown,
        onPress: async () => {
          if (busy.current || unknown) return;
          busy.current = true;
          setSending(true);
          try {
            if (await params.onSubmit(body.trim())) finish();
          } catch (error) {
            const code = error instanceof Error ? error.message : 'unavailable';
            if (code.includes('comment_unknown')) setUnknown(true);
            Alert.alert(t('pr.comment'), pullRequestError(code));
          } finally {
            busy.current = false;
            setSending(false);
          }
        },
      },
    ],
    [body, params.onSubmit, sending, unknown, finish],
  );
  const left = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.cancel'),
        accessibilityLabel: t('common.cancel'),
        tintColor: PlatformColor('systemBlue'),
        disabled: sending,
        onPress: () => {
          if (!body.trim()) {
            cancel();
            return;
          }
          Alert.alert(t('pr.discard'), undefined, [
            { text: t('common.cancel'), style: 'cancel' },
            { text: t('pr.discard'), style: 'destructive', onPress: cancel },
          ]);
        },
      },
    ],
    [body, cancel, sending],
  );
  useSheetHeader(right, left);
  return (
    <SafeAreaProvider>
      <SafeAreaView edges={['top']} style={{ flex: 1 }}>
        <Screen automaticallyAdjustKeyboardInsets>
          <AppText variant="secondary">
            {params.repository} · PR #{params.number}
          </AppText>
          <TextInput
            testID="pr-comment-input"
            accessibilityLabel={t('pr.comment')}
            multiline
            editable={!sending}
            maxLength={65536}
            autoFocus
            value={body}
            onChangeText={setBody}
            placeholder={t('pr.commentPlaceholder')}
            placeholderTextColor={colors.tertiaryLabel}
            style={{
              color: colors.label,
              minHeight: 160,
              fontSize: 17,
              lineHeight: 25,
              textAlignVertical: 'top',
            }}
          />
        </Screen>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}
export const PullRequestCommentScreen = definePage<Params>({
  id: 'pull-request-comment',
  title: t('pr.comment'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from a pull request');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    dismissible: false,
    sheetAllowedDetents: [1],
  },
});
