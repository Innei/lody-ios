import { useMemo, useState } from 'react';
import { Alert } from 'react-native';
import { NativeGroupedList } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSheetHeader } from '@/hooks/screens/useSheetHeader';
import { useQuickReplies } from '@/features/settings/quick-replies';
import { reorderQuickReplies } from '@/features/settings/quickReplies';
import { t } from '@/lib/i18n';
import { usePalette } from '@/lib/theme/palette';
import { QuickReplyEditorScreen } from './QuickReplyEditorScreen';

function View() {
  const { present } = usePageRuntime();
  const { quickReplies, setQuickReplies } = useQuickReplies();
  const [editing, setEditing] = useState(false);
  const colors = usePalette();
  const actions = useMemo(
    () => [
      {
        type: 'button' as const,
        title: t(editing ? 'common.done' : 'common.edit'),
        accessibilityLabel: t(editing ? 'common.done' : 'common.edit'),
        disabled: quickReplies.length < 2 && !editing,
        onPress: () => setEditing((value) => !value),
      },
      {
        type: 'button' as const,
        icon: { type: 'sfSymbol' as const, name: 'plus' },
        accessibilityLabel: t('settings.quickReplies.add'),
        tintColor: colors.accent,
        disabled: editing,
        onPress: () =>
          void present(
            QuickReplyEditorScreen,
            {},
            { title: t('settings.quickReplies.add') },
          ),
      },
    ],
    [editing, quickReplies.length, present, colors.accent],
  );
  useSheetHeader(actions);
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      reordering={editing}
      sections={[
        {
          id: 'quick-replies',
          footer: t(
            editing
              ? 'settings.quickReplies.reorderHint'
              : 'settings.quickReplies.hint',
          ),
          rows: quickReplies.map((item) => ({
            id: item.id,
            title: item.label,
            subtitle: item.message,
            action: !editing,
            disclosure: !editing,
            actions: [
              {
                id: 'delete',
                title: t('common.delete'),
                symbol: 'trash',
                destructive: true,
              },
            ],
          })),
        },
      ]}
      placeholder={t('settings.quickReplies.empty')}
      onRowPress={({ nativeEvent: { id } }) => {
        const item = quickReplies.find((item) => item.id === id);
        if (item) void present(QuickReplyEditorScreen, { item });
      }}
      onRowAction={({ nativeEvent: { id, actionId } }) => {
        if (actionId !== 'delete') return;
        Alert.alert(
          t('settings.quickReplies.deleteTitle'),
          t('settings.quickReplies.deleteHint'),
          [
            { text: t('common.cancel'), style: 'cancel' },
            {
              text: t('common.delete'),
              style: 'destructive',
              onPress: () => {
                if (
                  setQuickReplies(quickReplies.filter((item) => item.id !== id))
                )
                  setEditing(false);
              },
            },
          ],
        );
      }}
      onReorder={({ nativeEvent: { ids } }) =>
        setQuickReplies(reorderQuickReplies(quickReplies, ids))
      }
    />
  );
}

export const QuickRepliesScreen = definePage({
  id: 'quick-replies',
  title: t('settings.quickReplies.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
