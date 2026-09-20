import { useMemo, useState } from 'react';
import { TextInput } from 'react-native';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { useQuickReplies } from '@/features/settings/quick-replies';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';
import { Screen } from '@/ui/Screen';
import { FormGroup, formInputStyle } from '@/ui/FormGroup';
import type { QuickReply } from '@/models/settings';

type Params = { item?: QuickReply };

function View() {
  const { params, finish, cancel } = usePageRuntime<Params>();
  const { quickReplies, setQuickReplies } = useQuickReplies();
  const colors = usePalette();
  const [label, setLabel] = useState(params.item?.label ?? '');
  const [message, setMessage] = useState(params.item?.message ?? '');
  const [id] = useState(
    () =>
      params.item?.id ?? `${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t('common.save'),
        accessibilityLabel: t('common.save'),
        variant: 'prominent' as const,
        tintColor: colors.accent,
        disabled: !label.trim() || !message.trim(),
        onPress: () => {
          if (!label.trim() || !message.trim()) return;
          const item = { id, label: label.trim(), message };
          let next = [...quickReplies, item];
          if (params.item)
            next = quickReplies.map((old) => (old.id === id ? item : old));
          if (setQuickReplies(next)) finish();
        },
      },
    ],
    [
      label,
      message,
      id,
      params.item,
      quickReplies,
      setQuickReplies,
      finish,
      colors.accent,
    ],
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
      <FormGroup header={t('settings.quickReplies.label')}>
        <TextInput
          testID="quick-reply-label"
          accessibilityLabel={t('settings.quickReplies.label')}
          style={[formInputStyle, { color: colors.label }]}
          value={label}
          onChangeText={setLabel}
          maxLength={40}
          clearButtonMode="while-editing"
          autoCorrect={false}
        />
      </FormGroup>
      <FormGroup
        header={t('settings.quickReplies.message')}
        footer={t('settings.quickReplies.sendHint')}
      >
        <TextInput
          testID="quick-reply-message"
          accessibilityLabel={t('settings.quickReplies.message')}
          style={[
            formInputStyle,
            { color: colors.label, minHeight: 144, textAlignVertical: 'top' },
          ]}
          value={message}
          onChangeText={setMessage}
          maxLength={32000}
          multiline
          scrollEnabled={false}
        />
      </FormGroup>
    </Screen>
  );
}

export const QuickReplyEditorScreen = definePage<Params>({
  id: 'quick-reply-editor',
  title: t('settings.quickReplies.edit'),
  Component: View,
  parseRouteParams: () => {
    throw new Error('Open from quick replies');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
