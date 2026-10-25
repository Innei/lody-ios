import type { ReactNode } from 'react';
import type { ColorValue } from 'react-native';
import type {
  HeaderBarButtonItem,
  HeaderBarButtonItemWithMenu,
  PlatformIconIOS,
} from 'react-native-screens';

export type NativeViewBarItem = {
  type: 'view';
  element: ReactNode;
  hidesSharedBackground?: boolean;
  sharesBackground?: boolean;
};
export type NativeBarItem =
  (HeaderBarButtonItem & { systemItem?: 'close' }) | NativeViewBarItem;
export type NativeToolbarItem =
  NativeBarItem | { type: 'flexibleSpacing' } | { type: 'searchSlot' };

export type Handlers = Map<string, () => void>;
export type SlotSizes = ReadonlyMap<number, { width: number; height: number }>;
type MenuEntries = HeaderBarButtonItemWithMenu['menu']['items'];

function symbol(icon: PlatformIconIOS | undefined) {
  return icon?.type === 'sfSymbol' ? icon.name : undefined;
}

function tint(color: ColorValue | undefined) {
  if (typeof color === 'string') return color;
  return (color as { semantic?: string[] } | undefined)?.semantic?.[0];
}

function menuEntries(
  entries: MenuEntries,
  prefix: string,
  handlers: Handlers,
): unknown[] {
  return entries.map((entry, index): unknown => {
    const id = `${prefix}${index}`;
    if (entry.type === 'submenu') {
      return {
        type: 'submenu',
        title: entry.title,
        icon: symbol(entry.icon),
        inline: entry.displayInline,
        items: menuEntries(entry.items, `${id}.`, handlers),
      };
    }
    handlers.set(id, entry.onPress);
    return {
      id,
      type: 'action',
      title: entry.title,
      subtitle: entry.subtitle,
      icon: symbol(entry.icon),
      disabled: entry.disabled,
      destructive: entry.destructive,
      hidden: entry.hidden,
      state: entry.state,
    };
  });
}

export function viewElements(groups: (NativeToolbarItem[] | undefined)[]) {
  return groups.flatMap((items) =>
    (items ?? []).flatMap((item) =>
      item.type === 'view' ? [item.element] : [],
    ),
  );
}

export function barItems(
  items: NativeToolbarItem[] | undefined,
  prefix: string,
  handlers: Handlers,
  slots: { next: number; sizes: SlotSizes },
) {
  return (items ?? []).map((item, index) => {
    const id = `${prefix}${index}`;
    if (item.type === 'spacing') {
      return { type: 'spacing', spacing: item.spacing };
    }
    if (item.type === 'flexibleSpacing' || item.type === 'searchSlot') {
      return { type: item.type };
    }
    if (item.type === 'view') {
      const slot = slots.next++;
      return {
        type: 'view',
        slot,
        width: slots.sizes.get(slot)?.width ?? 0,
        height: slots.sizes.get(slot)?.height ?? 0,
        hidesSharedBackground: item.hidesSharedBackground,
        sharesBackground: item.sharesBackground,
      };
    }
    const base = {
      id,
      type: item.type,
      title: item.title,
      icon: symbol(item.icon),
      accessibilityLabel: item.accessibilityLabel,
      accessibilityHint: item.accessibilityHint,
      identifier: item.identifier,
      systemItem: item.systemItem,
      badge: item.badge?.value,
      disabled: item.disabled,
      tintColor: tint(item.tintColor),
      hidesSharedBackground: item.hidesSharedBackground,
      sharesBackground: item.sharesBackground,
      variant: item.variant,
      width: item.width,
    };
    if (item.type === 'button') {
      handlers.set(id, item.onPress);
      return base;
    }
    return {
      ...base,
      menu: { items: menuEntries(item.menu.items, `${id}.`, handlers) },
    };
  });
}
