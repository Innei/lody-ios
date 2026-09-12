import { use, useEffect, type ReactNode } from 'react';
import {
  SheetHeaderContext,
  type HeaderItems,
} from '@/lib/presentation/SheetStack';

export function useSheetHeader(
  items: HeaderItems,
  left?: HeaderItems,
  rightView?: ReactNode,
) {
  const setItems = use(SheetHeaderContext);
  useEffect(() => {
    setItems?.({ right: items, left, rightView });
    return () => setItems?.(undefined);
  }, [setItems, items, left, rightView]);
}
