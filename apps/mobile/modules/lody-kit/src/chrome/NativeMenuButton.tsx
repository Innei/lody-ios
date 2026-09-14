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
  header?: boolean;
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
  header,
  style,
  ...props
}: NativeMenuButtonProps) {
  const [width, setWidth] = useState(44);
  return (
    <NativeView
      {...props}
      header={!!header}
      collapsable={false}
      pointerEvents={header ? 'none' : 'auto'}
      style={header ? { width: 0, height: 0 } : [{ width, height: 44 }, style]}
      onSelect={({ nativeEvent }) => onSelect(nativeEvent.id)}
      onSize={({ nativeEvent }) => {
        if (!header) setWidth(Math.ceil(nativeEvent.width));
      }}
    />
  );
}
