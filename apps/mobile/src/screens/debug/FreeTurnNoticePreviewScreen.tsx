import { useState } from 'react';
import { Alert, Pressable, View, type ColorValue } from 'react-native';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import {
  freeTurnLimitReached,
  freeTurnNotice,
} from '@/features/sessions/freeTurnNotice';
import { AppText } from '@/ui/AppText';
import { t } from '@/lib/i18n';

function Choice({
  id,
  label,
  selected,
  onPress,
}: {
  id: string;
  label: string;
  selected: boolean;
  onPress: () => void;
}) {
  const colors = usePalette();
  let color: ColorValue = colors.secondaryLabel;
  let background: ColorValue = colors.fill;
  if (selected) {
    color = colors.accent;
    background = colors.inset;
  }
  return (
    <Pressable
      testID={id}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={{
        minHeight: 44,
        paddingHorizontal: 14,
        borderRadius: 22,
        borderCurve: 'continuous',
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: background,
      }}
    >
      <AppText variant="meta" style={{ color, fontWeight: '600' }}>
        {label}
      </AppText>
    </Pressable>
  );
}

function Preview() {
  const colors = usePalette();
  const [count, setCount] = useState(24);
  const [tier, setTier] = useState<'free' | 'plus'>('free');
  const [clearDraftToken, setClearDraftToken] = useState(0);
  const locked = freeTurnLimitReached(count, tier);
  let placeholder = 'Message';
  if (locked) placeholder = '';
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <View
        style={{
          paddingTop: 110,
          paddingHorizontal: 16,
          flexDirection: 'row',
          flexWrap: 'wrap',
          gap: 8,
        }}
      >
        {[24, 25, 29, 30].map((value) => (
          <Choice
            key={value}
            id={`free-turn-${value}`}
            label={`${value}`}
            selected={tier === 'free' && count === value}
            onPress={() => {
              const enteringLimit =
                freeTurnLimitReached(value, 'free') && !locked;
              setTier('free');
              setCount(value);
              if (!enteringLimit) return;
              Alert.alert(
                t('chat.composer.freeTurnLimitTitle'),
                t('chat.composer.freeTurnLimitBody'),
                [{ text: t('common.ok') }],
              );
            }}
          />
        ))}
        <Choice
          id="free-turn-plus"
          label="Plus"
          selected={tier === 'plus'}
          onPress={() => setTier('plus')}
        />
      </View>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON="[]"
        composerJSON={JSON.stringify({
          editable: !locked,
          canSend: false,
          sending: false,
          notice: '',
          quotaNotice: locked ? '' : freeTurnNotice(count, tier),
          quotaLocked: locked,
          reconnect: false,
          placeholder,
        })}
        clearDraftToken={clearDraftToken}
        emptyText="Free turn reminder"
        onSend={() => {
          setCount((value) => value + 1);
          setClearDraftToken((value) => value + 1);
        }}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </View>
  );
}

export const FreeTurnNoticePreviewScreen = definePage({
  id: 'free-turn-notice-preview',
  title: 'Free turn reminder',
  Component: Preview,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
