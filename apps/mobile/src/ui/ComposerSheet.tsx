import { useState, type ComponentProps, type ReactNode } from 'react';
import { View } from 'react-native';
import {
  NativeGroupedList,
  NativePagedList,
  type NativePagedPage,
} from '@lody-ios/kit';
import type { NativeSyntheticEvent } from 'react-native';

type ListProps = ComponentProps<typeof NativeGroupedList>;

export function ComposerSheet({
  children,
  pages,
  selectedPage,
  onPageChange,
  ...list
}: ListProps & {
  children: ReactNode;
  pages?: NativePagedPage[];
  selectedPage?: number;
  onPageChange?: (event: NativeSyntheticEvent<{ index: number }>) => void;
}) {
  const [bottomInset, setBottomInset] = useState(80);
  const form =
    pages && pages.length > 1 ? (
      <NativePagedList
        accent={list.accent}
        pages={pages}
        selectedPage={selectedPage}
        onPageChange={onPageChange}
        onRowPress={list.onRowPress}
        transparent
        style={{ flex: 1 }}
        bottomInset={bottomInset}
      />
    ) : (
      <NativeGroupedList
        {...list}
        sections={pages?.[0]?.sections ?? list.sections}
        transparent
        style={{ flex: 1 }}
        bottomInset={bottomInset}
      />
    );
  return (
    <View style={{ flex: 1 }}>
      {form}
      <View
        style={{ position: 'absolute', left: 0, right: 0, bottom: 0 }}
        onLayout={({ nativeEvent }) =>
          setBottomInset(nativeEvent.layout.height)
        }
      >
        {children}
      </View>
    </View>
  );
}
