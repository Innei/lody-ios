import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type NativeInlineDiffProps = ViewProps & {
  path: string;
  oldText?: string;
  newText?: string;
  onRender?: (
    event: NativeSyntheticEvent<{ fileCount: number; contentHeight: number }>,
  ) => void;
  onFail?: (event: NativeSyntheticEvent<{ message: string }>) => void;
};

export const NativeInlineDiff: ComponentType<NativeInlineDiffProps> =
  requireNativeView('LodyKit', 'LodyInlineDiffView');
