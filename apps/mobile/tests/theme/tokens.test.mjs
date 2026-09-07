import assert from 'node:assert/strict';
import test from 'node:test';
import {
  accent,
  clampFontScale,
  contrastRatio,
  space,
  systemBackground,
  type as typeScale,
} from '../../src/theme/tokens.ts';

test('accent stays legible on both system backgrounds', () => {
  assert.ok(
    contrastRatio(accent.light, systemBackground.light) >= 4.5,
    `light accent contrast ${contrastRatio(accent.light, systemBackground.light)}`,
  );
  assert.ok(
    contrastRatio(accent.dark, systemBackground.dark) >= 4.5,
    `dark accent contrast ${contrastRatio(accent.dark, systemBackground.dark)}`,
  );
});

test('contrast ratio is symmetric and anchored', () => {
  assert.equal(contrastRatio('#FFFFFF', '#000000').toFixed(2), '21.00');
  assert.equal(
    contrastRatio('#000000', '#FFFFFF'),
    contrastRatio('#FFFFFF', '#000000'),
  );
});

test('font scale clamps below accessibility sizes', () => {
  assert.equal(clampFontScale(0.5), 14 / 17);
  assert.equal(clampFontScale(1), 1);
  assert.equal(clampFontScale(3.1), 23 / 17);
});

test('type roles carry a line height taller than the size', () => {
  for (const [role, spec] of Object.entries(typeScale)) {
    assert.ok(spec.lineHeight > spec.size, `${role} line height`);
  }
});

test('spacing scale has no off-ladder values', () => {
  assert.deepEqual([...space], [4, 8, 12, 16, 20, 24]);
});
