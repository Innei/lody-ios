import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { ViewProps } from 'react-native';

export const NativeInbox = requireNativeView(
  'LodyKit',
  'LodyInboxView',
) as ComponentType<ViewProps>;
