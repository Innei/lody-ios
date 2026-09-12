import { requireNativeView } from 'expo';
import { createElement, type ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

export type NativeListAction = {
  id: string;
  title: string;
  symbol?: string;
  /** Semantic name (warning/danger/yellow) or `#RRGGBB`; destructive stays system red. */
  tint?: string;
  destructive?: boolean;
};

export type NativeListRow = {
  id: string;
  title: string;
  subtitle?: string;
  /** Session model, kept visible after the truncatable project/branch metadata. */
  modelName?: string;
  /** Paths, branches and ids read as data, not prose. */
  subtitleMono?: boolean;
  value?: string;
  /** Native progress row, normalized to 0...1. */
  progress?: number;
  /** Styled trailing value; text is also exposed together to VoiceOver. */
  valueSegments?: { text: string; tint?: string }[];
  /** Session rows only: bold title, trailing pill, +N −N after the subtitle. */
  unread?: boolean;
  badge?: string;
  diff?: { add: number; del: number };
  /** SF Symbol name, or an https/file/data image URL for a circular photo. */
  image?: string;
  /** Bundled template asset, rendered with the same semantic tint as SF Symbols. */
  imageAsset?: string;
  /** File rows use bundled Material Icon Theme artwork. */
  filePath?: string;
  /** Semantic name (blue/purple/warning/danger/secondary/tertiary) or a `#RRGGBB` value. */
  imageTint?: string;
  action?: boolean;
  selected?: boolean;
  accessibilityValue?: string;
  /** Trailing UISwitch; the row stops being selectable and `action` gates the switch. */
  toggle?: boolean;
  disclosure?: boolean;
  navigates?: boolean;
  destructive?: boolean;
  /** First row of a section: the section's outline header; `navigates` rows disclose instead of collapsing. */
  parent?: boolean;
  monogram?: string;
  pinned?: boolean;
  /** Trailing swipe actions. */
  actions?: NativeListAction[];
  leadingActions?: NativeListAction[];
  /** Long-press UIKit context menu. */
  menuActions?: NativeListAction[];
  /** Session rows may peek a cached transcript. */
  preview?: 'session';
};

export type NativeListSection = {
  id: string;
  header?: string;
  headerValue?: string;
  headerActionId?: string;
  headerExpanded?: boolean;
  footer?: string;
  rows: NativeListRow[];
};

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
