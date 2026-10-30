import type { Session } from '../lib/verify.mts';
import { capture, expect, openScene, waitForDump } from '../lib/verify.mts';

export async function accent(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'accent', appearance);
    const ready = await waitForDump(
      session,
      (dump) =>
        dump.windows.filter((window) => window.identifier === 'catalog-scene')
          .length === 2,
    );
    expect(ready.accent === 'system', 'the scene starts on the system accent');
    await capture(session, `accent-${appearance}`);
  }
}
