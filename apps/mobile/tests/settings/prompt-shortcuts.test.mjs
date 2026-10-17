import assert from 'node:assert/strict';
import test from 'node:test';
import { shortcutSections } from '../../src/features/settings/prompt-shortcuts.ts';
import { setLocale, t } from '../../src/lib/i18n/index.ts';

setLocale('en');

const entry = (id, extra = {}) => ({
  id,
  slug: id,
  name: id.toUpperCase(),
  visibility: 'private',
  ownerUserId: 'me',
  scope: {},
  dependencySummary: [],
  ...extra,
});

test('rows show only the command, without the prefix or capability sentences', () => {
  const [section] = shortcutSections([entry('review-pr')], 'me');
  const [row] = section.rows;
  assert.equal(row.subtitle, '/review-pr');
  assert.equal(row.subtitleMono, true);
  assert.equal(row.trailingSymbol, undefined);
  assert.ok(!row.subtitle.includes('shortcut:'));
});

test('templates another member owns or that need context are marked view only', () => {
  const sections = shortcutSections(
    [
      entry('mine'),
      entry('theirs', { visibility: 'workspace', ownerUserId: 'other' }),
      entry('context', { scope: { project: true } }),
    ],
    'me',
  );
  const rows = sections.flatMap((section) => section.rows);
  const marked = rows.filter((row) => row.trailingSymbol === 'eye');
  assert.deepEqual(
    marked.map((row) => row.id),
    ['context', 'theirs'],
  );
  assert.ok(
    marked.every(
      (row) => row.trailingSymbolLabel === t('settings.shortcuts.viewOnly'),
    ),
  );
});

test('private and shared sections keep their order and the shared footer is one line', () => {
  const sections = shortcutSections(
    [entry('a', { visibility: 'workspace' }), entry('b')],
    'me',
  );
  assert.deepEqual(
    sections.map((section) => section.id),
    ['private', 'workspace'],
  );
  assert.equal(sections[1].footer, t('settings.shortcuts.hintShort'));
  assert.deepEqual(shortcutSections([], 'me'), []);
});
