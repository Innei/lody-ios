import { NativeGroupedList } from '@lody-ios/kit';
import { Linking } from 'react-native';
import { useQueuedMessageBehavior } from '@/features/settings/queued-message-behavior';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { showToast } from '@/ui/toast';
import { NotificationSettingsScreen } from './NotificationSettingsScreen';
import { QuickRepliesScreen } from './QuickRepliesScreen';

function View() {
  const { push } = usePageRuntime();
  const colors = usePalette();
  const { queuedMessageBehavior, setQueuedMessageBehavior } =
    useQueuedMessageBehavior();
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={[
        {
          id: 'language-section',
          footer: t('settings.preferences.languageHint'),
          rows: [
            {
              id: 'language',
              title: t('settings.preferences.language'),
              value: t('settings.preferences.languageName'),
              accessibilityValue: t('settings.preferences.languageName'),
              image: 'globe',
              action: true,
              disclosure: true,
            },
          ],
        },
        {
          id: 'notifications-section',
          header: t('settings.preferences.notifications'),
          rows: [
            {
              id: 'notifications',
              title: t('settings.notifications.title'),
              image: 'bell',
              action: true,
              disclosure: true,
              navigates: true,
            },
          ],
        },
        {
          id: 'chat',
          header: t('settings.preferences.chat'),
          footer: t('settings.queuedMessageBehavior.hint'),
          rows: [
            {
              id: 'queued-message-behavior',
              title: t('settings.queuedMessageBehavior.title'),
              value: t(
                `settings.queuedMessageBehavior.${queuedMessageBehavior}`,
              ),
              image: 'arrow.uturn.forward',
              action: true,
              options: (['queue', 'guide'] as const).map((value) => ({
                id: value,
                title: t(`settings.queuedMessageBehavior.${value}`),
                selected: value === queuedMessageBehavior,
              })),
            },
            {
              id: 'quick-replies',
              title: t('settings.quickReplies.title'),
              image: 'text.bubble',
              action: true,
              disclosure: true,
              navigates: true,
            },
          ],
        },
      ]}
      onRowAction={({ nativeEvent: { id, actionId } }) => {
        if (
          id === 'queued-message-behavior' &&
          (actionId === 'queue' || actionId === 'guide')
        )
          setQueuedMessageBehavior(actionId);
      }}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'language')
          void Linking.openSettings().catch(() =>
            showToast(t('settings.preferences.languageFailed')),
          );
        if (id === 'notifications') void push(NotificationSettingsScreen, {});
        if (id === 'quick-replies') void push(QuickRepliesScreen);
      }}
    />
  );
}

export const PreferencesScreen = definePage({
  id: 'preferences',
  title: t('settings.preferences.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
