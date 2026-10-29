import type { Session } from '../lib/verify.mts';
import {
  capture,
  clickText,
  expect,
  find,
  nodes,
  openScene,
  scene,
  waitForDump,
  waitForText,
} from '../lib/verify.mts';

const order = (ids: string[], dumpIds: string[]) =>
  ids.every(
    (id, index) =>
      index === 0 || dumpIds.indexOf(ids[index - 1]!) < dumpIds.indexOf(id),
  );

export async function sidebar(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'sidebar', appearance);
    await waitForText(session, 'Build the AppKit sidebar');
    const ready = await waitForDump(
      session,
      (dump) =>
        find(dump, (node) => node.identifier === 'session-s-mac').length === 1,
    );
    const ids = nodes(scene(ready)?.root)
      .map((node) => node.identifier ?? '')
      .filter((id) => id.startsWith('session-'));
    expect(
      !ids.includes('session-s-old'),
      'archived sessions stay out of the sidebar',
    );
    expect(
      order(
        [
          'session-s-plan',
          'session-s-mac',
          'session-s-review',
          'session-s-tabs',
          'session-s-landing',
        ],
        ids,
      ),
      `pinned first, then projects by recency: ${ids.join(', ')}`,
    );
    expect(
      find(
        ready,
        (node) =>
          node.identifier === 'sidebar-approvals' &&
          node.text === 'Needs Approval · 1',
      ).length === 1,
      'the approval shortcut counts the waiting session',
    );
    expect(
      find(
        ready,
        (node) =>
          node.identifier === 'sidebar-machines' &&
          node.text === 'Machines online: 2',
      ).length === 1,
      'the footer reports machine presence',
    );
    await capture(session, `sidebar-${appearance}`);
  }

  await clickText(session, 'Landing page copy');
  await waitForDump(
    session,
    (dump) => scene(dump)?.title === 'Catalog · Landing page copy',
  );
}
