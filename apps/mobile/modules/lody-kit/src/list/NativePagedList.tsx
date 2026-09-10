import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';
import type { NativeListSection } from './NativeGroupedList';

export type NativePagedPage = {
  id: string;
  title: string;
  sections: NativeListSection[];
};

export type NativePagedListProps = ViewProps & {
  pages: NativePagedPage[];
  selectedPage?: number;
  pagingEnabled?: boolean;
  accent?: string;
  transparent?: boolean;
  bottomInset?: number;
  onRowPress: (
    event: NativeSyntheticEvent<{ id: string; expanded?: boolean }>,
  ) => void;
  onPageChange?: (event: NativeSyntheticEvent<{ index: number }>) => void;
};

export const NativePagedList = requireNativeView(
  'LodyKit',
  'LodyPagedList',
) as ComponentType<NativePagedListProps>;
