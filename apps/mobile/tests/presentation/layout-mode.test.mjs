import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  getLayoutMode,
  guessLayoutTraits,
  layoutModeFor,
  setLayoutTraits,
  subscribeLayoutMode,
} from '../../src/lib/presentation/layoutMode.ts';

test('a compact width class is the phone layout whatever the aspect', () => {
  assert.equal(
    layoutModeFor({ horizontal: 'compact', width: 466, height: 678 }),
    'compact',
  );
  assert.equal(
    layoutModeFor({ horizontal: 'compact', width: 594, height: 466 }),
    'compact',
  );
});

test('a regular width class wider than tall is the wide layout on iPad and an open Duo alike', () => {
  assert.equal(
    layoutModeFor({ horizontal: 'regular', width: 1180, height: 820 }),
    'wide',
  );
  assert.equal(
    layoutModeFor({ horizontal: 'regular', width: 951, height: 669 }),
    'wide',
  );
});

test('a regular width class taller than wide is the tall layout', () => {
  assert.equal(
    layoutModeFor({ horizontal: 'regular', width: 820, height: 1180 }),
    'tall',
  );
  assert.equal(
    layoutModeFor({ horizontal: 'regular', width: 669, height: 951 }),
    'tall',
  );
});

test('before the native trait arrives, the width guesses the class', () => {
  assert.equal(guessLayoutTraits(466, 678).horizontal, 'compact');
  assert.equal(guessLayoutTraits(951, 669).horizontal, 'regular');
  assert.equal(guessLayoutTraits(669, 951).horizontal, 'regular');
});

test('subscribers hear mode changes once, not repeated traits of the same mode', () => {
  const heard = [];
  const unsubscribe = subscribeLayoutMode(() => heard.push(getLayoutMode()));
  setLayoutTraits({ horizontal: 'regular', width: 951, height: 669 });
  setLayoutTraits({ horizontal: 'regular', width: 900, height: 669 });
  setLayoutTraits({ horizontal: 'compact', width: 466, height: 678 });
  setLayoutTraits({ horizontal: 'regular', width: 669, height: 951 });
  unsubscribe();
  setLayoutTraits({ horizontal: 'regular', width: 951, height: 669 });
  assert.deepEqual(heard, ['wide', 'compact', 'tall']);
  assert.equal(getLayoutMode(), 'wide');
});
