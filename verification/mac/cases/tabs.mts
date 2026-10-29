import type { Session } from '../lib/verify.mts';
import {
  capture,
  expect,
  openScene,
  waitForDump,
  waitForText,
} from '../lib/verify.mts';

export async function tabs(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'tabs', appearance);
    await waitForText(session, 'Q4 roadmap');
    const ready = await waitForDump(session, (dump) =>
      dump.windows.some((window) => (window.tabs ?? []).length === 3),
    );
    const group = ready.windows.find(
      (window) => (window.tabs ?? []).length === 3,
    )!;
    expect(
      JSON.stringify(group.tabs) ===
        JSON.stringify([
          'Catalog · Build the AppKit sidebar',
          'Catalog · Landing page copy',
          'Catalog · Q4 roadmap',
        ]),
      `native tabs carry session titles: ${group.tabs?.join(' | ')}`,
    );
    await capture(session, `tabs-${appearance}`);
  }
}
