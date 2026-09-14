import { NativeGroupedList, type NativeListSection } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { useQueuedMessageBehavior } from '@/features/settings/queued-message-behavior';
import {
  QUEUED_MESSAGE_BEHAVIORS,
  parseQueuedMessageBehavior,
} from '@/features/sessions/messageSubmitRoute';
import { usePalette } from '@/lib/theme/palette';
import { t } from '@/lib/i18n';

function View() {
  const colors = usePalette();
  const { queuedMessageBehavior, setQueuedMessageBehavior } =
    useQueuedMessageBehavior();
  const sections: NativeListSection[] = [
    {
      id: 'queued-message-behavior',
      footer: t('settings.queuedMessageBehavior.hint'),
      rows: QUEUED_MESSAGE_BEHAVIORS.map((option) => ({
        id: `queued-message-behavior-${option}`,
        title: t(`settings.queuedMessageBehavior.${option}`),
        action: true,
        selected: option === queuedMessageBehavior,
        accessibilityValue:
          option === queuedMessageBehavior
            ? t('settings.history.selected')
            : undefined,
      })),
    },
  ];
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={sections}
      placeholder=""
      onRowPress={({ nativeEvent }) => {
        const value = nativeEvent.id.replace('queued-message-behavior-', '');
        if (value === 'queue' || value === 'guide')
          setQueuedMessageBehavior(parseQueuedMessageBehavior(value));
      }}
    />
  );
}

export const QueuedMessageBehaviorScreen = definePage({
  id: 'queued-message-behavior',
  title: t('settings.queuedMessageBehavior.title'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
