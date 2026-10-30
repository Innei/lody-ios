import type { Session } from '../lib/verify.mts';
import {
  capture,
  choose,
  expect,
  find,
  openScene,
  pressReturn,
  typeInto,
  waitForDump,
  waitForText,
} from '../lib/verify.mts';

const sendEnabled = (enabled: boolean) => (dump: Parameters<typeof find>[0]) =>
  find(
    dump,
    (node) => node.identifier === 'composer-send' && node.enabled === enabled,
  ).length === 1;

const text = (dump: Parameters<typeof find>[0], identifier: string) =>
  find(dump, (node) => node.identifier === identifier)[0]?.text;

export async function composerNew(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'composer-new', appearance);
    await waitForText(session, 'Describe a task');
    const ready = await waitForDump(session, sendEnabled(false));
    expect(
      text(ready, 'composer-project') === 'lody-ios',
      'the first project is preselected',
    );
    expect(
      text(ready, 'composer-machine') === 'Mac Studio',
      'the first online machine is chosen',
    );
    expect(
      text(ready, 'composer-agent') === 'Claude Code',
      'its agent is chosen',
    );
    await capture(session, `composer-new-${appearance}`);
  }

  await typeInto(
    session,
    'Describe a task for the agent…',
    'Ship the Mac sidebar',
  );
  await waitForDump(session, sendEnabled(true));

  await choose(session, 'lody-ios', 'handbook');
  const offline = await waitForDump(session, sendEnabled(false));
  expect(
    text(offline, 'composer-notice') ===
      'No machine is online for this project',
    `a project without machines blocks sending: ${text(offline, 'composer-notice')}`,
  );
  await capture(session, 'composer-new-blocked-dark');

  await choose(session, 'handbook', 'lody-ios');
  await waitForDump(session, sendEnabled(true));
  await pressReturn(session);
  await waitForDump(
    session,
    (dump) =>
      text(dump, 'new-session-status') === 'Starting “Ship the Mac sidebar”…',
  );
}

export async function composerReply(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'composer-reply', appearance);
    await waitForText(session, 'Reply…');
    const ready = await waitForDump(session, sendEnabled(false));
    expect(
      text(ready, 'composer-context') ===
        'lody-ios  ·  mac-client  ·  Mac Studio',
      `the reply tray is read-only context: ${text(ready, 'composer-context')}`,
    );
    expect(
      text(ready, 'composer-mode') === 'Ask first',
      'permission mode sits on the left',
    );
    await capture(session, `composer-reply-${appearance}`);
  }

  await choose(session, 'Ask first', 'Full access');
  await waitForDump(
    session,
    (dump) => text(dump, 'composer-mode') === 'Full access',
  );
  await capture(session, 'composer-reply-full-access-dark');
  await typeInto(session, 'Reply…', 'Ship it');
  await waitForDump(session, sendEnabled(true));
  await pressReturn(session);
  await waitForDump(session, (dump) => {
    const sent = find(
      dump,
      (node) => node.text === 'Ship it' && !!node.inWindow,
    );
    return sent.length === 1 && sent[0].inWindow![1] < 140;
  });
  await capture(session, 'composer-reply-landed-dark');
}
