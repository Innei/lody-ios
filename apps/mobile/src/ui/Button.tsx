import { NativeGlassSurface, NativePressable } from '@lody-ios/kit';
import type { ColorValue, StyleProp, ViewStyle } from 'react-native';
import { usePalette } from '@/theme/palette';
import { AppText } from './AppText';

export type ButtonVariant = 'filled' | 'glass' | 'plain';

export function Button({
  label,
  children,
  onPress,
  variant = 'plain',
  disabled = false,
  destructive = false,
  testID,
  style,
}: {
  label?: string;
  children?: string;
  onPress: () => void;
  variant?: ButtonVariant;
  disabled?: boolean;
  destructive?: boolean;
  testID?: string;
  style?: StyleProp<ViewStyle>;
}) {
  const colors = usePalette();
  const glass = variant === 'glass';
  const filled = variant === 'filled';
  const surface = filled || glass;
  const text = label ?? children ?? '';
  let color: ColorValue = colors.accent;
  if (filled) color = colors.onAccent;
  else if (destructive) color = colors.danger;
  return (
    <NativePressable
      testID={testID}
      accessibilityLabel={text}
      disabled={disabled}
      onPress={onPress}
      style={[
        {
          minHeight: 44,
          paddingHorizontal: surface ? 20 : 0,
          borderRadius: filled ? 12 : 0,
          borderCurve: 'continuous',
          alignItems: 'center',
          justifyContent: 'center',
          backgroundColor: filled ? colors.accent : undefined,
          opacity: disabled ? 0.4 : 1,
        },
        style,
      ]}
    >
      {glass ? <NativeGlassSurface radius={14} /> : null}
      <AppText
        variant="body"
        style={{
          color,
          fontWeight: surface ? '600' : '400',
        }}
      >
        {text}
      </AppText>
    </NativePressable>
  );
}
