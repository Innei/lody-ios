import assert from 'node:assert/strict';
import { test } from 'node:test';

let target;
let navigationError;
const {
  present,
  getPresentationSession,
  completePresentation,
  cancelPresentation,
  setNavigator,
} = await import('../../src/lib/presentation/presentationStore.ts');
setNavigator((session, options) => {
  target = { session, options };
  if (navigationError) throw navigationError;
});
const page = {
  id: 'test',
  Component: () => null,
  presentation: { style: 'pageSheet' },
  title: 'Test',
};
const currentId = () => target.session.id;

test('presentation keeps callbacks with the session, isolates nested sessions, settles once and releases state', async () => {
  const callback = () => 'callback result';
  const outer = present(page, { callback });
  const outerId = currentId();
  assert.deepEqual(target.options, {
    container: undefined,
    root: undefined,
    insertAt: undefined,
  });
  assert.equal(
    getPresentationSession(outerId).params.callback(),
    'callback result',
  );
  const inner = present(page, { selected: 'inner' }, { style: 'formSheet' });
  const innerId = currentId();
  assert.notEqual(innerId, outerId);
  assert.equal(completePresentation(innerId, 'saved'), true);
  assert.equal(cancelPresentation(innerId), false);
  assert.deepEqual(await inner, { status: 'completed', value: 'saved' });
  assert.equal(getPresentationSession(innerId), undefined);
  assert.ok(getPresentationSession(outerId));
  assert.equal(cancelPresentation(outerId), true);
  assert.deepEqual(await outer, { status: 'cancelled' });
  assert.equal(getPresentationSession(outerId), undefined);
  assert.equal(completePresentation(outerId, 'late creation response'), false);
  assert.equal(cancelPresentation(outerId), false);

  navigationError = new Error('navigation unavailable');
  await assert.rejects(present(page), navigationError);
  assert.equal(getPresentationSession(currentId()), undefined);
  navigationError = undefined;
});
