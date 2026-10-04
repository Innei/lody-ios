import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type NativeDiffToolbarProps = ViewProps & {
  add?: number;
  del?: number;
  base?: string;
  diffStyle: 'unified' | 'split';
  onStyleChange: (
    event: NativeSyntheticEvent<{ style: 'unified' | 'split' }>,
  ) => void;
};

export const NativeDiffToolbar: ComponentType<NativeDiffToolbarProps> =
  requireNativeView('LodyKit', 'LodyDiffToolbar');

export const NativeDiffSurface: ComponentType<
  ViewProps & { contentRevision?: number }
> = requireNativeView('LodyKit', 'LodyDiffSurface');
