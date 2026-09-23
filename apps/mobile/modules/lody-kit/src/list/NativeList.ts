export type NativeListAction = {
  id: string;
  title: string;
  symbol?: string;
  /** Semantic name (warning/danger/yellow) or `#RRGGBB`; destructive stays system red. */
  tint?: string;
  destructive?: boolean;
  selected?: boolean;
};

export type NativeListRow = {
  id: string;
  title: string;
  subtitle?: string;
  /** Session model, kept visible after the truncatable project/branch metadata. */
  modelName?: string;
  /** Paths, branches and ids read as data, not prose. */
  subtitleMono?: boolean;
  wrapSubtitle?: boolean;
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
  /** Preserve full-color artwork and round it like an app icon. */
  imageOriginal?: boolean;
  /** File rows use bundled Material Icon Theme artwork. */
  filePath?: string;
  /** Semantic name (blue/green/purple/warning/danger/secondary/tertiary) or a `#RRGGBB` value. */
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
  /** A preceding row in this section; independent session provenance, not containment. */
  parentId?: string;
  /** Nonempty on session outline parents; shown while their children are collapsed. */
  collapsedValue?: string;
  collapsedBadge?: string;
  collapsedImageTint?: string;
  monogram?: string;
  pinned?: boolean;
  /** Trailing swipe actions. */
  actions?: NativeListAction[];
  leadingActions?: NativeListAction[];
  /** Long-press UIKit context menu. */
  menuActions?: NativeListAction[];
  /** Tap to choose an option in a native pop-up menu; emits onRowAction. */
  options?: NativeListAction[];
  /** Session rows may peek a cached transcript. */
  preview?: 'session';
};

export type NativeListSection = {
  id: string;
  header?: string;
  headerValue?: string;
  headerActionId?: string;
  headerExpanded?: boolean;
  headerProminent?: boolean;
  footer?: string;
  rows: NativeListRow[];
};
