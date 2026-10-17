import test from 'node:test';
import assert from 'node:assert/strict';
import { permissionChannel } from '../../src/features/sessions/permissionTarget.ts';

const target = { requestId: 'r1' };

test('a chat remounted while its permission sheet is open reuses that sheet', () => {
  const first = permissionChannel('s1');
  const releaseMount = first.retain();
  first.gate.opened();
  const releaseSheet = first.retain();
  const heard = [];
  const stop = first.source((state) => heard.push(state));
  releaseMount();

  const second = permissionChannel('s1');
  const releaseRemount = second.retain();
  assert.equal(second, first);
  assert.equal(second.gate.shouldOpen(target), false);
  assert.equal(second.gate.canPrompt(), false);
  second.publish({ ready: true, target });
  assert.deepEqual(heard.at(-1), { ready: true, target });

  stop();
  first.gate.settled({ status: 'completed', value: { requestId: 'r1' } });
  releaseSheet();
  releaseRemount();
});

test('returning to a chat after every holder let go starts a fresh gate', () => {
  const first = permissionChannel('s2');
  const release = first.retain();
  first.gate.opened();
  first.gate.settled({ status: 'cancelled' });
  assert.equal(first.gate.canPrompt(), false);
  release();

  const next = permissionChannel('s2');
  assert.notEqual(next, first);
  assert.equal(next.gate.canPrompt(), true);
  assert.equal(next.gate.shouldOpen(target), true);
});
