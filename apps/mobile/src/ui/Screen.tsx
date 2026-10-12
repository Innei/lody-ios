import type { PropsWithChildren } from 'react';
import type { StyleProp, ViewStyle } from 'react-native';
import { ScrollView, StyleSheet } from 'react-native';
import { ScrollViewMarker } from 'react-native-screens/experimental';

import { navigationScrollEdgeEffects } from '@lody-ios/kit';

export function Screen({
  children,
  style,
  automaticallyAdjustKeyboardInsets = false,
  scrollToOverflowEnabled = false,
}: PropsWithChildren<{
  style?: StyleProp<ViewStyle>;
  automaticallyAdjustKeyboardInsets?: boolean;
  scrollToOverflowEnabled?: boolean;
}>) {
  return (
    <ScrollViewMarker
      scrollEdgeEffects={navigationScrollEdgeEffects}
      style={[styles.root, style]}
    >
      <ScrollView
        automaticallyAdjustKeyboardInsets={automaticallyAdjustKeyboardInsets}
        scrollToOverflowEnabled={scrollToOverflowEnabled}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="interactive"
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={styles.content}
      >
        {children}
      </ScrollView>
    </ScrollViewMarker>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 12 },
});
