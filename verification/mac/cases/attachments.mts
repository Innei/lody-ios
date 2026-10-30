import type { Dump, Session } from '../lib/verify.mts';
import {
  capture,
  clickText,
  dropFiles,
  expect,
  find,
  openScene,
  pasteInto,
  pressReturn,
  typeInto,
  waitForDump,
  waitForText,
} from '../lib/verify.mts';

const pills = (dump: Dump) =>
  find(dump, (node) => node.identifier === 'composer-attachments').flatMap(
    (strip) =>
      (strip.children ?? []).flatMap((pill) =>
        (pill.children ?? [])
          .map((child) => child.text)
          .filter(
            (text): text is string =>
              !!text && !text.includes('KB') && !text.includes('bytes'),
          ),
      ),
  );

const draftIs = (names: string[]) => (dump: Dump) =>
  JSON.stringify(pills(dump)) === JSON.stringify(names);

export async function attachments(session: Session) {
  await openScene(session, 'attachments', 'light');
  await waitForText(session, 'Reply…');

  await clickText(session, 'composer-attach');
  await waitForDump(session, draftIs(['notes.txt', 'diagram.png']));

  await pasteInto(session, 'Reply…');
  await waitForDump(
    session,
    draftIs(['notes.txt', 'diagram.png', 'Pasted Image.png']),
  );

  await dropFiles(session, 'transcript');
  const dropped = await waitForDump(
    session,
    draftIs([
      'notes.txt',
      'diagram.png',
      'Pasted Image.png',
      'lody-verify-dropped.txt',
    ]),
  );
  expect(
    find(dropped, (node) => node.identifier === 'composer-send')[0]?.enabled ===
      true,
    'files alone can be sent',
  );
  await capture(session, 'attachments-draft-light');

  await clickText(session, 'Remove');
  await waitForDump(
    session,
    draftIs(['diagram.png', 'Pasted Image.png', 'lody-verify-dropped.txt']),
  );

  await typeInto(session, 'Reply…', 'Here are the files');
  await pressReturn(session);
  const restored = await waitForDump(
    session,
    (dump) =>
      draftIs(['diagram.png', 'Pasted Image.png', 'lody-verify-dropped.txt'])(
        dump,
      ) &&
      find(dump, (node) => node.identifier === 'composer-input')[0]?.text ===
        'Here are the files',
  );
  expect(
    pills(restored).length === 3,
    'a failed send restores the files and the text',
  );
  await capture(session, 'attachments-restored-light');
}
