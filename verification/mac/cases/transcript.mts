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

export async function transcript(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'transcript', appearance);
    await waitForText(session, 'Read MainWindowController.swift');
    const ready = await waitForDump(
      session,
      (dump) =>
        find(dump, (node) => node.identifier === 'permission-card').length ===
        1,
    );
    expect(
      find(ready, (node) => node.identifier === 'transcript-user').length === 1,
      'one user turn',
    );
    expect(
      find(ready, (node) => node.identifier === 'transcript-activity').length >=
        3,
      'tool calls render as quiet activity lines',
    );
    expect(
      find(ready, (node) => node.identifier === 'transcript-prose').length ===
        1,
      'assistant prose renders as Markdown',
    );
    expect(
      find(
        ready,
        (node) => node.class.includes('Button') && node.text === 'Allow',
      ).length === 1,
      'the permission card offers Allow',
    );
    await capture(session, `transcript-${appearance}`);
  }

  await clickText(session, 'Allow');
  const answered = await waitForDump(
    session,
    (dump) =>
      find(dump, (node) => node.identifier === 'permission-card').length === 0,
  );
  expect(
    find(answered, (node) => node.identifier === 'transcript-prose').length ===
      2,
    'the reply after approval renders',
  );
  await capture(session, 'transcript-answered-dark');
}
