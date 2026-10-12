import { useMemo, useState } from 'react';
import { TextInput } from 'react-native';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import { Screen } from '@/ui/Screen';
import { scrubFeedbackDiagnostics } from '@/features/feedback/report';

type Params = { value: string; title: string; diagnostics?: boolean };

function Content() {
  const { params, finish, cancel } = usePageRuntime<Params, string>();
  const colors = usePalette();
  const [value, setValue] = useState(params.value);
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.save'),
        accessibilityLabel: t('common.save'),
        variant: 'prominent' as const,
        tintColor: colors.accent,
        onPress: () =>
          finish(params.diagnostics ? scrubFeedbackDiagnostics(value) : value),
      },
    ],
    [colors.accent, finish, params.diagnostics, value],
  );
  const dismiss = useMemo(
    () => [
      { type: 'button' as const, title: t('common.cancel'), onPress: cancel },
    ],
    [cancel],
  );
  useSheetHeader(actions, dismiss);
  return (
    <Screen automaticallyAdjustKeyboardInsets>
      <FormGroup
        header={params.title}
        footer={params.diagnostics ? t('feedback.diagnosticsHint') : undefined}
      >
        <TextInput
          testID="feedback-editor"
          accessibilityLabel={params.title}
          value={value}
          onChangeText={setValue}
          maxLength={params.diagnostics ? 1500 : 4000}
          autoFocus
          multiline
          scrollEnabled={false}
          style={[
            formInputStyle,
            { minHeight: 180, color: colors.label, textAlignVertical: 'top' },
          ]}
        />
      </FormGroup>
    </Screen>
  );
}

export const FeedbackTextScreen = definePage<Params, string>({
  id: 'feedback-text',
  title: '',
  Component: Content,
  parseRouteParams: () => {
    throw new Error('Open the editor from a feedback draft');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});
