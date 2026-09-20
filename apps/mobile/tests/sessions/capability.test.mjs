import assert from 'node:assert/strict';
import test from 'node:test';
import {
  effortsFor,
  validConfigValue,
} from '../../src/cloud/send/capability.ts';

test('active chat still resolves model and config-only effort ladders', () => {
  const capability = {
    reasoningEfforts: { a: ['low', 'high'] },
    configOptions: [
      { category: 'model', currentValue: 'a' },
      {
        id: 'effort',
        category: 'thought_level',
        type: 'select',
        options: [{ id: 'medium' }],
      },
    ],
  };
  assert.deepEqual(effortsFor(capability), ['low', 'high']);
  assert.deepEqual(effortsFor(capability, 'b'), ['medium']);
  assert.deepEqual(effortsFor(undefined), []);
});

test('runtime config projection retains false and rejects mismatched values', () => {
  const flag = { type: 'boolean', options: [] };
  assert.equal(validConfigValue(flag, false), true);
  assert.equal(validConfigValue(flag, 'false'), false);
  const select = { type: 'select', options: [{ id: 'auto' }] };
  assert.equal(validConfigValue(select, 'auto'), true);
  assert.equal(validConfigValue(select, 'removed'), false);
  assert.equal(validConfigValue(select, true), false);
});
