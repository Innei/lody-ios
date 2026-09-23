import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type SessionShareAction =
  | 'publish'
  | 'retry'
  | 'discard'
  | 'copy'
  | 'share'
  | 'reset'
  | 'revoke'
  | 'includeChildren';

export const NativeSessionShare: ComponentType<
  ViewProps & {
    configurationJSON: string;
    onAction: (
      event: NativeSyntheticEvent<{
        action: SessionShareAction;
        value?: boolean;
      }>,
    ) => void;
  }
> = requireNativeView('LodyKit', 'LodySessionShareView');
