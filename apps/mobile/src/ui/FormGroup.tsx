import type { ReactNode } from 'react';
import { PlatformColor, StyleSheet, View } from 'react-native';
import { usePalette } from '@/lib/theme/palette';
import { AppText } from '@/ui/AppText';

export function FormGroup({
  header,
  footer,
  children,
}: {
  header?: string;
  footer?: string;
  children: ReactNode;
}) {
  const colors = usePalette();
  const surface =
    colors.theme === 'dark'
      ? PlatformColor('tertiarySystemGroupedBackground')
      : colors.card;
  return (
    <View style={styles.group}>
      {header ? (
        <AppText
          variant="meta"
          accessibilityRole="header"
          style={[styles.groupText, styles.groupHeader]}
        >
          {header}
        </AppText>
      ) : null}
      <View style={[styles.card, { backgroundColor: surface }]}>
        {children}
      </View>
      {footer ? (
        <AppText variant="meta" style={styles.groupText}>
          {footer}
        </AppText>
      ) : null}
    </View>
  );
}

export const formInputStyle = StyleSheet.create({
  input: {
    paddingHorizontal: 16,
    paddingVertical: 11,
    minHeight: 44,
    fontSize: 17,
  },
}).input;

const styles = StyleSheet.create({
  group: { gap: 7, marginBottom: 12 },
  groupText: { paddingHorizontal: 16 },
  groupHeader: { textTransform: 'uppercase' },
  card: {
    borderRadius: 26,
    borderCurve: 'continuous',
    overflow: 'hidden',
  },
});
