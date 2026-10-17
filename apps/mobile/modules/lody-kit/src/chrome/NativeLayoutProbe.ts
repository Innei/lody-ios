import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type NativeLayoutTraits = {
  horizontal: 'compact' | 'regular';
  width: number;
  height: number;
};

export const NativeLayoutProbe = requireNativeView(
  'LodyKit',
  'LodyLayoutProbe',
) as ComponentType<
  ViewProps & {
    onTraits: (event: NativeSyntheticEvent<NativeLayoutTraits>) => void;
  }
>;
