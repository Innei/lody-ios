import type { PropsWithChildren } from 'react';
import { ScrollView, StyleSheet, type ViewProps } from 'react-native';
import { ScrollViewMarker } from 'react-native-screens/experimental';

import { navigationScrollEdgeEffects } from '@lody-ios/kit';

export function Screen({
  children,
  automaticallyAdjustKeyboardInsets = false,
  style,
}: PropsWithChildren<{
  automaticallyAdjustKeyboardInsets?: boolean;
  style?: ViewProps['style'];
}>) {
  return (
    <ScrollViewMarker
      scrollEdgeEffects={navigationScrollEdgeEffects}
      style={[styles.root, style]}
    >
      <ScrollView
        automaticallyAdjustKeyboardInsets={automaticallyAdjustKeyboardInsets}
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
