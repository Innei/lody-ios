import { requireNativeView } from 'expo';
import { useCallback, useMemo, type ComponentType } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';
import type {
  HeaderBarButtonItem,
  HeaderBarButtonItemWithMenu,
  PlatformIconIOS,
} from 'react-native-screens';

export interface NativeNavigationHeaderProps {
  items?: HeaderBarButtonItem[];
  leftItems?: HeaderBarButtonItem[];
  title?: string;
}

type Handlers = Map<string, () => void>;
type MenuEntries = HeaderBarButtonItemWithMenu['menu']['items'];

const NativeView: ComponentType<
  ViewProps & {
    itemsJSON: string;
    leftItemsJSON: string;
    title: string;
    onAction: (event: NativeSyntheticEvent<{ id: string }>) => void;
  }
> = requireNativeView('LodyKit', 'LodyNavigationHeaderView');

function symbol(icon: PlatformIconIOS | undefined) {
  return icon?.type === 'sfSymbol' ? icon.name : undefined;
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

function barItems(
  items: HeaderBarButtonItem[] | undefined,
  prefix: string,
  handlers: Handlers,
) {
  return (items ?? []).map((item, index) => {
    const id = `${prefix}${index}`;
    if (item.type === 'spacing') {
      return { type: 'spacing', spacing: item.spacing };
    }
    const base = {
      id,
      type: item.type,
      title: item.title,
      icon: symbol(item.icon),
      accessibilityLabel: item.accessibilityLabel,
      accessibilityHint: item.accessibilityHint,
      identifier: item.identifier,
      badge: item.badge?.value,
      disabled: item.disabled,
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

export function NativeNavigationHeader({
  items,
  leftItems,
  title,
}: NativeNavigationHeaderProps) {
  const spec = useMemo(() => {
    const handlers: Handlers = new Map();
    return {
      handlers,
      itemsJSON: items ? JSON.stringify(barItems(items, 'r', handlers)) : '',
      leftItemsJSON: leftItems
        ? JSON.stringify(barItems(leftItems, 'l', handlers))
        : '',
    };
  }, [items, leftItems]);
  const onAction = useCallback(
    (event: NativeSyntheticEvent<{ id: string }>) => {
      spec.handlers.get(event.nativeEvent.id)?.();
    },
    [spec],
  );
  return (
    <NativeView
      itemsJSON={spec.itemsJSON}
      leftItemsJSON={spec.leftItemsJSON}
      title={title ?? ''}
      onAction={onAction}
      style={{ position: 'absolute', width: 0, height: 0 }}
    />
  );
}
