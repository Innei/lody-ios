import type { Session } from '../lib/verify.mts';
import {
  capture,
  clickText,
  expect,
  find,
  openScene,
  typeInto,
  waitForDump,
  waitForText,
} from '../lib/verify.mts';

const visible = (id: string) => (dump: Parameters<typeof find>[0]) =>
  find(dump, (n) => n.identifier === id).length > 0;
const text =
  (id: string, value: string) => (dump: Parameters<typeof find>[0]) =>
    find(dump, (n) => n.identifier === id && (n.text ?? '').includes(value))
      .length > 0;

export async function coreParity(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'core-parity', appearance);
    await waitForDump(session, visible('question-submit'));
    await capture(session, `core-questions-${appearance}`);
    await clickText(session, 'question-option-0');
    await clickText(session, 'question-option-1');
    await clickText(session, 'Notes');
    await typeInto(session, 'question-custom', 'Run the focused native checks');
    await clickText(session, 'question-submit');
    await waitForDump(session, (d) => !visible('question-submit')(d));
    await clickText(session, 'composer-queue');
    await waitForText(session, 'Queued messages');
    await clickText(session, 'queue-edit-0');
    await waitForDump(session, visible('queue-editor'));
    await typeInto(session, 'queue-editor', 'Add arrow-key navigation');
    await capture(session, `core-queue-edit-${appearance}`);
    await clickText(session, 'queue-save');
    await waitForText(session, 'Add arrow-key navigation');
    await clickText(session, 'queue-down-0');
    await waitForDump(
      session,
      text('queue-message-1', 'Add arrow-key navigation'),
    );
    await clickText(session, 'queue-remove-2');
    await waitForDump(session, (d) => !visible('queue-message-2')(d));
    await capture(session, `core-queue-${appearance}`);
    await clickText(session, 'queue-steer-0');
    await waitForDump(
      session,
      text('queue-message-0', 'Add arrow-key navigation'),
    );
    await clickText(session, 'queue-close');
    await waitForDump(session, (d) => !visible('queue-close')(d));
    await clickText(session, 'transcript-changes');
    await waitForDump(session, text('diff-patch', '+  return "Lody for Mac"'));
    await capture(session, `core-turn-diff-${appearance}`);
    await clickText(session, 'All changes');
    await waitForDump(session, text('diff-base', 'main'));
    await clickText(session, 'diff-file-1');
    await waitForDump(session, text('diff-status', 'Couldn’t load'));
    await clickText(session, 'diff-refresh');
    await waitForDump(session, text('diff-patch', 'Lody for Mac'));
    await capture(session, `core-session-diff-${appearance}`);
    await clickText(session, 'diff-file-2');
    await waitForDump(session, text('diff-status', 'binary'));
    await capture(session, `core-binary-diff-${appearance}`);
    await clickText(session, 'diff-close');
    await clickText(session, 'composer-stop');
    await waitForDump(session, (d) => !visible('composer-stop')(d));
    await capture(session, `core-stopped-${appearance}`);
  }
}

export async function coreDraft(session: Session) {
  for (const appearance of ['light', 'dark'] as const) {
    await openScene(session, 'core-draft', appearance);
    await typeInto(
      session,
      'composer-input',
      'Keep this draft and both attachments',
    );
    await clickText(session, 'composer-attach');
    await waitForText(session, 'notes.txt');
    await clickText(session, 'Another session');
    const other = await waitForDump(
      session,
      (d) => !text('composer-input', 'Keep this draft')(d),
    );
    expect(
      !find(other, (n) => (n.text ?? '').includes('notes.txt')).length,
      'attachment belongs to its original conversation',
    );
    await clickText(session, 'Draft session');
    await waitForDump(session, text('composer-input', 'Keep this draft'));
    await waitForText(session, 'notes.txt');
    await clickText(session, 'Reopen composer');
    await waitForDump(session, text('composer-input', 'Keep this draft'));
    await waitForText(session, 'diagram.png');
    await capture(session, `core-draft-restored-${appearance}`);
  }
}
