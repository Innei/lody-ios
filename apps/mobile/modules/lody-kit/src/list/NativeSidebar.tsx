import { requireNativeView } from 'expo';
import type { ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';
import type { NativeListSection } from './NativeList';

/** Navigation sidebar, not a grouped-list appearance or a device switch. */
export type NativeSidebarProps = ViewProps & {
  sections: NativeListSection[];
  selectedRowId?: string;
  placeholder?: string;
  accent?: string;
  previewUserId?: string;
  previewWorkspaceId?: string;
  onRowPress: (
    event: NativeSyntheticEvent<{ id: string; expanded?: boolean }>,
  ) => void;
  onRowAction: (
    event: NativeSyntheticEvent<{ id: string; actionId: string }>,
  ) => void;
};

export const NativeSidebar = requireNativeView(
  'LodyKit',
  'LodySidebar',
) as ComponentType<NativeSidebarProps>;
