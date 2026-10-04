import assert from 'node:assert/strict';
import test from 'node:test';
import {
  parseQuickReplies,
  reorderQuickReplies,
} from '../../src/features/settings/quickReplies.ts';

test('local replies retain exact messages, deletion and order across a save/load', () => {
  const first = {
    id: 'one',
    label: 'Review',
    message: '  Check this:\n    code()\n',
  };
  const second = {
    id: 'two',
    label: 'Push',
    message: 'Commit and push this task.',
  };
  const items = [first, second];
  assert.deepEqual(
    parseQuickReplies(
      JSON.stringify(reorderQuickReplies(items, ['two', 'one'])),
    ),
    [second, first],
  );
  assert.deepEqual(
    parseQuickReplies('[]'),
    [],
    'deleting all items must not restore defaults',
  );
  assert.equal(parseQuickReplies('broken'), null);
  assert.deepEqual(
    parseQuickReplies(
      JSON.stringify([
        null,
        first,
        { ...first, message: 'duplicate' },
        { ...second, label: ' ' },
      ]),
    ),
    [first],
  );
  assert.equal(reorderQuickReplies(items, ['one', 'one']), items);
  assert.equal(reorderQuickReplies(items, ['two', 'missing']), items);
  assert.equal(reorderQuickReplies(items, ['two']), items);
});
