import { type RefObject, useEffect, useMemo, useRef } from 'react';
import type { SearchBarProps } from 'react-native-screens';
import type {
  NativeHeaderSearch,
  NativeHeaderSearchCommands,
} from '@lody-ios/kit';

type Placement = NativeHeaderSearch['placement'];

const event = (nativeEvent: object) => ({ nativeEvent }) as never;

export function useShellSearch(search: SearchBarProps | undefined): {
  search: NativeHeaderSearch | undefined;
  ref: RefObject<NativeHeaderSearchCommands | null>;
} {
  const ref = useRef<NativeHeaderSearchCommands>(null);
  useEffect(() => {
    if (!search?.ref) return;
    const target = search.ref;
    target.current = {
      focus: () => ref.current?.focus(),
      blur: () => ref.current?.blur(),
      clearText: () => ref.current?.clearText(),
      cancelSearch: () => ref.current?.cancelSearch(),
      setText: () => {},
      toggleCancelButton: () => {},
    };
    return () => {
      target.current = null;
    };
  }, [search?.ref]);
  const native = useMemo<NativeHeaderSearch | undefined>(() => {
    if (!search) return undefined;
    return {
      placeholder: search.placeholder,
      placement: search.placement as Placement,
      hideWhenScrolling: search.hideWhenScrolling,
      autoCapitalize:
        search.autoCapitalize === 'systemDefault'
          ? undefined
          : search.autoCapitalize,
      obscureBackground: search.obscureBackground,
      hideNavigationBar: search.hideNavigationBar,
      onChangeText: (text) => search.onChangeText?.(event({ text })),
      onCancel: () => search.onCancelButtonPress?.(event({ target: 0 })),
      onFocus: () => search.onFocus?.(event({ target: 0 })),
      onBlur: () => search.onBlur?.(event({ target: 0 })),
      onSubmit: (text) => search.onSearchButtonPress?.(event({ text })),
    };
  }, [search]);
  return { search: native, ref };
}
