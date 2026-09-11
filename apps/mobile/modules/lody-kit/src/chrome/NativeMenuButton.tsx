import { requireNativeView } from 'expo';
import { type ComponentType, useState } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type NativeMenuItem = {
  id: string;
  title: string;
  symbol?: string;
  selected?: boolean;
};

export interface NativeMenuButtonProps extends ViewProps {
  accessibilityName: string;
  avatar: { text: string; color: string; image?: string };
  label: string;
  items: NativeMenuItem[];
  onSelect: (id: string) => void;
}

const NativeView: ComponentType<
  Omit<NativeMenuButtonProps, 'onSelect'> & {
    onSelect: (event: NativeSyntheticEvent<{ id: string }>) => void;
    onSize: (event: NativeSyntheticEvent<{ width: number }>) => void;
  }
> = requireNativeView('LodyKit', 'LodyMenuButton');

export function NativeMenuButton({
  onSelect,
  style,
  ...props
}: NativeMenuButtonProps) {
  const [width, setWidth] = useState(44);
  return (
    <NativeView
      {...props}
      style={[{ width, height: 44 }, style]}
      onSelect={({ nativeEvent }) => onSelect(nativeEvent.id)}
      onSize={({ nativeEvent }) => setWidth(Math.ceil(nativeEvent.width))}
    />
  );
}
