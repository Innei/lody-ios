import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type MessageShareBlock = {
  id: number;
  kind:
    | 'heading'
    | 'paragraph'
    | 'list'
    | 'code'
    | 'table'
    | 'quote'
    | 'divider'
    | 'image';
  text: string;
};

export const NativeMessageShare: ComponentType<
  ViewProps & {
    contentJSON: string;
    selectedJSON: string;
    onBlocks: (
      event: NativeSyntheticEvent<{ blocks: MessageShareBlock[] }>,
    ) => void;
    shareToken: number;
    retryToken: number;
    onState: (
      event: NativeSyntheticEvent<{
        state: 'loading' | 'ready' | 'error' | 'empty';
        message?: string;
        retryable?: boolean;
      }>,
    ) => void;
  }
> = requireNativeView('LodyKit', 'LodyMessageShareView');
