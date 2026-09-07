import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import { StyleSheet, type ViewProps } from 'react-native';

export interface NativeGlassSurfaceProps extends ViewProps {
  radius?: number;
  tint?: string;
}

const NativeView: ComponentType<NativeGlassSurfaceProps> = requireNativeView(
  'LodyKit',
  'LodyGlassSurface',
);

export function NativeGlassSurface({
  radius = 14,
  tint = '',
  style,
  ...rest
}: NativeGlassSurfaceProps) {
  return (
    <NativeView
      {...rest}
      pointerEvents="none"
      radius={radius}
      tint={tint}
      style={[StyleSheet.absoluteFill, style]}
    />
  );
}
