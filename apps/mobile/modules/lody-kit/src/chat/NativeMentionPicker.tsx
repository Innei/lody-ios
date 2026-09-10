import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export const NativeMentionPicker: ComponentType<
  ViewProps & {
    configurationJSON: string;
    onQueryReset: () => void;
    onRetry: () => void;
    onPick: (event: NativeSyntheticEvent<{ path: string }>) => void;
  }
> = requireNativeView('LodyKit', 'LodyMentionPickerView');
