import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export interface NativeSearchToolbarProps extends ViewProps {
  placeholder: string;
  actionAccessibilityName: string;
  tint?: string;
  visible?: boolean;
  onChangeText: (text: string) => void;
  onAction: () => void;
}

const NativeView: ComponentType<
  Omit<NativeSearchToolbarProps, 'onChangeText'> & {
    onSearchChange: (event: NativeSyntheticEvent<{ text: string }>) => void;
  }
> = requireNativeView('LodyKit', 'LodySearchToolbar');

export function NativeSearchToolbar({
  onChangeText,
  ...props
}: NativeSearchToolbarProps) {
  return (
    <NativeView
      {...props}
      style={[{ width: 0, height: 0 }, props.style]}
      onSearchChange={({ nativeEvent }) => onChangeText(nativeEvent.text)}
    />
  );
}
