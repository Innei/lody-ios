import { getLayoutMode, type LayoutMode } from './layoutMode.ts';

export type PanelSheetToken = {
  handingOver: boolean;
  closing: boolean;
  covered: boolean;
  dismiss?: () => void;
};

let sheet: PanelSheetToken | undefined;

// Removing a modal from under another one makes react-native-screens reshuffle
// presented controllers, so a covered sheet waits until it is on top again.
function handOver(token: PanelSheetToken) {
  token.handingOver = true;
  if (!token.dismiss || token.covered || token.closing) return;
  token.closing = true;
  token.dismiss();
}

export function syncPanelSheet(
  mode: LayoutMode,
  open: boolean,
  presentSheet: (token: PanelSheetToken) => Promise<unknown>,
) {
  if (!open) return;
  if (mode === 'wide') {
    if (sheet) handOver(sheet);
    return;
  }
  if (sheet && !sheet.closing) {
    sheet.handingOver = false;
    return;
  }
  const token: PanelSheetToken = {
    handingOver: false,
    closing: false,
    covered: false,
  };
  sheet = token;
  void presentSheet(token).finally(() => {
    if (sheet === token) sheet = undefined;
  });
}

export function attachPanelSheet(token: PanelSheetToken, dismiss: () => void) {
  token.dismiss = dismiss;
  if (token.handingOver || getLayoutMode() === 'wide') handOver(token);
}

export function setPanelSheetCovered(token: PanelSheetToken, covered: boolean) {
  token.covered = covered;
  if (!covered && token.handingOver) handOver(token);
}

export function detachPanelSheet(token: PanelSheetToken): boolean {
  if (sheet === token) sheet = undefined;
  return !token.handingOver;
}
