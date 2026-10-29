import type { Session } from '../lib/verify.mts';
import {
  capture,
  choose,
  expect,
  find,
  openScene,
  waitForDump,
} from '../lib/verify.mts';

export async function accent(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'accent', appearance);
    const ready = await waitForDump(
      session,
      (dump) =>
        find(dump, (node) => node.identifier === 'settings-accent').length ===
        1,
    );
    expect(ready.accent === 'system', 'the scene starts on the system accent');
    expect(
      find(ready, (node) => node.identifier === 'settings-notifications')
        .length === 1,
      'Settings offers the notifications switch',
    );
    await choose(session, 'System', 'Purple');
    await waitForDump(session, (dump) => dump.accent === 'purple');
    await capture(session, `accent-purple-${appearance}`);
    await choose(session, 'Purple', 'Orange');
    await waitForDump(session, (dump) => dump.accent === 'orange');
    await capture(session, `accent-orange-${appearance}`);
  }
}
