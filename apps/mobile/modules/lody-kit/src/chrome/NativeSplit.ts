import { requireNativeView } from 'expo';
import type { ComponentType, ReactNode } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';
export { SafeAreaView as NativeSplitContent } from 'react-native-screens/experimental';

export type NativeSplitFrame = {
  left: number;
  top: number;
  width: number;
  height: number;
};

export type NativeSplitLayout = {
  primary: NativeSplitFrame;
  secondary: NativeSplitFrame;
};

export const NativeSplit = requireNativeView(
  'LodyKit',
  'LodySplitView',
) as ComponentType<
  ViewProps & {
    children: ReactNode;
    hasDetail: boolean;
    detailRequest: number;
    onColumnLayout: (event: NativeSyntheticEvent<NativeSplitLayout>) => void;
  }
>;
