import { requireNativeView } from 'expo';
import {
  type ComponentType,
  type Ref,
  useCallback,
  useImperativeHandle,
  useMemo,
  useState,
} from 'react';
import {
  type LayoutChangeEvent,
  type NativeSyntheticEvent,
  View,
  type ViewProps,
} from 'react-native';

import {
  barItems,
  type Handlers,
  type NativeBarItem,
  type NativeToolbarItem,
  viewElements,
} from './navigationHeaderItems';

export type {
  NativeBarItem,
  NativeToolbarItem,
  NativeViewBarItem,
} from './navigationHeaderItems';

export interface NativeHeaderSearch {
  placeholder?: string;
  placement?:
    | 'automatic'
    | 'stacked'
    | 'inline'
    | 'integrated'
    | 'integratedButton'
    | 'integratedCentered';
  hideWhenScrolling?: boolean;
  autoCapitalize?: 'none' | 'words' | 'sentences' | 'characters';
  obscureBackground?: boolean;
  hideNavigationBar?: boolean;
  allowToolbarIntegration?: boolean;
  onChangeText?: (text: string) => void;
  onCancel?: () => void;
  onFocus?: () => void;
  onBlur?: () => void;
  onSubmit?: (text: string) => void;
}

export interface NativeHeaderSearchCommands {
  focus: () => void;
  blur: () => void;
  clearText: () => void;
  cancelSearch: () => void;
}

export interface NativeNavigationHeaderProps {
  items?: NativeBarItem[];
  leftItems?: NativeBarItem[];
  toolbarItems?: NativeToolbarItem[];
  title?: string;
  barHidden?: boolean;
  search?: NativeHeaderSearch;
  searchRef?: Ref<NativeHeaderSearchCommands>;
}

type SearchEvent = {
  type: 'change' | 'cancel' | 'focus' | 'blur' | 'submit';
  text: string;
};

const NativeView: ComponentType<
  ViewProps & {
    itemsJSON: string;
    leftItemsJSON: string;
    toolbarItemsJSON: string;
    searchJSON: string;
    searchCommandJSON: string;
    title: string;
    barHidden: boolean;
    onAction: (event: NativeSyntheticEvent<{ id: string }>) => void;
    onSearch: (event: NativeSyntheticEvent<SearchEvent>) => void;
  }
> = requireNativeView('LodyKit', 'LodyNavigationHeaderView');

function json(items: unknown[] | undefined) {
  return items ? JSON.stringify(items) : '';
}

export function NativeNavigationHeader({
  items,
  leftItems,
  toolbarItems,
  title,
  barHidden = false,
  search,
  searchRef,
}: NativeNavigationHeaderProps) {
  const [sizes, setSizes] = useState<
    ReadonlyMap<number, { width: number; height: number }>
  >(new Map());
  const [command, setCommand] = useState({ token: 0, action: '' });
  useImperativeHandle(searchRef, () => {
    const run = (action: string) =>
      setCommand((current) => ({ token: current.token + 1, action }));
    return {
      focus: () => run('focus'),
      blur: () => run('blur'),
      clearText: () => run('clearText'),
      cancelSearch: () => run('cancelSearch'),
    };
  }, []);
  const spec = useMemo(() => {
    const handlers: Handlers = new Map();
    const slots = { next: 0, sizes };
    const left = leftItems && barItems(leftItems, 'l', handlers, slots);
    const right = items && barItems(items, 'r', handlers, slots);
    const toolbar =
      toolbarItems && barItems(toolbarItems, 't', handlers, slots);
    return {
      handlers,
      itemsJSON: json(right),
      leftItemsJSON: json(left),
      toolbarItemsJSON: json(toolbar),
    };
  }, [items, leftItems, toolbarItems, sizes]);
  const views = viewElements([leftItems, items, toolbarItems]);
  const searchJSON = useMemo(() => {
    if (!search) return '';
    const {
      onChangeText: _change,
      onCancel: _cancel,
      onFocus: _focus,
      onBlur: _blur,
      onSubmit: _submit,
      ...config
    } = search;
    return JSON.stringify(config);
  }, [search]);
  const onAction = useCallback(
    (event: NativeSyntheticEvent<{ id: string }>) => {
      spec.handlers.get(event.nativeEvent.id)?.();
    },
    [spec],
  );
  const onSearch = useCallback(
    ({ nativeEvent: { type, text } }: NativeSyntheticEvent<SearchEvent>) => {
      if (type === 'change') search?.onChangeText?.(text);
      else if (type === 'cancel') search?.onCancel?.();
      else if (type === 'focus') search?.onFocus?.();
      else if (type === 'blur') search?.onBlur?.();
      else search?.onSubmit?.(text);
    },
    [search],
  );
  const measure = useCallback(
    (slot: number) =>
      ({ nativeEvent: { layout } }: LayoutChangeEvent) =>
        setSizes((current) => {
          const previous = current.get(slot);
          if (
            previous?.width === layout.width &&
            previous.height === layout.height
          )
            return current;
          const next = new Map(current);
          next.set(slot, { width: layout.width, height: layout.height });
          return next;
        }),
    [],
  );
  return (
    <NativeView
      itemsJSON={spec.itemsJSON}
      leftItemsJSON={spec.leftItemsJSON}
      toolbarItemsJSON={spec.toolbarItemsJSON}
      searchJSON={searchJSON}
      searchCommandJSON={command.token ? JSON.stringify(command) : ''}
      title={title ?? ''}
      barHidden={barHidden}
      onAction={onAction}
      onSearch={onSearch}
      style={{ position: 'absolute', width: 0, height: 0 }}
    >
      {views.map((element, slot) => (
        <View
          key={slot}
          collapsable={false}
          onLayout={measure(slot)}
          style={{ position: 'absolute', left: 0, top: 0 }}
        >
          {element}
        </View>
      ))}
    </NativeView>
  );
}
