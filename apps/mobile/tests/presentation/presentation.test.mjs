import assert from 'node:assert/strict';
import { mock, test } from 'node:test';

let target;
let navigationError;
mock.module('expo-router', {
  namedExports: {
    router: {
      push(value) {
        target = value;
        if (navigationError) throw navigationError;
      },
    },
  },
});
const {
  present,
  getPresentationSession,
  completePresentation,
  cancelPresentation,
} = await import('../../src/presentation/presentationStore.ts');
const page = {
  id: 'test',
  Component: () => null,
  presentation: { style: 'pageSheet' },
  title: 'Test',
};
const currentId = () => Number(target.params.presentationId);

test('presentation keeps callbacks outside URLs, isolates nested sessions, settles once and releases state', async () => {
  const callback = () => 'callback result';
  const outer = present(page, { callback });
  const outerId = currentId();
  assert.deepEqual(Object.keys(target.params), ['presentationId']);
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
