import assert from 'node:assert/strict';
import { test } from 'node:test';

const { setNavigator } =
  await import('../../src/lib/presentation/presentationStore.ts');
setNavigator(() => {});
const { getHomeDetail, setHomeDetail, showHomeSession } =
  await import('../../src/lib/presentation/homeDetail.ts');
const { setLayoutTraits } =
  await import('../../src/lib/presentation/layoutMode.ts');
const { closePanel, getPanelEntries, openPanel } =
  await import('../../src/lib/presentation/panelStore.ts');

const diff = {
  id: 'diff',
  Component: () => null,
  panel: true,
  presentation: { style: 'push' },
  title: 'diff',
};
const session = (id) => ({ session: { id } });
const wide = { horizontal: 'regular', width: 951, height: 669 };
const folded = { horizontal: 'compact', width: 466, height: 678 };

test('a wide layout shows an opened session in the split and closes a panel from another session', async () => {
  setLayoutTraits(wide);
  const presented = [];
  const presentCompact = async (value) => void presented.push(value);
  await showHomeSession(session('a'), 'scope', presentCompact);
  void openPanel(diff, { path: 'a.ts' }, 'replace');
  await showHomeSession(session('a'), 'scope', presentCompact);
  assert.equal(getPanelEntries().length, 1);
  await showHomeSession(session('b'), 'scope', presentCompact);
  assert.equal(getPanelEntries().length, 0);
  assert.equal(getHomeDetail('scope').value.session.id, 'b');
  assert.deepEqual(presented, []);
  setHomeDetail(undefined);
});

test('a compact layout presents the session instead of filling the split', async () => {
  setLayoutTraits(folded);
  const presented = [];
  await showHomeSession(session('c'), 'scope', async (value) => {
    presented.push(value);
  });
  assert.deepEqual(presented, [session('c')]);
  assert.equal(getHomeDetail('scope'), undefined);
  closePanel();
});

test('a detail opened in another account or workspace reads as empty', () => {
  setHomeDetail(session('d'), 'first');
  assert.equal(getHomeDetail('second'), undefined);
  assert.equal(getHomeDetail('first').value.session.id, 'd');
  setHomeDetail(undefined);
});
