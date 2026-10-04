import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type NativeMarkdownDocumentViewProps = ViewProps & {
  /** A ContentStore handle from `readFile`. */
  handle: string;
  onFilePress?: (
    event: NativeSyntheticEvent<{ path: string; line?: number }>,
  ) => void;
  onFail?: (event: NativeSyntheticEvent<{ message: string }>) => void;
};

export const NativeMarkdownDocumentView: ComponentType<NativeMarkdownDocumentViewProps> =
  requireNativeView('LodyKit', 'LodyMarkdownDocumentView');
