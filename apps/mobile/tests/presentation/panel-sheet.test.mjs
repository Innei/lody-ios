import assert from 'node:assert/strict';
import { test } from 'node:test';

const { setLayoutTraits } =
  await import('../../src/lib/presentation/layoutMode.ts');
const {
  attachPanelSheet,
  detachPanelSheet,
  setPanelSheetCovered,
  syncPanelSheet,
} = await import('../../src/lib/presentation/panelSheet.ts');

const tall = { horizontal: 'regular', width: 669, height: 951 };
const wide = { horizontal: 'regular', width: 951, height: 669 };

function presenter() {
  const tokens = [];
  return {
    tokens,
    present: (token) => {
      tokens.push(token);
      return new Promise(() => {});
    },
  };
}

function settle(tokens) {
  for (const token of tokens) detachPanelSheet(token);
}

test('a sheet that mounts after the layout turned wide hands its stack over at once', () => {
  const sheets = presenter();
  setLayoutTraits(tall);
  syncPanelSheet('tall', true, sheets.present);
  setLayoutTraits(wide);
  syncPanelSheet('wide', true, sheets.present);
  let dismissed = 0;
  attachPanelSheet(sheets.tokens[0], () => dismissed++);
  assert.equal(dismissed, 1);
  assert.equal(detachPanelSheet(sheets.tokens[0]), false);
});

test('a replaced sheet tearing down late leaves the newer sheet in charge', () => {
  const sheets = presenter();
  setLayoutTraits(tall);
  syncPanelSheet('tall', true, sheets.present);
  const [first] = sheets.tokens;
  attachPanelSheet(first, () => {});
  setLayoutTraits(wide);
  syncPanelSheet('wide', true, sheets.present);
  setLayoutTraits(tall);
  syncPanelSheet('tall', true, sheets.present);
  assert.equal(sheets.tokens.length, 2);
  assert.equal(detachPanelSheet(first), false);
  syncPanelSheet('tall', true, sheets.present);
  assert.equal(sheets.tokens.length, 2);
  let dismissed = 0;
  attachPanelSheet(sheets.tokens[1], () => dismissed++);
  setLayoutTraits(wide);
  syncPanelSheet('wide', true, sheets.present);
  assert.equal(dismissed, 1);
  settle(sheets.tokens);
});

test('a sheet covered by another modal hands over only once it is on top again', () => {
  const sheets = presenter();
  setLayoutTraits(tall);
  syncPanelSheet('tall', true, sheets.present);
  const [sheet] = sheets.tokens;
  let dismissed = 0;
  attachPanelSheet(sheet, () => dismissed++);
  setPanelSheetCovered(sheet, true);
  setLayoutTraits(wide);
  syncPanelSheet('wide', true, sheets.present);
  assert.equal(dismissed, 0);
  setPanelSheetCovered(sheet, false);
  assert.equal(dismissed, 1);
  settle(sheets.tokens);
});

test('turning tall again before a covered sheet hands over keeps the sheet', () => {
  const sheets = presenter();
  setLayoutTraits(tall);
  syncPanelSheet('tall', true, sheets.present);
  const [sheet] = sheets.tokens;
  let dismissed = 0;
  attachPanelSheet(sheet, () => dismissed++);
  setPanelSheetCovered(sheet, true);
  setLayoutTraits(wide);
  syncPanelSheet('wide', true, sheets.present);
  setLayoutTraits(tall);
  syncPanelSheet('tall', true, sheets.present);
  setPanelSheetCovered(sheet, false);
  assert.equal(dismissed, 0);
  assert.equal(sheets.tokens.length, 1);
  assert.equal(detachPanelSheet(sheet), true);
});

test('a user dismissal closes the panel and the next tall open presents a new sheet', () => {
  const sheets = presenter();
  setLayoutTraits(tall);
  syncPanelSheet('tall', true, sheets.present);
  attachPanelSheet(sheets.tokens[0], () => {});
  assert.equal(detachPanelSheet(sheets.tokens[0]), true);
  syncPanelSheet('tall', true, sheets.present);
  assert.equal(sheets.tokens.length, 2);
  settle(sheets.tokens);
});
