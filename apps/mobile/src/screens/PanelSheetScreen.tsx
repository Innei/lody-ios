import { useIsFocused } from '@/lib/presentation/focus';
import { useEffect } from 'react';
import { definePage, present } from '@/lib/presentation';
import type { LayoutMode } from '@/lib/presentation/layoutMode';
import { closePanel } from '@/lib/presentation/panelStore';
import {
  attachPanelSheet,
  detachPanelSheet,
  type PanelSheetToken,
  setPanelSheetCovered,
  syncPanelSheet,
} from '@/lib/presentation/panelSheet';
import { PanelStack, usePanelEntries } from '@/lib/presentation/PanelStack';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';

type PanelSheetParams = { token: PanelSheetToken };

function PanelSheet() {
  const { cancel, params } = usePageRuntime<PanelSheetParams>();
  const { token } = params;
  const entries = usePanelEntries();
  const colors = usePalette();
  const focused = useIsFocused();
  useEffect(() => {
    attachPanelSheet(token, cancel);
    return () => {
      if (detachPanelSheet(token)) closePanel();
    };
  }, [cancel, token]);
  useEffect(() => {
    setPanelSheetCovered(token, !focused);
  }, [focused, token]);
  useEffect(() => {
    if (!entries.length) cancel();
  }, [cancel, entries.length]);
  return <PanelStack entries={entries} backgroundColor={colors.reading} />;
}

export const PanelSheetScreen = definePage<PanelSheetParams>({
  id: 'panel-sheet',
  title: '',
  Component: PanelSheet,
  presentation: {
    style: 'formSheet',
    headerShown: false,
    sheetAllowedDetents: [0.5, 1],
    sheetGrabberVisible: true,
  },
});

export function usePanelSheet(mode: LayoutMode) {
  const entries = usePanelEntries();
  const open = entries.length > 0;
  useEffect(() => {
    syncPanelSheet(mode, open, (token) => present(PanelSheetScreen, { token }));
  }, [mode, open]);
}
