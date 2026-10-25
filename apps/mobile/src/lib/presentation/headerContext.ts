import { createContext, type ReactNode } from 'react';
import type {
  ScreenStackHeaderConfigProps,
  SearchBarProps,
} from 'react-native-screens';

export type HeaderItems =
  ScreenStackHeaderConfigProps['headerRightBarButtonItems'];
export type SheetHeaderItems = {
  right: HeaderItems;
  left?: HeaderItems;
  rightView?: ReactNode;
  title?: string;
};
export const SheetHeaderContext = createContext<
  ((items: SheetHeaderItems | undefined) => void) | null
>(null);

export const SheetSearchContext = createContext<
  ((search: SearchBarProps | undefined) => void) | null
>(null);
