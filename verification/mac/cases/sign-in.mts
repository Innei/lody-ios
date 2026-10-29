import type { Session } from '../lib/verify.mts';
import {
  capture,
  clickText,
  expect,
  find,
  openScene,
  waitForDump,
  waitForText,
} from '../lib/verify.mts';

export async function signIn(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'sign-in', appearance);
    await waitForText(session, 'Sign in to Lody');
    const ready = await waitForDump(
      session,
      (dump) =>
        find(
          dump,
          (node) =>
            node.text === 'Sign In with Browser' && node.enabled === true,
        ).length === 1,
    );
    expect(
      find(ready, (node) => node.identifier === 'sign-in-code').length === 0,
      'no device code before sign-in starts',
    );
    await capture(session, `sign-in-${appearance}`);
  }

  await clickText(session, 'Sign In with Browser');
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
    find(code, (node) => node.text === 'Open Browser Again').length === 1,
    'the primary button reopens the browser',
  );
  await capture(session, 'sign-in-code-dark');
  await clickText(session, 'Cancel');
  await waitForDump(
    session,
    (dump) =>
      find(dump, (node) => node.identifier === 'sign-in-code').length === 0,
  );
}
