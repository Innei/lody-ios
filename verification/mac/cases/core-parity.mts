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
    await waitForDump(session, visible('composer-interruption'));
    await capture(session, `core-questions-${appearance}`);
    await clickText(session, 'question-option-0');
    await clickText(session, 'question-option-1');
    await clickText(session, 'question-next');
    await typeInto(session, 'question-custom', 'Run the focused native checks');
    await clickText(session, 'question-submit');
    await waitForDump(session, (d) => !visible('composer-interruption')(d));
    await waitForDump(session, visible('queue-message-0'));
    await capture(session, `core-queue-${appearance}`);
    await clickText(session, 'queue-message-0');
    await waitForDump(session, visible('queue-editor'));
    await typeInto(session, 'queue-editor', 'Add arrow-key navigation');
    await capture(session, `core-queue-edit-${appearance}`);
    await clickText(session, 'queue-save');
    await waitForText(session, 'Add arrow-key navigation');
    await clickText(session, 'queue-steer-0');
    await waitForDump(
      session,
      text('queue-message-0', 'Review the native sidebar'),
    );
    await typeInto(session, 'composer-input', 'Guide the running task');
    const ready = await waitForDump(session, visible('composer-send'));
    expect(
      !visible('composer-stop')(ready),
      'one iOS-style primary action changes from stop to send when there is content',
    );
    expect(
      !visible('composer-queue')(ready) && !visible('composer-changes')(ready),
      'no extra footer buttons',
    );
    await capture(session, `core-single-action-${appearance}`);
    await typeInto(session, 'composer-input', '');
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
