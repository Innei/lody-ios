import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export const NativeAppIconGrid = requireNativeView(
  'LodyKit',
  'LodyAppIconGrid',
) as ComponentType<
  ViewProps & {
    items: { id: string; title: string }[];
    selected: string;
    pending: string;
    enabled: boolean;
    onSelect: (event: NativeSyntheticEvent<{ id: string }>) => void;
  }
>;
