import { useMemo, useState } from 'react';
import { TextInput, type KeyboardTypeOptions } from 'react-native';
import { NativeNavigationHeader } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import { Screen } from '@/ui/Screen';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import { copy } from '@/features/schedules/model';

type Params = {
  title: string;
  value: string;
  multiline?: boolean;
  maxLength?: number;
  keyboardType?: KeyboardTypeOptions;
  hint?: string;
};
function View() {
  const { params, finish, cancel } = usePageRuntime<Params, string>(),
    colors = usePalette();
  const [value, setValue] = useState(params.value);
  const items = useMemo(
    () => [
      {
        type: 'button' as const,
        title: copy('common.done'),
        accessibilityLabel: copy('common.done'),
        variant: 'prominent' as const,
        onPress: () => finish(value),
      },
    ],
    [finish, value],
  );
  const left = useMemo(
    () => [
      {
        type: 'button' as const,
        title: copy('common.cancel'),
        accessibilityLabel: copy('common.cancel'),
        onPress: cancel,
      },
    ],
    [cancel],
  );
  return (
    <>
      <NativeNavigationHeader
        title={params.title}
        items={items}
        leftItems={left}
      />
      <Screen automaticallyAdjustKeyboardInsets>
        <FormGroup header={params.title} footer={params.hint}>
          <TextInput
            testID="schedule-field"
            accessibilityLabel={params.title}
            autoFocus
            value={value}
            onChangeText={setValue}
            style={[
              formInputStyle,
              {
                color: colors.label,
                minHeight: params.multiline ? 160 : 44,
                textAlignVertical: 'top',
              },
            ]}
            multiline={params.multiline}
            scrollEnabled={false}
            maxLength={params.maxLength}
            keyboardType={params.keyboardType}
            autoCorrect={params.multiline}
            autoCapitalize={params.multiline ? 'sentences' : 'none'}
            clearButtonMode="while-editing"
          />
        </FormGroup>
      </Screen>
    </>
  );
}
export const ScheduleFieldScreen = definePage<Params, string>({
  id: 'schedule-field',
  title: copy('schedules.edit'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from schedule editor');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
