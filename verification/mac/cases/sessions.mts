import type { Session } from '../lib/verify.mts';
import {
  capture,
  expect,
  menu,
  nodes,
  openScene,
  scene,
  waitForDump,
  waitForText,
} from '../lib/verify.mts';

const sessionIds = (dump: Parameters<typeof scene>[0]) =>
  nodes(scene(dump)?.root)
    .map((node) => node.identifier ?? '')
    .filter((id) => id.startsWith('session-'));

export async function sessions(session: Session) {
  await openScene(session, 'sidebar');
  await waitForText(session, 'Build the AppKit sidebar');
  await menu(session, 'Pin');
  const pinned = await waitForDump(session, (dump) => {
    const ids = sessionIds(dump);
    return ids[0] === 'session-s-mac' && ids[1] === 'session-s-plan';
  });
  expect(
    sessionIds(pinned).length === 6,
    'pinning moves a row, it does not add one',
  );
  await capture(session, 'sessions-pinned');
  await menu(session, 'Archive');
  await waitForDump(
    session,
    (dump) => !sessionIds(dump).includes('session-s-mac'),
  );
  await capture(session, 'sessions-archived');

  await openScene(session, 'tabs');
  await waitForDump(session, (dump) =>
    dump.windows.some((window) => (window.tabs?.length ?? 0) === 3),
  );
  await menu(session, 'Tab 1');
  await waitForDump(session, (dump) =>
    dump.windows.some((window) =>
      (window.selectedTab ?? '').includes('Build the AppKit sidebar'),
    ),
  );
  await menu(session, 'Last Tab');
  await waitForDump(session, (dump) =>
    dump.windows.some((window) =>
      (window.selectedTab ?? '').includes('Q4 roadmap'),
    ),
  );
}
