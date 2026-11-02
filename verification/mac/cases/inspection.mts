import type { Session, Dump, ViewNode } from '../lib/verify.mts';
import {
  capture,
  clickText,
  choose,
  openScene,
  typeInto,
  waitForDump,
  waitForText,
} from '../lib/verify.mts';

function visible(dump: Dump, id: string) {
  const visit = (node?: ViewNode): boolean => {
    if (!node || node.hidden) return false;
    return node.identifier === id || (node.children ?? []).some(visit);
  };
  return dump.windows.some((w) => visit(w.root));
}

export async function inspection(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'inspection', appearance);
    await waitForText(session, '2026-11-02 10:32');
    await choose(session, 'This reply', 'All workspace changes');
    await waitForText(session, 'feature/native-panel');
    await capture(session, `inspection-diff-${appearance}`);
    await clickText(
      session,
      'inspection-preview-macOS/Views/MacComposerView.swift',
    );
    await waitForDump(session, (d) => visible(d, 'inspection-text'));
    await capture(session, `inspection-code-${appearance}`);
    await clickText(session, 'inspection-wrap');
    await clickText(session, 'inspection-files');
    await waitForDump(session, (d) => visible(d, 'inspection-file-filter'));
    await typeInto(session, 'inspection-file-filter', 'preview.png');
    await clickText(session, 'preview.png');
    await waitForDump(session, (d) => visible(d, 'inspection-image'));
    await choose(session, 'Fit', '200%');
    await capture(session, `inspection-image-${appearance}`);
    await clickText(session, 'inspection-changes-tab');
    await clickText(session, 'inspection-expand');
    await capture(session, `inspection-expanded-${appearance}`);
    await clickText(session, 'inspection-expand');
    await clickText(session, 'inspection-close');
    await openScene(session, 'inspection-small', appearance);
    await waitForText(session, '2026-11-02 10:32');
    await capture(session, `inspection-small-${appearance}`);
  }
}
