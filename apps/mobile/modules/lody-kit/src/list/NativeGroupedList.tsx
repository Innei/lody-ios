import { requireNativeView } from 'expo';
import { createElement, type ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type {
  NativeListAction,
  NativeListRow,
  NativeListSection,
} from './NativeList';
import type { NativeListSection } from './NativeList';

export type NativeGroupedListProps = ViewProps & {
  sections: NativeListSection[];
  segments?: string[];
  /** Ride the search bar's scope bar; only for screens that also want search. */
  segmentsUseSearchScope?: boolean;
  selectedSegment?: number;
  onSegmentChange?: (event: NativeSyntheticEvent<{ index: number }>) => void;
  /** Default row tint; `#RRGGBB`. Rows may override with `imageTint`. */
  accent?: string;
  /** Drop the list's own background so a sheet's material shows through. */
  transparent?: boolean;
  /** Total height reserved for a floating bottom accessory, including safe area. */
  bottomInset?: number;
  /** Project sections with tappable headings and compact session details. */
  contentStyle?: boolean;
  placeholder?: string;
  refreshing?: boolean;
  onRefresh?: () => void;
  /** `expanded` accompanies a parent row when UIKit toggles its outline. */
  onRowPress: (
    event: NativeSyntheticEvent<{ id: string; expanded?: boolean }>,
  ) => void;
  onRowToggle?: (
    event: NativeSyntheticEvent<{ id: string; value: boolean }>,
  ) => void;
  onRowAction?: (
    event: NativeSyntheticEvent<{ id: string; actionId: string }>,
  ) => void;
  previewUserId?: string;
  previewWorkspaceId?: string;
};

type NativeGroupedListBridgeProps = NativeGroupedListProps & {
  refreshEnabled: boolean;
};

const NativeGroupedListView = requireNativeView(
  'LodyKit',
  'LodyGroupedList',
) as ComponentType<NativeGroupedListBridgeProps>;

export const NativeGroupedList: ComponentType<NativeGroupedListProps> = ({
  onRefresh,
  ...props
}) =>
  createElement(NativeGroupedListView, {
    ...props,
    onRefresh,
    refreshEnabled: !!onRefresh,
  });
