import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {
  formatTemplate,
  matchLocale,
  pluralSuffix,
} from '../src/i18n/format.ts';

const catalog = (name) =>
  JSON.parse(
    fs.readFileSync(
      new URL(`../locales/${name}.json`, import.meta.url),
      'utf8',
    ),
  );

test('locale matcher folds simplified Chinese tags and falls back to English', () => {
  assert.equal(matchLocale('zh-Hans'), 'zh-Hans');
  assert.equal(matchLocale('zh-Hans-CN'), 'zh-Hans');
  assert.equal(matchLocale('zh-CN'), 'zh-Hans');
  assert.equal(matchLocale('zh-SG'), 'zh-Hans');
  assert.equal(matchLocale('zh'), 'zh-Hans');
  assert.equal(matchLocale('en'), 'en');
  assert.equal(matchLocale('en-GB'), 'en');
  assert.equal(matchLocale('zh-Hant-TW'), 'en');
  assert.equal(matchLocale('ja-JP'), 'en');
  assert.equal(matchLocale(undefined), 'en');
});

test('template substitution runs once and keeps unknown placeholders', () => {
  assert.equal(
    formatTemplate('{a} and {b} and {a}', { a: '1', b: 2 }),
    '1 and 2 and 1',
  );
  assert.equal(formatTemplate('hi {name}', {}), 'hi {name}');
  assert.equal(formatTemplate('hi {name}', { name: '{name}' }), 'hi {name}');
  assert.equal(
    formatTemplate('{outer}', { outer: '{inner}', inner: 'no' }),
    '{inner}',
  );
  assert.equal(formatTemplate('{count}', { count: Infinity }), '{count}');
  assert.equal(formatTemplate('plain', { unused: 'x' }), 'plain');
});

test('plural selection follows the locale', () => {
  assert.equal(pluralSuffix('en', 0), '.other');
  assert.equal(pluralSuffix('en', 1), '.one');
  assert.equal(pluralSuffix('en', 2), '.other');
  assert.equal(pluralSuffix('zh-Hans', 0), '.other');
  assert.equal(pluralSuffix('zh-Hans', 1), '.other');
  assert.equal(pluralSuffix('zh-Hans', 2), '.other');
});

test('both catalogs resolve the same plural groups', () => {
  const en = catalog('en');
  const zh = catalog('zh-Hans');
  const render = (locale, table, base, count) =>
    formatTemplate(table[`${base}${pluralSuffix(locale, count)}`], { count });

  assert.equal(render('en', en, 'settings.machineCount', 0), '0 computers');
  assert.equal(render('en', en, 'settings.machineCount', 1), '1 computer');
  assert.equal(render('en', en, 'settings.machineCount', 2), '2 computers');
  assert.equal(render('zh-Hans', zh, 'settings.machineCount', 1), '1 台电脑');
  assert.equal(render('zh-Hans', zh, 'settings.machineCount', 2), '2 台电脑');
});
