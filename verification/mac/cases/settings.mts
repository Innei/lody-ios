import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import type { Session } from '../lib/verify.mts';
import {
  capture,
  clickText,
  element,
  elements,
  expect,
  openScene,
  waitForDump,
} from '../lib/verify.mts';

const pages = [
  'account',
  'general',
  'appearance',
  'keyboard',
  'workspace',
  'machines',
  'projects',
  'about',
];

async function open(session: Session, page: string, control: string) {
  await clickText(session, `settings-${page}`);
  return waitForDump(session, (dump) => !!element(dump, control));
}

export async function settings(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'settings', appearance);
    const ready = await waitForDump(
      session,
      (dump) => !!element(dump, 'settings-general-queue'),
    );
    await writeFile(
      join(session.output, `settings-elements-${appearance}.json`),
      JSON.stringify(elements(ready), null, 1),
    );
    const missing = pages.filter((page) => !element(ready, `settings-${page}`));
    expect(missing.length === 0, `sidebar rows missing: ${missing.join(', ')}`);
    await capture(session, `settings-general-${appearance}`);
  }
  await clickText(session, 'Steer');
  await waitForDump(session, (dump) =>
    elements(dump).some((item) => item.label === 'Steer' && item.value === '1'),
  );
  await open(session, 'appearance', 'settings-appearance-theme-dark');
  await clickText(session, 'settings-appearance-theme-dark');
  await waitForDump(
    session,
    (dump) =>
      element(dump, 'settings-appearance-theme-dark')?.selected === true,
  );
  await open(session, 'machines', 'settings-machines-rename-m-studio');
  await open(session, 'projects', 'settings-projects-share-m-studio:local:p1');
  await open(session, 'workspace', 'settings-workspace-name');
  await open(session, 'about', 'settings-about-version');
  await capture(session, 'settings-about');
}
