import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { ViewProps } from 'react-native';

export interface NativeSymbolButtonProps extends ViewProps {
  accessibilityName: string;
  symbol?: string;
  /** Bundled template artwork; takes precedence over the SF Symbol. */
  imageAsset?: string;
  prominent?: boolean;
  glass?: boolean;
  disabled?: boolean;
  tint?: string;
  onPress: () => void;
  onLongPress?: () => void;
}

const NativeView: ComponentType<
  Omit<NativeSymbolButtonProps, 'onPress' | 'onLongPress'> & {
    longPress?: boolean;
    onSymbolPress: () => void;
    onSymbolLongPress?: () => void;
  }
> = requireNativeView('LodyKit', 'LodySymbolButton');

export function NativeSymbolButton({
  onPress,
  onLongPress,
  ...props
}: NativeSymbolButtonProps) {
  return (
    <NativeView
      {...props}
      longPress={!!onLongPress}
      onSymbolPress={onPress}
      onSymbolLongPress={onLongPress}
    />
  );
}
