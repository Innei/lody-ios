import type { Session } from '../lib/verify.mts';
import {
  capture,
  clickText,
  element,
  expect,
  openScene,
  route,
  waitForDump,
} from '../lib/verify.mts';

export async function accent(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'accent', appearance);
    const ready = await waitForDump(
      session,
      (dump) =>
        dump.windows.filter((window) => window.identifier === 'catalog-scene')
          .length === 2 && !!element(dump, 'settings-appearance-accent-orange'),
    );
    expect(ready.accent === 'system', 'the scene starts on the system accent');
    await clickText(session, 'settings-appearance-accent-orange');
    await waitForDump(session, (dump) => dump.accent === 'orange');
    await capture(session, `accent-${appearance}`);
  }
  await route(session, 'reset');
  await waitForDump(session, (dump) => dump.accent === 'system');
}
