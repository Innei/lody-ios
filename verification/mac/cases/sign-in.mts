import type { Session } from '../lib/verify.mts';
import {
  capture,
  clickText,
  expect,
  find,
  openScene,
  scene,
  waitForDump,
  waitForText,
} from '../lib/verify.mts';

export async function signIn(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'sign-in', appearance);
    await waitForText(session, 'Welcome to Lody');
    const ready = await waitForDump(
      session,
      (dump) =>
        find(
          dump,
          (node) =>
            node.text === 'Continue in Browser' && node.enabled === true,
        ).length === 1,
    );
    expect(
      scene(ready)?.appearance === 'NSAppearanceNameDarkAqua',
      `the onboarding window stays dark in ${appearance} mode`,
    );
    expect(
      find(ready, (node) => node.identifier === 'sign-in-visual').length === 1,
      'the jellyfish visual fills the left panel',
    );
    expect(
      find(ready, (node) => node.identifier === 'sign-in-legal').length === 1,
      'the terms and privacy notice is shown',
    );
    expect(
      find(ready, (node) => node.identifier === 'sign-in-code').length === 0,
      'no device code before sign-in starts',
    );
    await capture(session, `sign-in-${appearance}`);
  }

  await clickText(session, 'Continue in Browser');
  await waitForText(session, 'WXYZ-1234');
  const code = await waitForDump(
    session,
    (dump) =>
      find(
        dump,
        (node) =>
          node.identifier === 'sign-in-code' && node.text === 'WXYZ-1234',
      ).length === 1,
  );
  expect(
    find(code, (node) => node.text === 'Confirm in Your Browser').length === 1,
    'the heading asks to confirm in the browser',
  );
  expect(
    find(code, (node) => node.text === 'Open Browser Again').length === 1,
    'the primary button reopens the browser',
  );
  expect(
    find(code, (node) => node.identifier === 'sign-in-copy').length === 1,
    'the code has a copy button',
  );
  expect(
    find(code, (node) => node.identifier === 'sign-in-legal').length === 0,
    'the legal notice gives way to the code',
  );
  await capture(session, 'sign-in-code-dark');
  await clickText(session, 'Cancel');
  await waitForDump(
    session,
    (dump) =>
      find(dump, (node) => node.identifier === 'sign-in-code').length === 0,
  );

  await openScene(session, 'sign-in-done', 'dark');
  await waitForText(session, 'Signed in as Innei');
  await capture(session, 'sign-in-done-dark');
}
