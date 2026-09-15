import type { PropsWithChildren } from 'react';
import { ScrollView, StyleSheet } from 'react-native';
import { ScrollViewMarker } from 'react-native-screens/experimental';

import { navigationScrollEdgeEffects } from '@lody-ios/kit';

export function Screen({
  children,
  automaticallyAdjustKeyboardInsets = false,
}: PropsWithChildren<{ automaticallyAdjustKeyboardInsets?: boolean }>) {
  return (
    <ScrollViewMarker
      scrollEdgeEffects={navigationScrollEdgeEffects}
      style={styles.root}
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
