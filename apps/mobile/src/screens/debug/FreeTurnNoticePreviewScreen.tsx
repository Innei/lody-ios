import { useState } from 'react';
import { View } from 'react-native';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { freeTurnNotice } from '@/features/sessions/freeTurnNotice';
import { Button } from '@/ui/Button';

function Preview() {
  const colors = usePalette();
  const [count, setCount] = useState(24);
  const [tier, setTier] = useState<'free' | 'plus'>('free');
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
          <Button
            key={value}
            testID={`free-turn-${value}`}
            onPress={() => {
              setTier('free');
              setCount(value);
            }}
          >
            {`${value} turns`}
          </Button>
        ))}
        <Button testID="free-turn-plus" onPress={() => setTier('plus')}>
          Plus
        </Button>
      </View>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON="[]"
        composerJSON={JSON.stringify({
          editable: true,
          canSend: true,
          sending: false,
          notice: '',
          quotaNotice: freeTurnNotice(count, tier),
          reconnect: false,
          placeholder: 'Message',
        })}
        clearDraftToken={0}
        emptyText="Free turn reminder"
        onSend={() => {}}
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
